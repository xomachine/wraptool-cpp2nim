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
          let xlen = x.len()
          var ts = toSeq(x.children())
          ts.setLen(xlen-2)
          ts.map(
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
    "# " & op & " #"
    
proc generate_proc_call*(state: State, procedure: NimNode): string =
  ## Generates string for importcpp pragma
  procedure.expectKind(nnkProcDef)
  let formals = procedure[3]
  formals.expectKind(nnkFormalParams)
  let generics = procedure[2]
  var name = ""
  case procedure[0].kind:
  of nnkAccQuoted:
    return generate_operator_call($procedure[0][0], formals.len() < 3)
  of nnkPostfix:
    case procedure[0].basename.kind
    of nnkIdent: name = $procedure[0].basename
    of nnkAccQuoted:
      return generate_operator_call($procedure[0].basename[0], formals.len() < 3)
    else:
      error("Unknown Node: $1" % $procedure[0].basename.kind)
  of nnkIdent:
    name = $procedure[0]
  else:
    error("Unknown Node: $1" % $procedure[0].kind)

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
  # generate_cpp_brackets test
  proc test_generate_cpp_brackets(testcase: string, answer: string){.compileTime.} =
    let test = parseExpr($testcase)
    test.expectKind(nnkProcDef)
    let test_result = toSeq(test[2]).generate_cpp_brackets(test[3])
    assert(test_result == answer, "\nExpected: $1\nGot: $2\n" %
      [answer, test_result])
  
  static:
    test_generate_cpp_brackets("proc q[T](w:T)", "'1")
    test_generate_cpp_brackets("proc q[T](w:T):T", "'0")
    test_generate_cpp_brackets("proc q[T](w:seq[T])", "'*1")
    test_generate_cpp_brackets("proc q[T, U](w:seq[T], g: U)", "'*1,'2")
  
  # generate_proc_call test
  proc test_generate_proc_call(testcase: string, answer: string,
    state: State = State()) {.compileTime.} =
    let test = parseExpr($testcase)
    test.expectKind(nnkProcDef)
    let test_result = state.generate_proc_call(test)
    assert(test_result == answer, "\nExpected: $1\nGot: $2\n" %
      [answer, test_result])
  
  static:
    let test_class = new CppClass
    test_class.cppname = "someclass"
    test_class.name = "someclass"
    test_generate_proc_call("proc q()", "q(@)")
    test_generate_proc_call("proc `+`(q: int, w: int)", "# + #")
    test_generate_proc_call("proc q[T](w:T)", "q<'1>(@)")
    test_generate_proc_call("proc q[T](w:T)", "std::q<'1>(@)", State(namespace: "std"))
    test_generate_proc_call("proc q[T](w:T)", "someclass::q<'1>(@)",
      State(class: test_class))
    test_class.template_args = @[newIdentNode("T"), newIdentNode("Y")]
    test_generate_proc_call("proc q[W](w:T, e:W): Y", "someclass<'1,'0>::q<'2>(@)",
      State(class: test_class))
