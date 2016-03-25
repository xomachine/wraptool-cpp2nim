import macros
from strutils import `%`
from sequtils import map, toSeq

## This file provides tools to generate native Nim code with
# the `{.importcpp.}` pragma usage



proc generate_cpp_brackets*(template_symbol: string,
                           args: NimNode): string {.compiletime.} =
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
    ""
  of nnkIdentDefs:
    template_symbol.generate_cpp_brackets(args[1])
  else:
    error("Internal error while trying to parse arguments: $1 $2" %
          [args.treeRepr(), args.lineinfo()])
    ""
proc generate_cpp_brackets*(template_symbols: seq[string],
                           args: NimNode): string {.compiletime.} =
  for template_symbol in template_symbols:
    result &= generate_cpp_brackets(template_symbol, args)


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
    let generics_ast = toSeq(test[2].children)
    let generics = generics_ast.map(
      proc(x: NimNode): string =
        expectKind(x, nnkIdent)
        $x
      )
    let formals = test[3]
    let brackets = generate_cpp_brackets(generics,
      formals)
    assert(brackets == answer_string)
    # generate_cpp_brackets test
  test_generate_cpp_brackets("proc q[T](w:T)", "'1")
  test_generate_cpp_brackets("proc q[T](w:T):T", "'0")
  test_generate_cpp_brackets("proc q[T](w:seq[T])", "'*1")
  test_generate_cpp_brackets("proc q[T, U](w:seq[T], g: U)", "'*1'2")