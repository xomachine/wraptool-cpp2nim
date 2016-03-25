import macros
from strutils import `%`, join
from sequtils import map, toSeq

## This file provides tools to generate native Nim code with
## the `{.importcpp.}` pragma usage



proc generate_cpp_brackets*(template_symbol: string,
  args: NimNode): string {.compiletime,noSideEffect.} =
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
proc generate_cpp_brackets*(template_symbols: NimNode,
  args: NimNode): string {.compiletime.} =
  template_symbols.expectKind(nnkGenericParams)
  toSeq(template_symbols.children())
    .map(
      proc(x: NimNode): string =
        x.expectKind(nnkIdentDefs)
        let xlen = x.len()
        var ts = toSeq(x.children())
        ts.setLen(xlen-2)
        ts.map(
          proc(y: NimNode):string =
          y.expectKind(nnkIdent)
          generate_cpp_brackets($y, args)
          )
        .join(",")
      )
    .join(",")

    

  
    

########################
# Test area
########################
when isMainModule:
  macro test_generate_cpp_brackets(testcase: string, answer: string):stmt =
    result = newEmptyNode()
    expectKind(testcase, nnkStrLit)
    let answer_string = $answer
    let test = parseExpr($testcase)
    test.expectKind(nnkProcDef)
    let generics = test[2]
    let formals = test[3]
    let brackets = generate_cpp_brackets(generics,
      formals)
    assert(brackets == answer_string, "\n$3Expected: $1\n$3Got: $2\n" %
      [answer_string, brackets, callsite().lineinfo()])
    # generate_cpp_brackets test
  test_generate_cpp_brackets("proc q[T](w:T)", "'1")
  test_generate_cpp_brackets("proc q[T](w:T):T", "'0")
  test_generate_cpp_brackets("proc q[T](w:seq[T])", "'*1")
  test_generate_cpp_brackets("proc q[T, U](w:seq[T], g: U)", "'*1,'2")