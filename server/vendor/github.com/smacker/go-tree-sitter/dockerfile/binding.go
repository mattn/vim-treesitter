package dockerfile

//#include "parser.h"
//TSLanguage *tree_sitter_dockerfile();
import "C"
import (
	"unsafe"

	sitter "github.com/smacker/go-tree-sitter"
)

func GetLanguage() *sitter.Language {
	ptr := unsafe.Pointer(C.tree_sitter_dockerfile())
	return sitter.NewLanguage(ptr)
}
