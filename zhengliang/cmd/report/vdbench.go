package main

import (
	"bufio"
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
)

// ParseVdbench reads a vdbench nohup.out and returns results.
func ParseVdbench(path string) ([]VdbenchResult, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var results []VdbenchResult
	var currentName string

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 4*1024*1024), 4*1024*1024)

	for scanner.Scan() {
		line := scanner.Text()

		if strings.Contains(line, "input argument scanned:") && strings.Contains(line, "300client-") {
			idx := strings.LastIndex(line, "/")
			if idx >= 0 {
				name := strings.TrimRight(line[idx+1:], "'\"")
				name = strings.TrimSuffix(name, "'")
				currentName = name
			}
			continue
		}

		if currentName != "" && strings.Contains(line, "avg_") {
			ok, r := parseSteadyAvgLine(line)
			if ok {
				r.Name = currentName
				classifyVdbench(&r)
				replaced := false
				for i := range results {
					if results[i].Name == currentName {
						results[i] = r
						replaced = true
						break
					}
				}
				if !replaced {
					results = append(results, r)
				}
			}
		}
	}
	return results, scanner.Err()
}

func parseSteadyAvgLine(line string) (bool, VdbenchResult) {
	var r VdbenchResult
	fields := strings.Fields(line)
	if len(fields) < 15 {
		return false, r
	}
	if !strings.HasPrefix(fields[1], "avg_") {
		return false, r
	}
	tag := strings.TrimPrefix(fields[1], "avg_")
	parts := strings.SplitN(tag, "-", 2)
	if len(parts) != 2 {
		return false, r
	}
	start, err := strconv.Atoi(parts[0])
	if err != nil || start < 21 {
		return false, r
	}

	r.TotalIOPS = parseVdbFloat(fields[2])
	r.TotalResp = parseVdbFloat(fields[3])
	r.ReadPct = parseVdbFloat(fields[6])
	r.ReadIOPS = parseVdbFloat(fields[7])
	r.ReadResp = parseVdbFloat(fields[8])
	r.WriteIOPS = parseVdbFloat(fields[9])
	r.WriteResp = parseVdbFloat(fields[10])
	r.ReadMBs = parseVdbFloat(fields[11])
	r.WriteMBs = parseVdbFloat(fields[12])
	if len(fields) > 14 {
		r.XferSize, _ = strconv.ParseInt(fields[14], 10, 64)
	}
	return true, r
}

func parseVdbFloat(s string) float64 {
	if s == "NaN" {
		return math.NaN()
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return math.NaN()
	}
	return v
}

func classifyVdbench(r *VdbenchResult) {
	n := strings.TrimPrefix(r.Name, "300client-")
	for _, op := range []string{"rand-write", "rand-read", "read8-write2"} {
		if strings.HasPrefix(n, op+"-") {
			r.Op = op
			rest := strings.TrimPrefix(n, op+"-")
			parts := strings.Split(rest, "-")
			if len(parts) >= 3 {
				r.FileSize = strings.ToUpper(parts[0])
				r.BlockSize = strings.ToUpper(parts[1])
				r.Jobs = parts[2]
			}
			break
		}
	}
	// Normalize blockSize: "4K" stays "4K", "1M" stays "1M"
	if r.BlockSize == "4K" || r.BlockSize == "1M" {
		// ok
	} else {
		r.BlockSize = strings.ToUpper(r.BlockSize)
	}
	fmt.Fprintf(os.Stderr, "  vdbench: %s → fs=%s bs=%s op=%s jobs=%s\n", r.Name, r.FileSize, r.BlockSize, r.Op, r.Jobs)
}
