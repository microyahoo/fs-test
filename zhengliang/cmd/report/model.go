package main

import (
	"fmt"
	"math"
)

// LatBucket represents one latency distribution bucket.
type LatBucket struct {
	Label string  // e.g. "≤250µs", "500µs-1ms", "1-4ms", "≥4ms"
	Pct   float64 // percentage, e.g. 36.52
}

// FIOResult holds parsed results from one FIO log file's "All clients" section.
type FIOResult struct {
	FileName  string // e.g. "16M_4K_128job_randread"
	FileSize  string // "16M", "3G"
	BlockSize string // "4K", "1M"
	NumJobs   string // "64job", "128job", "256job", "600job"
	Op        string // "randread", "randwrite", "read8write2"

	ReadIOPS    float64 // absolute value, e.g. 71.2e6
	ReadBW      float64 // GiB/s
	ReadClatAvg float64 // microseconds

	WriteIOPS    float64
	WriteBW      float64 // GiB/s
	WriteClatAvg float64 // microseconds

	LatDist []LatBucket
}

// VdbenchResult holds parsed results from one vdbench test run.
type VdbenchResult struct {
	Name string // e.g. "300client-rand-write-4K-4K-64job"

	FileSize  string // "4K", "3G"
	BlockSize string // "4K", "1M"
	Jobs      string // "64job", "128job", "256job"
	Op        string // "rand-write", "rand-read", "read8-write2"

	TotalIOPS float64
	TotalResp float64 // ms
	ReadPct   float64
	ReadIOPS  float64
	ReadResp  float64 // ms
	WriteIOPS float64
	WriteResp float64 // ms
	ReadMBs   float64 // MiB/s
	WriteMBs  float64 // MiB/s
	XferSize  int64   // bytes
}

func (r *VdbenchResult) ReadGiBs() float64  { return r.ReadMBs / 1024 }
func (r *VdbenchResult) WriteGiBs() float64 { return r.WriteMBs / 1024 }
func (r *VdbenchResult) TotalMBs() float64  { return r.ReadMBs + r.WriteMBs }
func (r *VdbenchResult) TotalGiBs() float64 { return r.TotalMBs() / 1024 }

// Report holds all parsed data.
type Report struct {
	FIOResults     []FIOResult
	VdbenchResults []VdbenchResult
}

// ---------- Formatting helpers ----------

func fmtIOPS(v float64) string {
	if math.IsNaN(v) || v == 0 {
		return "—"
	}
	if v >= 1_000_000 {
		return fmt.Sprintf("%.1fM", v/1_000_000)
	}
	if v >= 1_000 {
		return fmt.Sprintf("%.0fk", v/1_000)
	}
	return fmt.Sprintf("%.0f", v)
}

func fmtBW(gibs float64) string {
	if math.IsNaN(gibs) || gibs == 0 {
		return "—"
	}
	if gibs >= 1 {
		return fmt.Sprintf("%.0f GiB/s", gibs)
	}
	return fmt.Sprintf("%.0f MiB/s", gibs*1024)
}

func fmtBWFromMiB(mibs float64) string {
	if math.IsNaN(mibs) || mibs == 0 {
		return "—"
	}
	if mibs >= 1024 {
		return fmt.Sprintf("%.0f GiB/s", mibs/1024)
	}
	return fmt.Sprintf("%.0f MiB/s", mibs)
}

func fmtLatency(usec float64) string {
	if math.IsNaN(usec) || usec == 0 {
		return "—"
	}
	if usec < 1000 {
		return fmt.Sprintf("%.0f µs", usec)
	}
	return fmt.Sprintf("%.2f ms", usec/1000)
}

func fmtRespMs(ms float64) string {
	if math.IsNaN(ms) || ms == 0 {
		return "—"
	}
	if ms < 1 {
		return fmt.Sprintf("%.3f ms", ms)
	}
	return fmt.Sprintf("%.2f ms", ms)
}

func latClass(usec float64) string {
	ms := usec / 1000
	switch {
	case ms <= 0.5:
		return "c-good"
	case ms <= 2:
		return "c-warn"
	default:
		return "c-bad"
	}
}

func latClassMs(ms float64) string {
	switch {
	case ms <= 0.5:
		return "c-good"
	case ms <= 2:
		return "c-warn"
	default:
		return "c-bad"
	}
}
