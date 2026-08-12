package main

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

// ParseFIODir scans a directory for FIO .log files and parses each one.
func ParseFIODir(dir string) ([]FIOResult, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("read dir %s: %w", dir, err)
	}

	var results []FIOResult
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".log") {
			continue
		}
		if strings.Contains(e.Name(), "prewrite") {
			continue
		}
		path := filepath.Join(dir, e.Name())
		r, err := parseFIOLog(path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "WARN: skip %s: %v\n", e.Name(), err)
			continue
		}
		results = append(results, r)
	}
	return results, nil
}

func parseFIOLog(path string) (FIOResult, error) {
	var r FIOResult
	base := strings.TrimSuffix(filepath.Base(path), ".log")
	r.FileName = base

	if err := parseFileName(base, &r); err != nil {
		return r, err
	}

	f, err := os.Open(path)
	if err != nil {
		return r, err
	}
	defer f.Close()

	// Read all lines, find the LAST "All clients:" block
	var lines []string
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		return r, err
	}

	// Find last "All clients:" line index
	lastIdx := -1
	for i := len(lines) - 1; i >= 0; i-- {
		if strings.Contains(lines[i], "All clients:") {
			lastIdx = i
			break
		}
	}
	if lastIdx < 0 {
		return r, fmt.Errorf("no 'All clients:' found")
	}

	// Parse from lastIdx onward
	parseAllClientsBlock(lines[lastIdx:], &r)
	return r, nil
}

// parseFileName extracts fileSize, blockSize, numJobs, op from name like "3G_4K_64job_randread"
func parseFileName(name string, r *FIOResult) error {
	// Handle formats: "16M_4K_128job_randwrite", "3G_1M_64job_read8write2"
	parts := strings.Split(name, "_")
	if len(parts) < 4 {
		return fmt.Errorf("unexpected filename format: %s", name)
	}
	r.FileSize = parts[0]
	r.BlockSize = parts[1]
	r.NumJobs = parts[2]
	r.Op = strings.Join(parts[3:], "_") // handle "read8write2" which is single token
	return nil
}

var (
	reIOPS = regexp.MustCompile(`IOPS=([0-9.]+)([kM]?)`)
	reBW   = regexp.MustCompile(`BW=([0-9.]+)([A-Za-z/]+)`)
	reClat = regexp.MustCompile(`avg=([0-9.]+)`)
)

func parseAllClientsBlock(lines []string, r *FIOResult) {
	// State machine: look for "read:", "write:", "clat" lines
	var inRead, inWrite bool
	var readClatDone, writeClatDone bool

	for i := 1; i < len(lines); i++ {
		line := strings.TrimSpace(lines[i])

		// Detect read/write summary lines
		if strings.HasPrefix(line, "read: IOPS=") {
			inRead = true
			inWrite = false
			r.ReadIOPS = parseIOPSValue(line)
			r.ReadBW = parseBWValue(line)
			continue
		}
		if strings.HasPrefix(line, "write: IOPS=") {
			inWrite = true
			inRead = false
			r.WriteIOPS = parseIOPSValue(line)
			r.WriteBW = parseBWValue(line)
			continue
		}

		// Parse clat avg
		if strings.Contains(line, "clat (usec)") || strings.Contains(line, "clat (msec)") {
			isMs := strings.Contains(line, "clat (msec)")
			m := reClat.FindStringSubmatch(line)
			if m != nil {
				avg, _ := strconv.ParseFloat(m[1], 64)
				if isMs {
					avg *= 1000 // convert to usec
				}
				if inRead && !readClatDone {
					r.ReadClatAvg = avg
					readClatDone = true
				} else if inWrite && !writeClatDone {
					r.WriteClatAvg = avg
					writeClatDone = true
				}
			}
			continue
		}

		// Parse latency distribution
		if strings.HasPrefix(line, "lat (usec)") || strings.HasPrefix(line, "lat (msec)") {
			buckets := parseLatDist(line)
			r.LatDist = append(r.LatDist, buckets...)
			continue
		}

		// Stop at next section indicators
		if strings.HasPrefix(line, "cpu") || strings.HasPrefix(line, "IO depths") {
			break
		}
	}
}

func parseIOPSValue(line string) float64 {
	m := reIOPS.FindStringSubmatch(line)
	if m == nil {
		return 0
	}
	v, _ := strconv.ParseFloat(m[1], 64)
	switch m[2] {
	case "k":
		v *= 1000
	case "M":
		v *= 1_000_000
	}
	return v
}

func parseBWValue(line string) float64 {
	m := reBW.FindStringSubmatch(line)
	if m == nil {
		return 0
	}
	v, _ := strconv.ParseFloat(m[1], 64)
	unit := m[2]
	// Normalize to GiB/s
	switch {
	case strings.HasPrefix(unit, "Gi"):
		// already GiB/s
	case strings.HasPrefix(unit, "Mi"):
		v /= 1024
	case strings.HasPrefix(unit, "Ki"):
		v /= (1024 * 1024)
	}
	return v
}

// parseLatDist parses a line like "lat (usec) : 250=36.52%, 500=63.44%, 750=0.03%"
func parseLatDist(line string) []LatBucket {
	// Find the part after ":"
	idx := strings.Index(line, ":")
	if idx < 0 {
		return nil
	}
	isMs := strings.Contains(line[:idx], "msec")
	data := line[idx+1:]

	var buckets []LatBucket
	pairs := strings.Split(data, ",")
	for _, p := range pairs {
		p = strings.TrimSpace(p)
		eqIdx := strings.Index(p, "=")
		if eqIdx < 0 {
			continue
		}
		boundStr := strings.TrimSpace(p[:eqIdx])
		pctStr := strings.TrimSuffix(strings.TrimSpace(p[eqIdx+1:]), "%")
		pct, err := strconv.ParseFloat(pctStr, 64)
		if err != nil || pct == 0 {
			continue
		}

		var label string
		if isMs {
			label = boundStr + "ms"
		} else {
			label = boundStr + "µs"
		}
		buckets = append(buckets, LatBucket{Label: label, Pct: pct})
	}
	return buckets
}
