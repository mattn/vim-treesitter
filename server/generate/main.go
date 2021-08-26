package main

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"net/http"
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

func main() {
	resp, err := http.Get("https://raw.githubusercontent.com/nvim-treesitter/nvim-treesitter/820b4a9c211a49c878ce3f19ed5c349509e7988f/queries/go/highlights.scm")
	if err != nil {
		log.Fatal(err)
	}
	defer resp.Body.Close()

	in := bufio.NewReader(resp.Body)
	p := NewParser(in)

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
			fmt.Println(prev.String(), "TS"+camel(n.v.(string)[1:]))
		}
		prev = n
	}
}
