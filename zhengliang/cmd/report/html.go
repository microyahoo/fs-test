package main

import (
	"html/template"
	"io"
	"math"
	"sort"
	"strings"
)

var funcMap = template.FuncMap{
	"fmtIOPS":    fmtIOPS,
	"fmtBW":      fmtBW,
	"fmtBWMiB":   fmtBWFromMiB,
	"fmtLat":     fmtLatency,
	"fmtResp":    fmtRespMs,
	"latCls":     latClass,
	"latClsMs":   latClassMs,
	"isNaN":      func(v float64) bool { return math.IsNaN(v) },
	"gt":         func(a, b float64) bool { return a > b },
	"pctStr":     func(b LatBucket) string { return b.Label },
	"safeHTML":   func(s string) template.HTML { return template.HTML(s) },
}

const htmlTemplate = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>FIO + Vdbench 性能测试报告</title>
<style>
:root{--bg:#f8f9fa;--card:#fff;--text:#1a1a2e;--muted:#6b7280;--border:#e5e7eb;--accent:#2563eb;--accent-l:#dbeafe;--green:#059669;--green-l:#d1fae5;--orange:#d97706;--orange-l:#fef3c7;--red:#dc2626;--red-l:#fee2e2;--purple:#7c3aed;--purple-l:#ede9fe;}
*{margin:0;padding:0;box-sizing:border-box;}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Noto Sans SC",sans-serif;background:var(--bg);color:var(--text);line-height:1.6;padding:24px;}
.container{max-width:1300px;margin:0 auto;}
h1{font-size:24px;font-weight:700;margin-bottom:6px;}
.meta{font-size:12px;color:var(--muted);margin-bottom:20px;display:flex;gap:10px;flex-wrap:wrap;}
.meta span{background:var(--card);padding:3px 10px;border-radius:5px;border:1px solid var(--border);}
.badge-ok{background:var(--green-l)!important;color:var(--green)!important;border-color:var(--green)!important;}
.section{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:18px 22px;margin-bottom:14px;}
.section h2{font-size:16px;font-weight:700;margin-bottom:12px;padding-bottom:6px;border-bottom:2px solid var(--border);}
.section h3{font-size:13px;font-weight:600;color:var(--muted);margin:14px 0 8px;}
table{width:100%;border-collapse:collapse;font-size:13px;}
th,td{padding:8px 12px;text-align:left;border-bottom:1px solid var(--border);}
th{font-size:11px;color:var(--muted);font-weight:600;text-transform:uppercase;background:var(--bg);}
td{font-variant-numeric:tabular-nums;}
.r{text-align:right;}
.b{font-weight:700;}
.c-good{color:var(--green);}
.c-warn{color:var(--orange);font-weight:600;}
.c-bad{color:var(--red);font-weight:700;}
.note{font-size:12px;color:var(--muted);background:var(--bg);padding:10px 14px;border-radius:6px;margin-top:10px;line-height:1.5;}
.note b{color:var(--text);}
.tag{display:inline-block;padding:2px 8px;border-radius:3px;font-size:11px;font-weight:600;}
.tag-fio{background:var(--accent-l);color:var(--accent);}
.tag-vdb{background:var(--purple-l);color:var(--purple);}
hr.divider{border:none;border-top:2px dashed var(--border);margin:20px 0;}
</style>
</head>
<body>
<div class="container">
<h1>FIO + Vdbench 性能测试报告</h1>
<div class="meta">
  <span>📍 FIO 日志：{{.FIOCount}} 个</span>
  <span>📍 Vdbench 用例：{{.VdbCount}} 个</span>
  <span class="badge-ok">✅ 工具：fio-3.23 · vdbench 50407 · direct=1</span>
  <span>🖥 客户端：300 × Ubuntu VM</span>
</div>

<!-- ===== FIO Sections ===== -->
{{range .FIOSections}}
<div class="section">
  <h2><span class="tag tag-fio">FIO</span> {{.Title}}</h2>
  {{if .Desc}}<p style="font-size:13px;color:var(--muted);margin-bottom:10px;">{{.Desc}}</p>{{end}}
  {{range .Tables}}
  <h3>{{.Title}}</h3>
  <table>
    <thead><tr>{{range .Headers}}<th{{if .Right}} class="r"{{end}}>{{.Text}}</th>{{end}}</tr></thead>
    <tbody>
    {{range .Rows}}<tr>{{range .}}<td{{if .FullClass}} class="{{.FullClass}}"{{end}}>{{.Text}}</td>{{end}}</tr>
    {{end}}
    </tbody>
  </table>
  {{end}}
  {{if .Note}}<div class="note">{{safeHTML .Note}}</div>{{end}}
</div>
{{end}}

<hr class="divider">

<!-- ===== Vdbench Sections ===== -->
{{range .VdbSections}}
<div class="section">
  <h2><span class="tag tag-vdb">Vdbench</span> {{.Title}}</h2>
  {{if .Desc}}<p style="font-size:13px;color:var(--muted);margin-bottom:10px;">{{.Desc}}</p>{{end}}
  {{range .Tables}}
  <h3>{{.Title}}</h3>
  <table>
    <thead><tr>{{range .Headers}}<th{{if .Right}} class="r"{{end}}>{{.Text}}</th>{{end}}</tr></thead>
    <tbody>
    {{range .Rows}}<tr>{{range .}}<td{{if .FullClass}} class="{{.FullClass}}"{{end}}>{{.Text}}</td>{{end}}</tr>
    {{end}}
    </tbody>
  </table>
  {{end}}
  {{if .Note}}<div class="note">{{safeHTML .Note}}</div>{{end}}
</div>
{{end}}

</div>
</body>
</html>`

// ---------- Template data structures ----------

type THeader struct {
	Text  string
	Right bool
}

type TCell struct {
	Text  string
	Right bool
	Bold  bool
	Class string
}

func (c TCell) FullClass() string {
	var parts []string
	if c.Right {
		parts = append(parts, "r")
	}
	if c.Bold {
		parts = append(parts, "b")
	}
	if c.Class != "" {
		parts = append(parts, c.Class)
	}
	return strings.Join(parts, " ")
}

type TTable struct {
	Title   string
	Headers []THeader
	Rows    [][]TCell
}

type TSection struct {
	Title  string
	Desc   string
	Tables []TTable
	Note   string
}

type TData struct {
	FIOCount    int
	VdbCount    int
	FIOSections []TSection
	VdbSections []TSection
}

// ---------- Build sections from parsed data ----------

func buildFIOSections(results []FIOResult) []TSection {
	// Group by (fileSize, blockSize)
	type groupKey struct{ fs, bs string }
	groups := map[groupKey][]FIOResult{}
	for _, r := range results {
		k := groupKey{r.FileSize, r.BlockSize}
		groups[k] = append(groups[k], r)
	}

	// Sort each group by numJobs
	jobOrder := map[string]int{"64job": 0, "128job": 1, "256job": 2, "600job": 3}
	for k := range groups {
		sort.Slice(groups[k], func(i, j int) bool {
			return jobOrder[groups[k][i].NumJobs] < jobOrder[groups[k][j].NumJobs]
		})
	}

	var sections []TSection
	// Define section order
	sectionKeys := []groupKey{{"16M", "4K"}, {"3G", "4K"}, {"3G", "1M"}}
	sectionTitles := map[groupKey]string{
		{"16M", "4K"}: "16M 文件 4K 块大小（小文件 / cache-hot）",
		{"3G", "4K"}:  "3G 文件 4K 块大小（大文件 / cache-cold）",
		{"3G", "1M"}:  "3G 文件 1M 块大小（大块带宽）",
	}

	for _, key := range sectionKeys {
		items, ok := groups[key]
		if !ok || len(items) == 0 {
			continue
		}

		s := TSection{Title: sectionTitles[key]}

		// Split by operation
		var reads, writes, mixes []FIOResult
		for _, r := range items {
			switch r.Op {
			case "randread":
				reads = append(reads, r)
			case "randwrite":
				writes = append(writes, r)
			case "read8write2":
				mixes = append(mixes, r)
			}
		}

		rwHeaders := []THeader{{"Job", false}, {"IOPS", true}, {"带宽", true}, {"clat avg", true}}
		mixHeaders := []THeader{{"Job", false}, {"读 IOPS", true}, {"读带宽", true}, {"写 IOPS", true}, {"写带宽", true}, {"读 clat", true}, {"写 clat", true}}

		if len(reads) > 0 {
			var rows [][]TCell
			for _, r := range reads {
				rows = append(rows, []TCell{
					{Text: r.NumJobs},
					{Text: fmtIOPS(r.ReadIOPS), Right: true, Bold: true},
					{Text: fmtBW(r.ReadBW), Right: true},
					{Text: fmtLatency(r.ReadClatAvg), Right: true, Class: latClass(r.ReadClatAvg)},
				})
			}
			s.Tables = append(s.Tables, TTable{Title: "纯读 (randread)", Headers: rwHeaders, Rows: rows})
		}

		if len(writes) > 0 {
			var rows [][]TCell
			for _, r := range writes {
				rows = append(rows, []TCell{
					{Text: r.NumJobs},
					{Text: fmtIOPS(r.WriteIOPS), Right: true, Bold: true},
					{Text: fmtBW(r.WriteBW), Right: true},
					{Text: fmtLatency(r.WriteClatAvg), Right: true, Class: latClass(r.WriteClatAvg)},
				})
			}
			s.Tables = append(s.Tables, TTable{Title: "纯写 (randwrite)", Headers: rwHeaders, Rows: rows})
		}

		if len(mixes) > 0 {
			var rows [][]TCell
			for _, r := range mixes {
				rows = append(rows, []TCell{
					{Text: r.NumJobs},
					{Text: fmtIOPS(r.ReadIOPS), Right: true, Bold: true},
					{Text: fmtBW(r.ReadBW), Right: true},
					{Text: fmtIOPS(r.WriteIOPS), Right: true},
					{Text: fmtBW(r.WriteBW), Right: true},
					{Text: fmtLatency(r.ReadClatAvg), Right: true, Class: latClass(r.ReadClatAvg)},
					{Text: fmtLatency(r.WriteClatAvg), Right: true, Class: latClass(r.WriteClatAvg)},
				})
			}
			s.Tables = append(s.Tables, TTable{Title: "混合读写 (80%读 + 20%写)", Headers: mixHeaders, Rows: rows})
		}

		sections = append(sections, s)
	}
	return sections
}

func buildVdbSections(results []VdbenchResult) []TSection {
	type groupKey struct{ fs, bs string }
	groups := map[groupKey][]VdbenchResult{}
	for _, r := range results {
		k := groupKey{r.FileSize, r.BlockSize}
		groups[k] = append(groups[k], r)
	}

	jobOrder := map[string]int{"64job": 0, "128job": 1, "256job": 2}
	for k := range groups {
		sort.Slice(groups[k], func(i, j int) bool {
			return jobOrder[groups[k][i].Jobs] < jobOrder[groups[k][j].Jobs]
		})
	}

	var sections []TSection
	sectionKeys := []groupKey{{"4K", "4K"}, {"3G", "4K"}, {"3G", "1M"}}
	sectionTitles := map[groupKey]string{
		{"4K", "4K"}: "4K 小文件 4K 随机 IO（文件大小=4KiB）",
		{"3G", "4K"}: "大文件（3 GiB）4K 随机 IO",
		{"3G", "1M"}: "大文件（3 GiB）1M 大块 IO",
	}

	for _, key := range sectionKeys {
		items, ok := groups[key]
		if !ok || len(items) == 0 {
			continue
		}

		s := TSection{Title: sectionTitles[key]}

		var reads, writes, mixes []VdbenchResult
		for _, r := range items {
			switch r.Op {
			case "rand-read":
				reads = append(reads, r)
			case "rand-write":
				writes = append(writes, r)
			case "read8-write2":
				mixes = append(mixes, r)
			}
		}

		rwHeaders := []THeader{{"Job", false}, {"IOPS", true}, {"带宽", true}, {"resp avg", true}}
		mixHeaders := []THeader{{"Job", false}, {"总 IOPS", true}, {"读 IOPS", true}, {"读带宽", true}, {"写 IOPS", true}, {"写带宽", true}, {"读 resp", true}, {"写 resp", true}}

		if len(reads) > 0 {
			var rows [][]TCell
			for _, r := range reads {
				bw := fmtBWFromMiB(r.ReadMBs)
				rows = append(rows, []TCell{
					{Text: r.Jobs},
					{Text: fmtIOPS(r.TotalIOPS), Right: true, Bold: true},
					{Text: bw, Right: true},
					{Text: fmtRespMs(r.TotalResp), Right: true, Class: latClassMs(r.TotalResp)},
				})
			}
			s.Tables = append(s.Tables, TTable{Title: "纯读 (randread)", Headers: rwHeaders, Rows: rows})
		}

		if len(writes) > 0 {
			var rows [][]TCell
			for _, r := range writes {
				bw := fmtBWFromMiB(r.WriteMBs)
				rows = append(rows, []TCell{
					{Text: r.Jobs},
					{Text: fmtIOPS(r.TotalIOPS), Right: true, Bold: true},
					{Text: bw, Right: true},
					{Text: fmtRespMs(r.TotalResp), Right: true, Class: latClassMs(r.TotalResp)},
				})
			}
			s.Tables = append(s.Tables, TTable{Title: "纯写 (randwrite)", Headers: rwHeaders, Rows: rows})
		}

		if len(mixes) > 0 {
			var rows [][]TCell
			for _, r := range mixes {
				rows = append(rows, []TCell{
					{Text: r.Jobs},
					{Text: fmtIOPS(r.TotalIOPS), Right: true},
					{Text: fmtIOPS(r.ReadIOPS), Right: true, Bold: true},
					{Text: fmtBWFromMiB(r.ReadMBs), Right: true},
					{Text: fmtIOPS(r.WriteIOPS), Right: true},
					{Text: fmtBWFromMiB(r.WriteMBs), Right: true},
					{Text: fmtRespMs(r.ReadResp), Right: true, Class: latClassMs(r.ReadResp)},
					{Text: fmtRespMs(r.WriteResp), Right: true, Class: latClassMs(r.WriteResp)},
				})
			}
			s.Tables = append(s.Tables, TTable{Title: "混合读写 (80%读 + 20%写)", Headers: mixHeaders, Rows: rows})
		}

		sections = append(sections, s)
	}
	return sections
}

// RenderHTML writes the report to w.
func RenderHTML(w io.Writer, report *Report) error {
	tmpl, err := template.New("report").Funcs(funcMap).Parse(htmlTemplate)
	if err != nil {
		return err
	}

	data := TData{
		FIOCount:    len(report.FIOResults),
		VdbCount:    len(report.VdbenchResults),
		FIOSections: buildFIOSections(report.FIOResults),
		VdbSections: buildVdbSections(report.VdbenchResults),
	}

	return tmpl.Execute(w, data)
}
