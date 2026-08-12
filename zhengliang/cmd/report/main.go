package main

import (
	"flag"
	"fmt"
	"log"
	"os"
)

func main() {
	fioDir := flag.String("fio-dir", ".", "Directory containing FIO .log files")
	vdbLog := flag.String("vdbench-log", "", "Path to vdbench nohup.out (optional)")
	output := flag.String("output", "report.html", "Output HTML file path")
	flag.Parse()

	var report Report

	// Parse FIO logs
	fioResults, err := ParseFIODir(*fioDir)
	if err != nil {
		log.Fatalf("parse FIO: %v", err)
	}
	report.FIOResults = fioResults
	fmt.Printf("Parsed %d FIO test results\n", len(fioResults))
	for _, r := range fioResults {
		fmt.Printf("  fio: %s → read=%.1fM/%.1fGiB/s write=%.1fM/%.1fGiB/s\n",
			r.FileName, r.ReadIOPS/1e6, r.ReadBW, r.WriteIOPS/1e6, r.WriteBW)
	}

	// Parse Vdbench if provided
	if *vdbLog != "" {
		vdbResults, err := ParseVdbench(*vdbLog)
		if err != nil {
			log.Fatalf("parse Vdbench: %v", err)
		}
		report.VdbenchResults = vdbResults
		fmt.Printf("Parsed %d Vdbench test results\n", len(vdbResults))
	}

	// Generate report
	out, err := os.Create(*output)
	if err != nil {
		log.Fatalf("create output: %v", err)
	}
	defer out.Close()

	if err := RenderHTML(out, &report); err != nil {
		log.Fatalf("render: %v", err)
	}
	fmt.Printf("Report written to %s\n", *output)
}
