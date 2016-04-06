from state import State, source_declaration
import macros

## Vars, consts and other imported values handler

proc generate_var_pragma(state: State, cppname: string): NimNode =
  let namespace_prefix =
    if state.namespace != nil and state.class == nil:
      state.namespace & "::"
    else: ""
  let importcpp = newTree(nnkExprColonExpr,
    newIdentNode("importcpp"),
    newStrLitNode(namespace_prefix & cppname))
  if state.class == nil:
    newTree(nnkPragma, importcpp, state.source_declaration)
  else:
    newTree(nnkPragma, importcpp)

proc get_var_info*(declaration: NimNode):
  tuple[cppname: string, nimname: string, typename: string] =
  case declaration.kind
  of nnkInfix:
    assert(declaration.len == 4, "Broken infix: " & declaration.treeRepr)
    declaration[0].expectKind(nnkIdent)
    declaration[2].expectKind(nnkIdent)
    declaration[1].expectKind(nnkStrLit)
    declaration[3].expectKind(nnkStmtList)
    assert($declaration[0] == "as", """Only "<cppname>" as <nimname> """ &
      """declarations allowed, not """ & declaration.repr)
    assert(declaration[3].len == 1, "Broken declaration: " & declaration.repr)
    let cppname = $declaration[1]
    let nimname = $declaration[2]
    let typename = $declaration[3][0]
    (cppname: cppname, nimname: nimname, typename: typename)
  of nnkCall:
    assert(declaration.len == 2, "Broken declaration: " & declaration.repr)
    declaration[0].expectKind(nnkIdent)
    declaration[1].expectKind(nnkStmtList)
    assert(declaration[1].len == 1, "Broken declaration: " & declaration.repr)
    let cppname = $declaration[0]
    let nimname = $declaration[0]
    let typename = $declaration[1][0]
    (cppname: cppname, nimname: nimname, typename: typename)
  else:
    error("Unknown NimNode: " & declaration.treeRepr)
    ("", "", "")

proc generate_var*(state: State, declaration: NimNode): NimNode =
  let varinfo = get_var_info(declaration)
  
  let pragma = newTree(nnkPragmaExpr,
    newIdentNode(varinfo.nimname).postfix("*"),
    state.generate_var_pragma(varinfo.cppname))
  newTree(nnkIdentDefs, pragma, newIdentNode(varinfo.typename), newEmptyNode())

  
when isMainModule:
  from test_tools import test
  from cppclass import newCppClass
  proc n(e: string): NimNode {.compileTime.} = parseExpr(e)
  
  static:
    let es = State()
    let cs = State(class: newCppClass(n"""someclass"""))
    test(es.generate_var(n"""simplevar: int"""),
      n"""var simplevar*{.importcpp:"simplevar", nodecl.}: int"""[0])
    test(cs.generate_var(n"""simplefield: int"""),
      n"""var simplefield*{.importcpp:"simplefield".}: int"""[0])
