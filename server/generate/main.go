package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

func camel(s string) string {
	isToUpper := false
	r := ""
	for k, v := range s {
		if k == 0 {
			r = strings.ToUpper(string(s[0]))
		} else {
			if isToUpper {
				r += strings.ToUpper(string(v))
				isToUpper = false
			} else {
				if v == '_' || v == '.' {
					isToUpper = true
				} else {
					r += string(v)
				}
			}
		}
	}
	r = strings.Replace(r, "Punctuation", "Punct", -1)
	if r != "Constant" {
		r = strings.Replace(r, "Constant", "Const", -1)
	}
	return r
}

var languages = []string{
	"bash",
	"c",
	"cpp",
	"csharp",
	"css",
	"dockerfile",
	"elm",
	"go",
	"hcl",
	"html",
	"java",
	"javascript",
	"lua",
	"ocaml",
	"php",
	"python",
	"ruby",
	"rust",
	//"scala",
	"svelte",
	"toml",
	"tsx",
	"typescript",
	"yaml",
}

type idmap struct {
	Name  string
	Color string
}

func has(m []idmap, name string) bool {
	for _, s := range m {
		if s.Name == name {
			return true
		}
	}
	return false
}

func generate(l string) ([]idmap, []idmap) {
	resp, err := http.Get("https://raw.githubusercontent.com/nvim-treesitter/nvim-treesitter/820b4a9c211a49c878ce3f19ed5c349509e7988f/queries/" + l + "/highlights.scm")
	if err != nil {
		log.Fatal(err)
	}
	defer resp.Body.Close()

	in := bufio.NewReader(resp.Body)
	p := NewParser(in)

	symbols := []idmap{}
	keywords := []idmap{}

	var prev *Node
	for {
		n, err := p.ParseAny(false)
		if err != nil {
			if err == io.EOF {
				break
			}
			log.Fatal(err)
		}
		if n.t == NodeIdent && n.v.(string)[0] == '@' {
			if prev.t == NodeCell {
				if prev.car.t == NodeIdent {
					name := prev.car.v.(string)
					if !has(symbols, name) {
						symbols = append(symbols, idmap{
							Name:  name,
							Color: "TS" + camel(n.v.(string)[1:]),
						})
					}
				} else if prev.car.t == NodeNil {
					name := "nil"
					if !has(symbols, name) {
						symbols = append(symbols, idmap{
							Name:  name,
							Color: "TS" + camel(n.v.(string)[1:]),
						})
					}
				}
			} else if prev.t == NodeString {
				name := prev.v.(string)
				if !has(keywords, name) {
					keywords = append(keywords, idmap{
						Name:  name,
						Color: "TS" + camel(n.v.(string)[1:]),
					})
				}
			} else if prev.t == NodeArray {
				curr := prev
				for curr != nil {
					if curr.car == nil {
						break
					}
					if curr.car.t == NodeCell && curr.car.v != nil {
						name := curr.car.v.(string)
						if !has(symbols, name) {
							symbols = append(symbols, idmap{
								Name:  name,
								Color: "TS" + camel(n.v.(string)[1:]),
							})
						}
					} else if curr.car.t == NodeString {
						name := curr.car.v.(string)
						if has(keywords, name) {
							keywords = append(keywords, idmap{
								Name:  name,
								Color: "TS" + camel(n.v.(string)[1:]),
							})
						}
					}
					if curr.cdr == nil || curr.cdr.t == NodeNil {
						break
					}
					curr = curr.cdr
				}
			} else {
				//fmt.Println(n)
			}
		}
		prev = n
	}

	return symbols, keywords
}

func main() {
	var fname string
	flag.StringVar(&fname, "o", "", "output file")
	flag.Parse()

	var out io.Writer = os.Stdout
	if fname != "" {
		f, err := os.Create(fname)
		if err != nil {
			log.Fatal(err)
		}
		defer f.Close()
		out = f
	}
	symbols := map[string][]idmap{}
	keywords := map[string][]idmap{}
	for _, l := range languages {
		s, k := generate(l)
		symbols[l] = s
		keywords[l] = k
	}

	fmt.Fprintln(out, "package main")
	fmt.Fprintln(out, "")

	fmt.Fprintln(out, `var symbols = map[string]map[string]string {`)
	for _, l := range languages {
		fmt.Fprintf(out, "\t%q: {\n", l)
		for _, s := range symbols[l] {
			fmt.Fprintf(out, "\t\t%q: %q,\n", s.Name, s.Color)
		}
		fmt.Fprintln(out, "\t},")
	}
	fmt.Fprintln(out, "}")

	fmt.Fprintln(out, `var keywords = map[string]map[string]string {`)
	for _, l := range languages {
		fmt.Fprintf(out, "\t%q: {\n", l)
		for _, s := range keywords[l] {
			fmt.Fprintf(out, "\t\t%q: %q,\n", s.Name, s.Color)
		}
		fmt.Fprintln(out, "\t},")
	}
	fmt.Fprintln(out, "}")
}
