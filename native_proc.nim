import macros
from strutils import `%`, join, endsWith
from sequtils import map, toSeq, concat, repeat, delete
from cppclass import CppClass, new, declaration
from state import State, WrapSource, SourceType

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
  else:
    error("Internal error while trying to parse arguments: $1 $2" %
          [args.treeRepr(), args.lineinfo()])
    ""

proc generate_cpp_brackets*(template_symbols: seq[NimNode],
  args: NimNode): string =
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
  unary: bool = false): string {.noSideEffect.} =
  if unary: op & "#"
  else:
    let i = (if op[0] in ['[', '(']: 1 else: op.len)
    "#" & op[0..<i] & "#" & op[i..^1]
    
proc generate_proc_call*(state: State, procedure: NimNode): string =
  ## Generates string for importcpp pragma
  procedure.expectKind(nnkProcDef)
  let formals = procedure[3]
  formals.expectKind(nnkFormalParams)
  let generics = procedure[2]
  if procedure[0].kind == nnkAccQuoted or
    procedure[0].basename.kind == nnkAccQuoted:
    let op =
      if procedure[0].kind == nnkAccQuoted:
        procedure[0][0]
      else: procedure[0].basename[0]
    return generate_operator_call($op, formals.len() < 3)
  let name = $procedure[0].basename
  let namespace_part = 
    if state.namespace != nil: state.namespace & "::"
    else: ""
  let class_part = 
    if state.class != nil:
      state.class.cppname & 
        (if state.class.template_args.len() > 0: "<" &
        state.class.template_args.generate_cpp_brackets(formals) &
        ">" else: "") & "::"
    else: ""
  let generics_part =
    if generics.kind == nnkGenericParams:
      "<" & toSeq(generics.children()).generate_cpp_brackets(formals) & ">"
    else: ""
  namespace_part & class_part & name & generics_part & "(@)"
  
proc generate_proc*(state: State, procedure: NimNode): NimNode =
  ## Generates procedure import declaration for given procedure
  ## This proc adds necessary pragmas and transform procedure
  ## arguments and template parameters to use it with declared type/class
  ## If procedure name has the same name with class it will be considered
  ## as constructor and replaced by "proc new[T: <classname>](<params>):T"
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
  # Setting return type and constructor template specialization
    if result[2].kind == nnkEmpty:
      result[2] = newNimNode(nnkGenericParams)
    result[2].insert(0, newTree(nnkIdentDefs,
      newIdentNode("ClassName"),
      newIdentNode(state.class.name),
      newEmptyNode()))
    result[3][0] = newIdentNode("ClassName")
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
  result.pragma.add((case state.source.kind
    of none: newIdentNode("nodecl")
    of header: newTree(nnkExprColonExpr,
        newIdentNode("header"),
        newStrLitNode(state.source.file))
    of dynlib: newTree(nnkExprColonExpr,
      newIdentNode("dynlib"),
      newStrLitNode(state.source.file))
    ))
  if is_constructor:
    # Latest name changing to avoid affecting pragma
    # generation
    result.pragma.add(newIdentNode("constructor"))
    result.name = newIdentNode("new").postfix("*")
    
  
  

########################
# Test area
########################
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
    let test_class = new[CppClass](n"someclass")
    let cs = State(class: test_class)
    
    let template_class = new[CppClass](n"tclass[T, Y]", "_tclass")
    let tcs = State(class: template_class)
    # generate_proc_call test
    test(es.generate_proc_call(n"proc q()"), "q(@)")
    test(es.generate_proc_call(n"proc `+`(q: int, w: int)"), "#+#")
    test(es.generate_proc_call(n"proc `[]`(q: int, w: int)"), "#[#]")
    test(es.generate_proc_call(n"proc q[T](w:T)"), "q<'1>(@)")
    test(ns.generate_proc_call(n"proc q[T](w:T)"),
      "std::q<'1>(@)")
    test(cs.generate_proc_call(n"proc q[T](w:T)"),
      "someclass::q<'1>(@)")
    test(tcs.generate_proc_call(n"proc q[W](w:T, e:W): Y"),
      "_tclass<'1,'0>::q<'2>(@)")
      
    # generate_proc test
    test(es.generate_proc(n"proc q()"),
      n"""proc q*() {.importcpp:"q(@)", nodecl.}""")
    test(es.generate_proc(n"proc q(w: cint): char"),
      n"""proc q*(w: cint): char {.importcpp:"q(@)", nodecl.}""")
    test(es.generate_proc(n"proc q[T](w: T)"),
      n"""proc q*[T](w: T) {.importcpp:"q<'1>(@)", nodecl.}""")
    test(cs.generate_proc(n"proc q*[T](w: T)"),
      n"""proc q*[T](this: someclass, w: T)
      {.importcpp:"someclass::q<'2>(@)", nodecl.}""")
    test(cs.generate_proc(n"proc someclass[T](w: T)"),
      n"""proc new*[ClassName: someclass, T](w: T): ClassName
      {.importcpp:"someclass::someclass<'0,'1>(@)", nodecl, constructor.}""")
    test(tcs.generate_proc(n"proc q[G](w: G, e: T): seq[Y]"),
      n"""proc q*[G](this: tclass[T, Y], w: G, e: T): seq[Y]
      {.importcpp:"_tclass<'*1,'*0>::q<'2>(@)", nodecl.}""")
