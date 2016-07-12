import macros
from strutils import `%`, join, endsWith, startsWith
from sequtils import map, toSeq, concat, repeat, filter
from cppclass import CppClass, declaration, newCppClass
from state import State, source_declaration

## This file provides tools to generate native Nim code with
## the `{.importcpp.}` pragma usage

proc generate_cpp_brackets*(template_symbol: string,
  args: NimNode): string {.noSideEffect.} =
  ## Converts Nims template parameters to notation for
  ## `{.importcpp.}` pragma
  ##  template_symbol - a symbol used in template proc declaration, e.g.:
  ## .. code-block:: nim
  ## proc tproc[template_symbol](arg: tempate_symbol)
  ##
  ##
  case args.kind
  of nnkIdent:
    if $args == template_symbol:
      "$1"
    else: ""
  of nnkEmpty:
    ""
  of nnkFormalParams, nnkBracketExpr:
    var i = 0
    for ch in args.children():
      let body = template_symbol.generate_cpp_brackets(ch)
      if body != "":
        if args.kind == nnkFormalParams:
          return ("'" & body) % $i
        else:
          return "*" & body
      inc(i)
    if args.kind == nnkFormalParams:
      error("""Can not find template specification in function arguments!
Template argument: $1
Arguments tree:\n $2""" %
        [template_symbol, args.treeRepr])
    ""
  of nnkIdentDefs:
    template_symbol.generate_cpp_brackets(args[1])
  of nnkVarTy:
    template_symbol.generate_cpp_brackets(args[0])
  else:
    error("Internal error while trying to parse arguments: $1 $2" %
          [args.treeRepr(), args.lineinfo()])
    ""

proc generate_cpp_brackets*(template_symbols: seq[NimNode],
  args: NimNode): string =
  ## Generates brackets for multiple template parameters
  template_symbols.map(
    proc(x: NimNode): string =
      case x.kind
      of nnkIdent: generate_cpp_brackets($x, args)
      of nnkIdentDefs:
        let ts = toSeq(x.children())
        ts[0..^3]
          .map(
            proc(y: NimNode):string =
              y.expectKind(nnkIdent)
              generate_cpp_brackets($y, args)
          ).join(",")
      else:
        error("Unexpected node: $1" % $x.kind)
        ""
    ).join(",")

proc generate_operator_call(op: string,
  nargs: int = 1): string {.noSideEffect.} =
  ## Generates call of operator for {.importcpp.} pragma
  ## supports binary and unary operators
  assert(nargs in 1..3, "Number of arguments of operator must be in interval " &
    "between 1 and 3, but $1 arguments found!" % $nargs)
  if nargs == 1: op & "#"
  else:
    let i = (if op[0] in ['[', '(']: 1 else: op.len)
    "#" & op[0..<i] & "#" & op[i..^1] & (if nargs > 2: "#" else: "")

proc generate_proc_call*(state: State, procedure: NimNode): string =
  ## Generates string for importcpp pragma
  procedure.expectKind(nnkProcDef)
  let formals = procedure[3]
  formals.expectKind(nnkFormalParams)
  let generics = procedure[2]
  let namenode = case procedure.name.kind
    of nnkPostfix: procedure.name.basename
    else: procedure.name
  if namenode.kind == nnkAccQuoted:
    if namenode.len == 1: # Operator but not a destructor
      return generate_operator_call($namenode[0], formals.len() - 1)
    #else: # Destructor not implemented
    #  return "delete #"
  let is_class_member = state.class != nil
  let is_constructor = is_class_member and state.class.name == $namenode
  let is_method = is_class_member and not is_constructor
  let is_template_class = is_class_member and state.class.template_args.len > 0
  let name =
    if is_constructor:
      state.class.cppname
    else:
      $namenode
  let namespace_part =
    if state.namespace != nil: state.namespace & "::"
    else: ""
  let class_part =
    if is_class_member: (prefix: (if is_method : "#." else: ""), class: state.class.cppname &
      (if is_template_class: "<" &
      state.class.template_args.generate_cpp_brackets(formals) &
      ">" else: "") & "::")
    else: ("", "")
  let generics_part =
    if generics.kind == nnkGenericParams:
      "<" & toSeq(generics.children()).generate_cpp_brackets(formals) & ">"
    else: ""
  class_part.prefix & namespace_part & class_part.class & name & generics_part & "(@)"

proc generate_proc*(state: State, procedure: NimNode): NimNode =
  ## Generates procedure import declaration for given procedure
  ## This proc adds necessary pragmas and transform procedure
  ## arguments and template parameters to use it with declared type/class
  ## If procedure name has the same name with class it will be considered
  ## as constructor and replaced by "proc new<classname>(<params>):T"
  ## or similiar proc
  procedure.expectKind(nnkProcDef)
  let is_method = (state.class != nil)
  let is_constructor = (is_method and
    procedure.name.kind in [nnkIdent, nnkPostfix] and
    procedure.name.basename.lispRepr == ("Ident(!\"$1\")" % state.class.name))
  # Name standartization
  let procname =
    if procedure.name.kind == nnkPostfix: procedure.name
    else: procedure.name.postfix("*")
  result = procedure
  result.name = procname
  if is_constructor:
    result[3][0] = state.class.declaration()
  elif is_method:
  # Inserting "this" into args to call proc as method
    result[3].insert(1, newTree(nnkIdentDefs,
      newIdentNode("this"),
      state.class.declaration(),
      newEmptyNode()))
  # Pragmas generation
  if result.pragma.kind == nnkEmpty:
    result.pragma = newNimNode(nnkPragma)
  result.pragma.add(newTree(nnkExprColonExpr,
    newIdentNode("importcpp"),
    newStrLitNode(state.generate_proc_call(result))))
  result.pragma.add(state.source_declaration)
  if is_method and state.class.template_args.len > 0:
    if result[2].kind != nnkGenericParams:
      result[2] = newNimNode(nnkGenericParams)
    let tail = state.class.template_args.concat(newEmptyNode().repeat(2))
    if result[2].len > 0 and
      result[2].last.len > 2 and
      result[2].last[^2].kind == nnkEmpty and
      result[2].last[^1].kind == nnkEmpty:
      result[2][^1] = newTree(nnkIdentDefs,
        toSeq(result[2].last)[0..^2].concat(tail))
    else:
      result[2].add(newTree(nnkIdentDefs, tail))
  if is_constructor:
    # Latest name changing to avoid affecting pragma
    # generation
    result.pragma.add(newIdentNode("constructor"))
    result.name = newIdentNode("new$1" % state.class.name).postfix("*")


#-----------------------
# Test area
#-----------------------
when isMainModule:
  from test_tools import test
  proc n(x: string): NimNode {.compileTime.} = parseExpr(x)

  static:
    # generate_cpp_brackets test
    test(@[n"T"].generate_cpp_brackets(n"proc q(w: T)"[3]), "'1")
    test(@[n"T"].generate_cpp_brackets(n"proc q(w: T):T"[3]), "'0")
    test(@[n"T"].generate_cpp_brackets(n"proc q(w: seq[T])"[3]), "'*1")
    test(@[n"T", n"U"]
      .generate_cpp_brackets(n"proc q(w: seq[T], g:U)"[3]),
      "'*1,'2")

    # Test data
    let es = State()
    let ns = State(namespace: "std")
    let test_class = newCppClass(n"someclass")
    let cs = State(class: test_class)
    let template_class = newCppClass(n""""_tclass" as tclass[T, Y]""")
    let tcs = State(class: template_class)
    # generate_proc_call test
    test(es.generate_proc_call(n"proc q()"), "q(@)")
    test(es.generate_proc_call(n"proc `+`(q: int, w: int)"), "#+#")
    test(es.generate_proc_call(n"proc `[]`(q: int, w: int)"), "#[#]")
    test(es.generate_proc_call(n"proc `[]=`(q: int, w: int, u:int)"), "#[#]=#")
    test(es.generate_proc_call(n"proc q[T](w:T)"), "q<'1>(@)")
    test(ns.generate_proc_call(n"proc q[T](w:T)"),
      "std::q<'1>(@)")
    test(cs.generate_proc_call(n"proc q[T](w:T)"),
      "#.someclass::q<'1>(@)")

    test(tcs.generate_proc_call(n"proc q[W](w:T, e:W): Y"),
      "#._tclass<'1,'0>::q<'2>(@)")

    # generate_proc test
    test(es.generate_proc(n"proc q()"),
      n"""proc q*() {.importcpp:"q(@)", nodecl.}""")
    test(es.generate_proc(n"proc q(w: cint): char"),
      n"""proc q*(w: cint): char {.importcpp:"q(@)", nodecl.}""")
    test(es.generate_proc(n"proc q[T](w: T)"),
      n"""proc q*[T](w: T) {.importcpp:"q<'1>(@)", nodecl.}""")
    test(cs.generate_proc(n"proc q*[T](w: T)"),
      n"""proc q*[T](this: someclass, w: T)
      {.importcpp:"#.someclass::q<'2>(@)", nodecl.}""")
    test(cs.generate_proc(n"proc `[]=`(w: int, u:int)"),
      n"""proc `[]=`*(this: someclass, w: int, u: int)
      {.importcpp:"#[#]=#", nodecl.}""")
    test(tcs.generate_proc(n"proc q[G](w: G, e: T): seq[Y]"),
      n"""proc q*[G, T, Y](this: tclass[T, Y], w: G, e: T): seq[Y]
      {.importcpp:"#._tclass<'*1,'*0>::q<'2>(@)", nodecl.}""")
    # constructor test
    test(cs.generate_proc(n"proc someclass[T](w: T)"),
      n"""proc newsomeclass*[T](w: T): someclass
      {.importcpp:"someclass::someclass<'1>(@)", nodecl, constructor.}""")
    # destructor test
    #test(cs.generate_proc(n"proc `=destroy`()"),
    #  n"""proc `=destroy`*(this: ptr someclass)
    #  {.importcpp:"delete #", nodecl.}""")
