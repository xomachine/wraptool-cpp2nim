import macros
from strutils import `%`, join
from sequtils import map, toSeq, concat, repeat, delete

## This file provides tools to generate native Nim code with
## the `{.importcpp.}` pragma usage

type
  CppClass = ref object
    name: string
    cppname: string
    template_args: seq[NimNode]
  
  State = object
    namespace: string
    class: CppClass


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
  if unary:
    op & "#"
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

########################
# Test area
########################
when isMainModule:   
  template test[T](code:expr, answer: T) = 
    let ii = instantiationInfo()
    let position = "$1($2, 1)" % [ii.filename, $ii.line]
    let test_result = (code)
    if test_result != answer:
      warning("\n$3Expected: $1\n$3Got: $2" %
        [$answer, test_result, position])
  
  proc n(x: string): NimNode = parseExpr(x)
  # generate_cpp_brackets test
  static:
    test(@[n"T"].generate_cpp_brackets(n"proc q(w: T)"[3]), "'1")
    test(@[n"T"].generate_cpp_brackets(n"proc q(w: T):T"[3]), "'0")
    test(@[n"T"].generate_cpp_brackets(n"proc q(w: seq[T])"[3]), "'*1")
    test(@[n"T", n"U"]
      .generate_cpp_brackets(n"proc q(w: seq[T], g:U)"[3]),
      "'*1,'2")
  
  # generate_proc_call test
  static:
    let es = State()
    let test_class = new CppClass
    test_class.cppname = "someclass"
    test_class.name = "someclass"
    test(es.generate_proc_call(n"proc q()"), "q(@)")
    test(es.generate_proc_call(n"proc `+`(q: int, w: int)"), "#+#")
    test(es.generate_proc_call(n"proc `[]`(q: int, w: int)"), "#[#]")
    test(es.generate_proc_call(n"proc q[T](w:T)"), "q<'1>(@)")
    test(State(namespace: "std").generate_proc_call(n"proc q[T](w:T)"),
      "std::q<'1>(@)")
    test(State(class: test_class).generate_proc_call(n"proc q[T](w:T)"),
      "someclass::q<'1>(@)")
    test_class.template_args = @[newIdentNode("T"), newIdentNode("Y")]
    test(State(class: test_class).generate_proc_call(n"proc q[W](w:T, e:W): Y"),
      "someclass<'1,'0>::q<'2>(@)")
