package main

//go:generate go run generate/main.go generate/parser.go -o highlight.go

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"runtime"
	"strconv"

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

const name = "server"

const version = "0.0.1"

var revision = "HEAD"

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

var debug bool
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

type Response [2]interface{}

type Point struct {
	Row    uint32 `json:"row"`
	Column uint32 `json:"column"`
}

type Node struct {
	Type  string `json:"type"`
	Start Point  `json:"start"`
	End   Point  `json:"end"`
}

type Colorizer struct {
	row    int
	column int
	colors []string
	line   *[]Prop
	lines  []*[]Prop
}

func NewColorizer(row, column int) *Colorizer {
	return &Colorizer{
		row:    row,
		column: column,
		colors: []string{""},
		line:   &[]Prop{},
		lines:  []*[]Prop{},
	}
}

func (c *Colorizer) ExtendLine(length int) {
	// length must be > 0 or EOL
	if len(*c.line) == 0 {
		c.lines = append(c.lines, c.line)
	}
	if len(*c.line) > 0 && (*c.line)[0].Attr.Type == c.colors[0] {
		if length == EOL {
			(*c.line)[0].Attr.Length = EOL
		} else {
			(*c.line)[0].Attr.Length += length
		}
	} else {
		*c.line = append([]Prop{{Attr: PropAttr{Length: length, Type: c.colors[0]}}}, (*c.line)...)
	}
	if length == EOL {
		c.line = &[]Prop{}
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

type PropAttr struct {
	Length int    `json:"length"`
	Type   string `json:"type"`
}

type Prop struct {
	Row  int      `json:"row"`
	Col  int      `json:"col"`
	Attr PropAttr `json:"attr"`
}

func (c *Colorizer) Render() [][]Prop {
	lines := [][]Prop{}
	for i := 0; i < len(c.lines); i++ {
		props := []Prop{}
		col := 1
		for j := len(*(c.lines[i])) - 1; j >= 0; j-- {
			v := (*(c.lines[i]))[j]
			props = append(props, Prop{Row: i + 1, Col: col, Attr: v.Attr})
			col += v.Attr.Length
		}
		lines = append(lines, props)
	}
	return lines
}

func doTextObj(parser *sitter.Parser, lname string, code string, column uint32, row uint32) {
	f, ok := languages[lname]
	if !ok {
		return
	}
	lang := f()
	parser.Reset()
	parser.SetLanguage(lang)
	root := parser.Parse(nil, []byte(code)).RootNode()
	pt := sitter.Point{
		Row:    row,
		Column: column,
	}
	node := root.NamedDescendantForPointRange(pt, pt)
	if node == nil {
		json.NewEncoder(os.Stdout).Encode(Response{"textobj", "not found"})
	} else {
		json.NewEncoder(os.Stdout).Encode(Response{"textobj", &Node{
			Type: node.Type(),
			Start: Point{
				Row:    node.StartPoint().Row,
				Column: node.StartPoint().Column,
			},
			End: Point{
				Row:    node.EndPoint().Row,
				Column: node.EndPoint().Column,
			},
		}})
	}
}

func doSyntax(parser *sitter.Parser, lname string, code string) {
	f, ok := languages[lname]
	if !ok {
		return
	}
	lang := f()
	parser.Reset()
	parser.SetLanguage(lang)
	root := parser.Parse(nil, []byte(code)).RootNode()

	colorizer := NewColorizer(int(root.StartPoint().Row), int(root.StartPoint().Column))
	types := []string{}
	var process_node func(node *sitter.Node)
	process_node = func(node *sitter.Node) {
		nt := node.Type()
		if debug {
			fmt.Println(nt)
		}
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
	json.NewEncoder(os.Stdout).Encode(Response{"syntax", colorizer.Render()})
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
	var showVersion bool
	flag.BoolVar(&debug, "debug", false, "debug")
	flag.BoolVar(&showVersion, "V", false, "Print the version")
	flag.Parse()

	if showVersion {
		fmt.Printf("%s %s (rev: %s/%s)\n", name, version, revision, runtime.Version())
		return
	}

	parser := sitter.NewParser()
	reader := bufio.NewReader(os.Stdin)
	for {
		var buf bytes.Buffer
		err := readLine(reader, &buf)
		if err != nil {
			break
		}
		var input []string
		err = json.Unmarshal(buf.Bytes(), &input)
		if err != nil {
			continue
		}
		if input[0] == "version" {
			json.NewEncoder(os.Stdout).Encode(Response{"version", version})
		} else if input[0] == "syntax" && len(input) == 3 {
			doSyntax(parser, input[1], input[2])
		} else if input[0] == "textobj" /*&& len(input) == 5*/ {
			col, _ := strconv.Atoi(input[3])
			line, _ := strconv.Atoi(input[4])
			doTextObj(parser, input[1], input[2], uint32(col), uint32(line))
		} else {
			json.NewEncoder(os.Stdout).Encode(Response{"error", "invalid command"})
		}
	}
}
