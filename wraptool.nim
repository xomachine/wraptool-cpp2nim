import macros
from strutils import `%`

proc generate_cpp_brackets(template_symbol: string,
                           args: NimNode): string {.compiletime.} =
  let isTop =
    if args.kind == nnkFormalParams:
      true
    else:
      false
  if (not isTop) and not (args.kind == nnkBracketExpr):
    error("Internal error while trying to parse arguments: $1 $2" %
          [$args, args.lineinfo()])
  var i = 0
  for ch in args.children():
    case ch.kind
    of nnkIdent:
      if $ch == template_symbol:
        if isTop:
          result = "'" & $i
        else:
          result = "*"
        return
    of nnkBracketExpr:
      let body = template_symbol.generate_cpp_brackets(ch)
      if body.len > 0:
        if isTop:
          result = "'" & body & $i
        else:
          result = "*" & body
    else:
      echo "Unexpected node:"
      echo ch.treeRepr()
      error("Internal error while trying to parse arguments: $1 $2" %
            [$args, args.lineinfo()])
    i+=1



proc annotate_class(header_pragma: string , ns_prefix: string, nimname: NimNode,
                    cppname: string, body: expr): NimNode {.compiletime.} =
  result = newNimNode(nnkStmtList)
  var template_brackets: seq[string] = newSeq[string]()
  var t_brackets: string = ""
  var cpp_class_brackets: string = ""
  var cpp_constructor_brackets: string = ""
  var cpp_method_brackets: string  = ""
  var cpp_destructor_brackets: string =""
  var nimclass: string
  case nimname.kind:
  of nnkIdent:
    # standart class
    nimclass = $nimname
  of nnkBracketExpr:
    # class template
    nimclass = $nimname[0]
    cpp_class_brackets = "<'0>"
    cpp_constructor_brackets = "<'*0>"
    cpp_method_brackets  = "<'*1>"
    cpp_destructor_brackets ="<'**1>"
    for i in 1..nimname.len-1:
      template_brackets.add($nimname[i])
    t_brackets = ($template_brackets)
    t_brackets = t_brackets[1..t_brackets.len]
    let pragma_no_unused_hint =
      parseExpr("{.push hint[XDeclaredButNotUsed]: off.}")
    result.add(pragma_no_unused_hint)
  else:
    error("Invalid class name: " & $nimname & nimname.lineinfo())
  let var_pragma_string = "{.importcpp:\"$1\".}"
  # Creating type declaration
  # type nimclass* {.header: header, importcpp: ns::class.} = object.}
  let type_string = "type " & $nimclass & "* " & "{." & header_pragma &
                    ", importcpp: \"" & ns_prefix & cppname &
                    cpp_class_brackets & "\".} " & t_brackets & " = object"
  var type_stmt = parseExpr(type_string)
  result.add(type_stmt)
  let typedef_position = result.len - 1
  if template_brackets.len > 0:
    let pop_pragma = parseExpr("{.pop.}")
    result.add(pop_pragma)

  let basic_constructor = "proc new" & nimclass & "*" & t_brackets &
                          "(): " & nimclass & t_brackets & " {." &
                          header_pragma & ", importcpp:\"" & ns_prefix &
                          cppname & cpp_constructor_brackets & "(@)\", constructor.}"
  result.add(parseExpr(basic_constructor))
#  Experimental pragma required (should be implemented when it will become stable)
#  let basic_destructor = "proc `=destroy`*" & t_brackets &
#                          "(self: var " & nimclass & t_brackets &
#                          ") {." & header & "importcpp:\"#." & ns_prefix &
#                          cppname & cpp_destructor_brackets & "::~" &
#                          cppname & "()\".}"
  let basic_destructor = "proc destroy" & nimclass & "*" & t_brackets &
                          "(self: var " & nimclass & t_brackets &
                          ") {." & header_pragma & ", importcpp:\"#." &
                          ns_prefix & cppname & cpp_destructor_brackets &
                          "::~" & cppname & "()\".}"
  result.add(parseExpr(basic_destructor))
#  var self_type = newNimNode(nnkVarTy)
#  self_type.add(parseExpr(nimclass & t_brackets))
  let self_arg = newIdentDefs(ident("self"),
                              parseExpr(nimclass & t_brackets))
  let method_pragma_string = "{." & header_pragma & ", importcpp:\"#." & ns_prefix &
                             cppname & cpp_method_brackets & "::$1$2(@)\".}"
  let body_list =
    if not (body.kind == nnkStmtList):
      newStmtList(body)
    else:
      body
  for s in body_list:
    case s.kind
    of nnkProcDef:
      # proc name [T](args) {.pragma.}
      #       0    2   3        4
      if not(s[0].kind == nnkPostfix):
        s[0] = s[0].postfix("*")
      let fname =
        if s[0].basename.kind == nnkIdent:
          $(s[0].basename)
        else:
          ""
      if fname == nimclass: # if constructor declared
        var constructor = parseExpr(basic_constructor)
        let args = s[3]
        let gens = s[2]
        for i in 1..<args.len:
          constructor[3].add(args[i])
        if not (gens.kind == nnkEmpty):
          gens.copyChildrenTo(constructor[2])
        result.add(constructor)
        continue
      s[3].insert(1, self_arg)
      var cpp_brackets: string = ""
      if template_brackets.len > 0:
        if s[2].kind == nnkEmpty:
          s[2] = newNimNode(nnkGenericParams)
        else:
          if s[2][0].kind == nnkIdent:
            if $s[2][0] in template_brackets:
              error("Suplied template name $1 already used: $2 $3" % [$s[2][0], $s, s.lineinfo()])
            cpp_brackets = ($s[2][0]).generate_cpp_brackets(s[3])
        var generic_expr = newNimNode(nnkIdentDefs)
        for t in template_brackets:
          generic_expr.add(ident(t))
        if template_brackets.len < 3:
          for i in template_brackets.len..<3:
            generic_expr.add(newEmptyNode())
        s[2].add(generic_expr)
      if (s[0][1].kind == nnkAccQuoted):
        # operator
        let op = ($s[0][1][0])
        var cppnotation = "#" & op[0] & "@" & op[1..<op.len]
        s[4] = parseExpr("{.nodecl, importcpp:\"$1\".}" % cppnotation)
        result.add(s.copy())
        continue
      let method_pragma = parseExpr(method_pragma_string % [fname, cpp_brackets])
      s[4] = method_pragma
      result.add(s.copy())
    of nnkDiscardStmt:
      discard
    of nnkCall, nnkInfix:
      var cppvar: string
      var nimvar: NimNode
      var vartype: NimNode
      if (s.kind == nnkInfix):
        if not($s[0] == "as") or
           not(s[1].kind == nnkStrLit) or
           not(s[2].kind == nnkIdent) or
           not(s[3].kind == nnkStmtList) or
           not(s[3].len == 1):
          error("Unknown infix notation\n" & s.treeRepr() & s.lineinfo())
        cppvar = $s[1]
        nimvar = s[2]
        vartype = s[3][0]
      else:
        if not(s[0].kind == nnkIdent) or
           not(s[1].kind == nnkStmtList) or
           not(s[1].len == 1):
          error("Expression $1 not supported in wrapper. $2" %
              [s.treeRepr(), s.lineinfo()])
        cppvar = $s[0]
        nimvar = s[0]
        vartype = s[1][0]
      if result[typedef_position][0][2][2].kind == nnkEmpty:
        result[typedef_position][0][2][2] = newNimNode(nnkRecList)
      var annotation = newNimNode(nnkIdentDefs)
      annotation.add(newNimNode(nnkPragmaExpr))
      annotation[0].add(newNimNode(nnkPostfix))
      annotation[0][0].add(ident("*"))
      annotation[0][0].add(nimvar)
      annotation[0].add(parseExpr(var_pragma_string % [cppvar]))
      annotation.add(vartype)
      annotation.add(newNimNode(nnkEmpty))
      result[typedef_position][0][2][2].add(annotation.copy())
    else:
      error("Unknown expression:\n$1\n $2" % [s.treeRepr(), s.lineinfo()])



proc wrap(source: string, dynlib:bool, namespace: string = "",
          expressions: NimNode): NimNode {.compiletime.} =
  let head_pragma =
    if dynlib:
      "dynlib: " & source
    else:
      "header: " & source
  let ns_prefix =
    if namespace == "":
      namespace
    else:
      namespace & "::"
  result = newNimNode(nnkStmtList)
  let pragma_string = "{."& head_pragma & ", importcpp: \"$1\".}"
  let proc_pragma_string = pragma_string % [ns_prefix & "$1$2(@)"]
  for expression in expressions.children:
    case expression.kind
    of nnkCommand:
      case $expression[0]
      of "namespace":
        if not (ns_prefix == ""):
          error("Namespace cannot be redefined inside namespace block: $1 $2" %
                [$expression, expression.lineinfo()])
        result.add(source.wrap(dynlib, $expression[1],
                   expression[2].copy()))
      of "class":
        var cppname: string
        var nimname: NimNode
        case expression[1].kind
        of nnkInfix:
          if not ($expression[1][0] == "as"):
            error("Unknown class statement syntax: $1 $2" %
                  [$expression, expression.lineinfo()])
          cppname = $expression[1][1]
          nimname = expression[1][2]
        of nnkIdent:
          cppname = $expression[1]
          nimname = expression[1]
        of nnkBracketExpr:
          nimname = expression[1]
          cppname = $expression[1][0]
        else:
          error("Unknown class statement syntax: $1 $2" %
                [$expression, expression.lineinfo()])
        result.add(annotate_class(head_pragma, ns_prefix, nimname,
                                  cppname, expression[2]))
      else:
        error("Unknown command: $1 $2" % [$expression, expression.lineinfo()])
    of nnkProcDef:
      if (expression[0].kind == nnkIdent):
        let name:string = $expression[0]
        expression[0] = ident(name).postfix("*")
      let procname = $(expression[0].basename)
      var template_brackets = ""
      if not (expression[2].kind == nnkEmpty):
        template_brackets  = "<"
        for templ_par in expression[2].children:
          template_brackets  &= ($templ_par).generate_cpp_brackets(expression[3]) & ","
        template_brackets[template_brackets.len-1] = '>'
      let proc_pragma = parseExpr(proc_pragma_string % [procname, template_brackets])
      expression[4] = proc_pragma
      result.add(expression.copy())
    of nnkCall, nnkInfix:
      if dynlib:
        error("Constants and global variables cannot be imported from dynamic library: $1 $2" %
            [$expression, expression.lineinfo()])
      var cppvar: string
      var nimvar: NimNode
      var vartype: NimNode
      if (expression.kind == nnkInfix):
        if not($expression[0] == "as") or
           not(expression[1].kind == nnkStrLit) or
           not(expression[2].kind == nnkIdent) or
           not(expression[3].kind == nnkStmtList) or
           not(expression[3].len == 1):
          error("Unknown infix notation\n" & expression.treeRepr() & expression.lineinfo())
        cppvar = $expression[1]
        nimvar = expression[2]
        vartype = expression[3][0]
      else:
        if not(expression[0].kind == nnkIdent) or
           not(expression[1].kind == nnkStmtList) or
           not(expression[1].len == 1):
          error("Expression\n $1\n not supported in wrapper. $2" %
              [expression.treeRepr, expression.lineinfo()])
        cppvar = $expression[0]
        nimvar = expression[0]
        vartype = expression[1][0]
      var annotation = newNimNode(nnkVarSection)
      annotation.add(newNimNode(nnkIdentDefs))
      annotation[0].add(newNimNode(nnkPragmaExpr))
      annotation[0][0].add(newNimNode(nnkPostfix))
      annotation[0][0][0].add(ident("*"))
      annotation[0][0][0].add(nimvar)
      annotation[0][0].add(parseExpr(pragma_string % [ns_prefix & cppvar]))
      annotation[0].add(vartype)
      annotation[0].add(newNimNode(nnkEmpty))
      result.add(annotation.copy())
    else:
      error("Expression not supported in wrapper.$1 \n $2" %
            [expression.treeRepr(), expression.lineinfo()])


macro wrapheader*(header: expr, imports: expr): expr =
  ## Wraps all supplied annotations as C++ stuff included from file
  ##
  ##
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   wrapheader "<string>":
  ##     namespace "std":
  ##       proc stoi(str: cstring, idx: ptr culong, base: cint) # import "stoi" function
  ##       class "string" as CppString: # import std::string as CppString type
  ##         proc c_str(): cstring      # import method of class
  ##         proc CppString(s:cstring)  # overloaded constructor
  ##         # (default constructor and destructor generated automaticaly)
  ##     ...
  ##   var cppstr = newCppString("str") # constructors have names
  ##                                    # compilled from "new" word and class name in Nim
  ##   echo(cppstr.c_str())  # method can be called by familiar way
  ##   lc.destroyCppString() # destructors have names compiled from "destroy" word and class name in Nim
  ##   # Destructors usage is unnesessary according to Nim manual
  ##   # http://nim-lang.org/docs/manual.html#importcpp-pragma-wrapping-destructors
  ##     ...
  ##   wrapheader "<foo.h>":
  ##     FOO_CONSTANT: cint             # constants can be wrapped
  ##     "__BarConst" as BAR_CONST:cint # and renamed if nessesary
  ##     class Bar[T]: # namespace can be ommited as well as C++ name
  ##                   # if in C++ class has the same name with Nims one
  ##                   # actually class can be a template
  ##       proc Bar(x: T, y: cint)      # You may use template identifier in constructors
  ##                                    # from declaration of class
  ##       proc some_method(): T        # as well as in methods
  ##       foofield: cint               # class field annotations allowed
  ##       "__bar_field" as barfield: T # field can be renamed and its type can be generic parameter
  ##      ...
  ##    let fooconst = FOO_CONST                   # constants can be used in code as usually
  ##    var bar = newBar[string]("str", BAR_CONST) # costructors are formed as generics
  ##    assert(type(bar.some_method()) is string)  # either methods
  ##
  ## class annotation without parameters generates new type, default constructor and destructor for this type
  let header_string =
    if header.kind == nnkIdent:
      $header
    else:
      "\"" & $header & "\""
  wrap(header_string, dynlib = false, "", imports)

macro wrapdynlib*(lib: expr, imports: expr): expr =
  ## Wraps all supplied annotations as C++ stuff included from file
  ##
  ##
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   wrapdynlib "libfoo.so": # libraries also can be "wrapped"
  ##     # FOO_CONST: cint     # Constants cannot be wrapped from libraries
  ##     class Bar[T]: # Other things are the same with wrapheader
  ##       proc Bar(x: T, y: int)
  ##       proc some_method(): T
  ##      ...
  ##    var bar = newBar[string]("str", 5)
  ##    assert(type(bar.some_method()) is string)
  ##
  ## class annotation without parameters generates new type, default constructor and destructor for this type
  let lib_string =
    if lib.kind == nnkIdent:
      $lib
    else:
      "\"" & $lib & "\""
  wrap(lib_string, dynlib = true, "", imports)
