import macros
from strutils import `%`, join
from native_var import get_var_info
from type_converter import nim_to_c
from state import State

const cppsource_tempate = """struct wtconsts {
  $1;
} wtc_;
extern "C" {
  struct wtconsts wraptool_get_consts() {
    struct wtconsts result;
    $2;
  }
}"""

proc generate_consts*(state: State, consts: NimNode): tuple[nim: NimNode, cpp: string] =
  ## The procedure generates constants requester in wrapper file, then
  ## makes requester call and sets all the constants via `let`
  consts.expectKind(nnkStmtList)
  var cassigns = newSeq[string](0)
  var cdecls = newSeq[string](0)
  var assignments = newSeq[NimNode](0)
  var struct_fields = newSeq[NimNode](0)
  let namespace_prefix =
    if state.namespace != nil: state.namespace & "::"
    else: ""
  for declaration in consts.children():
    let var_info = get_var_info(declaration)
    cassigns.add("result.$1 = $2$1" % [var_info.cppname, namespace_prefix])
    cdecls.add("$1 $2" % [var_info.typename.nim_to_c(), var_info.cppname])
    assignments.add(
      parseExpr("""let $1* = wraptool_imported_consts.$1""" % var_info.nimname))
    struct_fields.add(newTree(nnkIdentDefs,
      newIdentNode(varinfo.nimname),
      newIdentNode(varinfo.typename),
      newEmptyNode()))
  let typedecl = newTree(nnkTypeSection,
    newTree(nnkTypeDef, newIdentNode("wraptool_consts"), newEmptyNode(),
      newTree(nnkTupleTy, struct_fields)))
  let getter_decl = parseExpr(
    """proc wraptool_get_consts(): wraptool_consts {.importc.}""")
  let get_consts = parseExpr(
    """let wraptool_imported_consts = wraptool_get_consts()""")
  result.nim = newTree(nnkStmtList, typedecl, getter_decl, get_consts)
  result.nim.add(assignments)
  result.cpp = cppsource_tempate % [cdecls.join(";\n"), cassigns.join(";\n")]


when isMainModule:
  macro checkme(data: expr): expr =
    result = newEmptyNode()
    let ans = generate_consts(State(),data)
    let etalon = """StmtList(TypeSection(TypeDef(Ident(!"wraptool_consts"), Empty(), TupleTy(IdentDefs(Ident(!"someconst"), Ident(!"cint"), Empty()), IdentDefs(Ident(!"otherconst"), Ident(!"culong"), Empty()), IdentDefs(Ident(!"customconst"), Ident(!"CustomType"), Empty())))), ProcDef(Ident(!"wraptool_get_consts"), Empty(), Empty(), FormalParams(Ident(!"wraptool_consts")), Pragma(Ident(!"importc")), Empty(), Empty()), LetSection(IdentDefs(Ident(!"wraptool_imported_consts"), Empty(), Call(Ident(!"wraptool_get_consts")))), LetSection(IdentDefs(Postfix(Ident(!"*"), Ident(!"someconst")), Empty(), DotExpr(Ident(!"wraptool_imported_consts"), Ident(!"someconst")))), LetSection(IdentDefs(Postfix(Ident(!"*"), Ident(!"otherconst")), Empty(), DotExpr(Ident(!"wraptool_imported_consts"), Ident(!"otherconst")))), LetSection(IdentDefs(Postfix(Ident(!"*"), Ident(!"customconst")), Empty(), DotExpr(Ident(!"wraptool_imported_consts"), Ident(!"customconst")))))"""
    assert(etalon == ans.nim.lisprepr)
    let cppetalon = """struct wtconsts {
  int _someconst;
unsigned long otherconst;
void* customconst;
} wtc_;
extern "C" {
  struct wtconsts wraptool_get_consts() {
    struct wtconsts result;
    result._someconst = _someconst;
result.otherconst = otherconst;
result.customconst = customconst;
  }
}"""
    assert(cppetalon == ans.cpp)
  checkme:
    "_someconst" as someconst: cint
    otherconst: culong
    customconst: CustomType
    