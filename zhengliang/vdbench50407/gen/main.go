// Command jobgen regenerates vdbench job files for a given hosts file.
//
// Every job file under the vdbench dir is a fixed skeleton in which only three
// sections scale with the number of hosts N:
//
//	hd=clientI,system=<host[I-1]>            (one line per host)
//	fsd=fsdI,anchor=<base>-I,<rest>          (one line per host, anchor index auto-increments)
//	fwd=fwdI,fsd=fsdI,host=clientI           (one line per host)
//
// Everything else (the fwd=default line with its operation/rdpct/threads
// quirks, the anchor base name, files/size, the rd= line, ...) is copied
// verbatim from the template, so per-file differences are preserved
// automatically without hard-coding them here.
//
// Usage:
//
//	cd gen
//	go run . -hosts ../hosts.new                 # -> ../390/390client-*
//	go run . -hosts ../hosts -prefix 21client -out ../15   # custom prefix/dir
//
// By default the output directory is named after the host count and the file
// prefix is "<N>client", matching the existing 390/ convention.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// segment kinds within a template's structure.
type segKind int

const (
	segFixed  segKind = iota // a verbatim line (messagescan, hd=default, fwd=format/default, rd=, ...)
	segHosts                 // the hd=clientI block
	segFsd                   // the fsd=fsdI block
	segFwdMap                // the fwd=fwdI,fsd=fsdI,host=clientI block
)

type segment struct {
	kind segKind
	line string // only for segFixed
}

// template is the parsed structure of one job file.
type template struct {
	suffix     string    // filename part after "<digits>client-"
	srcName    string    // original template filename (for diagnostics)
	segs       []segment // ordered structure
	anchorBase string    // fsd1 anchor with trailing -<digits> stripped
	fsdRest    string    // everything after the anchor in the fsd1 line (depth=...,openflags=...)
}

var (
	// matches a template filename like "21client-rand-read-3G-4k-128job".
	reTemplateName = regexp.MustCompile(`^(\d+)client-(.+)$`)
	// matches an fsd line; captures the index, the anchor value, and the rest.
	reFsd = regexp.MustCompile(`^fsd=fsd(\d+),anchor=([^,]*),(.*)$`)
	// matches the fwd mapping line: fwd=fwd<idx>,fsd=fsd<idx>,host=client<idx>.
	reFwdMap = regexp.MustCompile(`^fwd=fwd(\d+),fsd=fsd\d+,host=client\d+$`)
	// trailing -<digits> at the end of an anchor; the digits are the per-fsd index.
	reAnchorIdx = regexp.MustCompile(`-(\d+)$`)
)

func main() {
	var (
		hostsPath = flag.String("hosts", "", "path to the hosts file (one IP per line); required")
		tmplDir   = flag.String("templates", ".", "directory containing the <N>client-* template job files")
		outDir    = flag.String("out", "", "output directory (default: the host count, e.g. 390)")
		prefix    = flag.String("prefix", "", "output filename prefix (default: <N>client)")
		force     = flag.Bool("force", false, "overwrite an existing/non-empty output directory")
		dedup     = flag.Bool("dedup", false, "drop duplicate hosts, keeping first occurrence")
	)
	flag.Parse()

	if err := run(*hostsPath, *tmplDir, *outDir, *prefix, *force, *dedup); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(hostsPath, tmplDir, outDir, prefix string, force, dedup bool) error {
	if hostsPath == "" {
		return fmt.Errorf("-hosts is required")
	}

	hosts, err := readHosts(hostsPath, dedup)
	if err != nil {
		return err
	}
	if len(hosts) == 0 {
		return fmt.Errorf("hosts file %q contains no hosts", hostsPath)
	}
	n := len(hosts)

	if prefix == "" {
		prefix = fmt.Sprintf("%dclient", n)
	}
	if outDir == "" {
		outDir = strconv.Itoa(n)
	}

	tmpls, err := discoverTemplates(tmplDir)
	if err != nil {
		return err
	}
	if len(tmpls) == 0 {
		return fmt.Errorf("no <N>client-* template files found in %q", tmplDir)
	}

	if err := prepareOutDir(outDir, force); err != nil {
		return err
	}

	var written int
	for _, t := range tmpls {
		out := renderTemplate(t, hosts)
		outName := fmt.Sprintf("%s-%s", prefix, t.suffix)
		outPath := filepath.Join(outDir, outName)
		if err := os.WriteFile(outPath, []byte(out), 0o644); err != nil {
			return fmt.Errorf("writing %s: %w", outPath, err)
		}
		written++
	}

	fmt.Printf("hosts:     %d (from %s)\n", n, hostsPath)
	fmt.Printf("templates: %d (from %s)\n", len(tmpls), tmplDir)
	fmt.Printf("written:   %d files -> %s/\n", written, outDir)
	return nil
}

// readHosts reads non-empty, non-comment lines as host entries.
func readHosts(path string, dedup bool) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var hosts []string
	seen := map[string]bool{}
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if dedup {
			if seen[line] {
				continue
			}
			seen[line] = true
		}
		hosts = append(hosts, line)
	}
	if err := sc.Err(); err != nil {
		return nil, fmt.Errorf("reading %s: %w", path, err)
	}
	return hosts, nil
}

// discoverTemplates scans dir for <digits>client-* files. When several files
// share the same suffix (different host-count prefixes), the one with the
// largest prefix wins, since it carries the most complete fsd/fwd layout.
func discoverTemplates(dir string) ([]*template, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	type cand struct {
		count int
		tmpl  *template
	}
	bySuffix := map[string]cand{}

	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		m := reTemplateName.FindStringSubmatch(e.Name())
		if m == nil {
			continue
		}
		count, _ := strconv.Atoi(m[1])
		suffix := m[2]

		path := filepath.Join(dir, e.Name())
		t, err := parseTemplate(path, suffix)
		if err != nil {
			fmt.Fprintf(os.Stderr, "warning: skipping template %s: %v\n", e.Name(), err)
			continue
		}
		if prev, ok := bySuffix[suffix]; !ok || count > prev.count {
			bySuffix[suffix] = cand{count: count, tmpl: t}
		}
	}

	// stable, sorted-by-suffix output for deterministic runs
	suffixes := make([]string, 0, len(bySuffix))
	for s := range bySuffix {
		suffixes = append(suffixes, s)
	}
	sort.Strings(suffixes)

	tmpls := make([]*template, 0, len(suffixes))
	for _, s := range suffixes {
		tmpls = append(tmpls, bySuffix[s].tmpl)
	}
	return tmpls, nil
}

// parseTemplate reads a job file and reduces it to a structural segment list
// plus the fsd1-derived anchor base and trailing parameters.
func parseTemplate(path, suffix string) (*template, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")

	t := &template{suffix: suffix, srcName: filepath.Base(path)}
	var sawHosts, sawFsd, sawFwdMap bool

	for _, line := range lines {
		switch {
		case strings.HasPrefix(line, "hd=client"):
			if !sawHosts {
				t.segs = append(t.segs, segment{kind: segHosts})
				sawHosts = true
			}
		case reFwdMap.MatchString(line):
			if !sawFwdMap {
				t.segs = append(t.segs, segment{kind: segFwdMap})
				sawFwdMap = true
			}
		case strings.HasPrefix(line, "fsd=fsd"):
			m := reFsd.FindStringSubmatch(line)
			if m == nil {
				return nil, fmt.Errorf("unrecognized fsd line: %q", line)
			}
			if m[1] == "1" { // derive base + rest from fsd1
				anchor, rest := m[2], m[3]
				idx := reAnchorIdx.FindStringSubmatchIndex(anchor)
				if idx == nil {
					return nil, fmt.Errorf("fsd1 anchor %q has no trailing -<number> index", anchor)
				}
				t.anchorBase = anchor[:idx[0]] // strip trailing -<digits>
				t.fsdRest = rest
			}
			if !sawFsd {
				t.segs = append(t.segs, segment{kind: segFsd})
				sawFsd = true
			}
		default:
			t.segs = append(t.segs, segment{kind: segFixed, line: line})
		}
	}

	if !sawFsd || t.anchorBase == "" {
		return nil, fmt.Errorf("no fsd=fsd1 line found")
	}
	return t, nil
}

// renderTemplate produces the full job-file text for the given hosts.
func renderTemplate(t *template, hosts []string) string {
	n := len(hosts)
	var b strings.Builder

	for _, seg := range t.segs {
		switch seg.kind {
		case segFixed:
			b.WriteString(seg.line)
			b.WriteByte('\n')
		case segHosts:
			for i := 1; i <= n; i++ {
				fmt.Fprintf(&b, "hd=client%d,system=%s\n", i, hosts[i-1])
			}
		case segFsd:
			for i := 1; i <= n; i++ {
				fmt.Fprintf(&b, "fsd=fsd%d,anchor=%s-%d,%s\n", i, t.anchorBase, i, t.fsdRest)
			}
		case segFwdMap:
			for i := 1; i <= n; i++ {
				fmt.Fprintf(&b, "fwd=fwd%d,fsd=fsd%d,host=client%d\n", i, i, i)
			}
		}
	}
	return b.String()
}

// prepareOutDir creates outDir, refusing to use a non-empty one unless force.
func prepareOutDir(outDir string, force bool) error {
	info, err := os.Stat(outDir)
	switch {
	case err == nil && info.IsDir():
		if !force {
			entries, _ := os.ReadDir(outDir)
			if len(entries) > 0 {
				return fmt.Errorf("output dir %q is not empty; pass -force to overwrite", outDir)
			}
		}
	case err == nil && !info.IsDir():
		return fmt.Errorf("output path %q exists and is not a directory", outDir)
	case os.IsNotExist(err):
		// will be created below
	default:
		return err
	}
	return os.MkdirAll(outDir, 0o755)
}
