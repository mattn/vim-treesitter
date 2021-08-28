package main

//go:generate go run generate/main.go generate/parser.go -o highlight.go

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"io/ioutil"
	"log"
	"os"

	sitter "github.com/smacker/go-tree-sitter"
	"github.com/smacker/go-tree-sitter/bash"
	"github.com/smacker/go-tree-sitter/c"
	"github.com/smacker/go-tree-sitter/cpp"
	"github.com/smacker/go-tree-sitter/csharp"
	"github.com/smacker/go-tree-sitter/css"
	"github.com/smacker/go-tree-sitter/dockerfile"
	"github.com/smacker/go-tree-sitter/elm"
	"github.com/smacker/go-tree-sitter/golang"
	"github.com/smacker/go-tree-sitter/hcl"
	"github.com/smacker/go-tree-sitter/html"
	"github.com/smacker/go-tree-sitter/java"
	"github.com/smacker/go-tree-sitter/javascript"
	"github.com/smacker/go-tree-sitter/lua"
	"github.com/smacker/go-tree-sitter/ocaml"
	"github.com/smacker/go-tree-sitter/php"
	"github.com/smacker/go-tree-sitter/python"
	"github.com/smacker/go-tree-sitter/ruby"
	"github.com/smacker/go-tree-sitter/rust"
	"github.com/smacker/go-tree-sitter/scala"
	"github.com/smacker/go-tree-sitter/svelte"
	"github.com/smacker/go-tree-sitter/toml"
	"github.com/smacker/go-tree-sitter/typescript/tsx"
	"github.com/smacker/go-tree-sitter/typescript/typescript"
	"github.com/smacker/go-tree-sitter/yaml"
)

const (
	EOL          = 0
	PLAIN        = 1
	SYMBOL       = 2
	KEYWORD      = 3
	IDENTIFIER   = 4
	SPECIAL_CHAR = 5
	STRING       = 6
	NUMBER       = 7
	ERROR        = 8
	COMMENT      = 9
)

var languages = map[string]func() *sitter.Language{
	"bash":       bash.GetLanguage,
	"c":          c.GetLanguage,
	"cpp":        cpp.GetLanguage,
	"csharp":     csharp.GetLanguage,
	"css":        css.GetLanguage,
	"dockerfile": dockerfile.GetLanguage,
	"elm":        elm.GetLanguage,
	"go":         golang.GetLanguage,
	"hcl":        hcl.GetLanguage,
	"html":       html.GetLanguage,
	"java":       java.GetLanguage,
	"javascript": javascript.GetLanguage,
	"lua":        lua.GetLanguage,
	"ocaml":      ocaml.GetLanguage,
	"php":        php.GetLanguage,
	"python":     python.GetLanguage,
	"ruby":       ruby.GetLanguage,
	"rust":       rust.GetLanguage,
	"scala":      scala.GetLanguage,
	"svelte":     svelte.GetLanguage,
	"toml":       toml.GetLanguage,
	"typescript": typescript.GetLanguage,
	"tsx":        tsx.GetLanguage,
	"yaml":       yaml.GetLanguage,
}

func has(kw []string, s string) bool {
	for _, k := range kw {
		if k == s {
			return true
		}
	}
	return false
}

type Colorizer struct {
	row    int
	column int
	colors []string
	line   *[]Line
	lines  []*[]Line
}

type Line struct {
	Distance int    `json:"distance"`
	Color    string `json:"color"`
}

func NewColorizer(row, column int) *Colorizer {
	return &Colorizer{
		row:    row,
		column: column,
		colors: []string{""},
		line:   &[]Line{},
		lines:  []*[]Line{},
	}
}

func (c *Colorizer) ExtendLine(distance int) {
	// distance must be > 0 or EOL
	if len(*c.line) == 0 {
		c.lines = append(c.lines, c.line)
	}
	if len(*c.line) > 0 && (*c.line)[0].Color == c.colors[0] {
		if distance == EOL {
			(*c.line)[0].Distance = EOL
		} else {
			(*c.line)[0].Distance += distance
		}
	} else {
		*c.line = append([]Line{{Distance: distance, Color: c.colors[0]}}, (*c.line)...)
	}
	if distance == EOL {
		c.line = &[]Line{}
	}
}

func (c *Colorizer) AdvanceTo(row, column int) {
	// Handle line wraps within colored area
	for row > c.row {
		c.ExtendLine(EOL)
		c.row += 1
		c.column = 0
	}
	if column > c.column {
		c.ExtendLine(column - c.column)
		c.column = column
	}
}

func (c *Colorizer) Start(color string, row, column int) {
	c.AdvanceTo(row, column)
	c.colors = append([]string{color}, c.colors...)
}

func (c *Colorizer) End(row, column int) {
	c.AdvanceTo(row, column)
	c.colors = c.colors[1:]
}

func (c *Colorizer) Render() [][]interface{} {
	ret := [][]interface{}{}
	for i := 0; i < len(c.lines); i++ {
		vv := []interface{}{}
		for j := len(*(c.lines[i])) - 1; j >= 0; j-- {
			v := (*(c.lines[i]))[j]
			vv = append(vv, v.Color, v.Distance)
		}
		ret = append(ret, vv)
	}
	return ret
}

func parse(parser *sitter.Parser, lname string, code string) {
	f, ok := languages[lname]
	if !ok {
		return
	}
	lang := f()
	parser.SetLanguage(lang)
	root := parser.Parse(nil, []byte(code)).RootNode()

	colorizer := NewColorizer(int(root.StartPoint().Row), int(root.StartPoint().Column))
	types := []string{}
	var process_node func(node *sitter.Node)
	process_node = func(node *sitter.Node) {
		nt := node.Type()
		//println(nt, lang.SymbolType(node.Symbol()).String())
		types = append(types, nt)
		color := ""
		if lang.SymbolType(node.Symbol()) == sitter.SymbolTypeAnonymous {
			if v, ok := keywords[lname][nt]; ok {
				color = v
			}
		} else {
			if v, ok := symbols[lname][nt]; ok {
				color = v
			}
		}

		if color != "" {
			colorizer.Start(color, int(node.StartPoint().Row), int(node.StartPoint().Column))
		}

		for i := 0; i < int(node.ChildCount()); i++ {
			process_node(node.Child(i))
		}

		types = append(types, "/"+nt)

		if color != "" {
			colorizer.End(int(node.EndPoint().Row), int(node.EndPoint().Column))
		}
	}
	process_node(root)
	json.NewEncoder(os.Stdout).Encode(colorizer.Render())
}

func readLine(reader *bufio.Reader, buf *bytes.Buffer) error {
	for {
		b, prefix, err := reader.ReadLine()
		if err != nil {
			return err
		}
		buf.Write(b)
		if !prefix {
			break
		}
	}
	return nil
}

func main() {
	var ft string
	var file string
	flag.StringVar(&ft, "ft", "", "filetype")
	flag.StringVar(&file, "file", "", "file")
	flag.Parse()

	parser := sitter.NewParser()

	if ft != "" && file != "" {
		b, err := ioutil.ReadFile(file)
		if err != nil {
			log.Fatal(err)
		}
		parse(parser, ft, string(b))
		return
	}

	reader := bufio.NewReader(os.Stdin)
	for {
		var buf bytes.Buffer
		err := readLine(reader, &buf)
		if err != nil {
			break
		}
		var input []string
		err = json.Unmarshal(buf.Bytes(), &input)
		if err != nil || len(input) != 2 {
			continue
		}
		parse(parser, input[0], input[1])
	}
}
