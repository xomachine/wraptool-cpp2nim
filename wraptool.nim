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
  ## function allowing define class should be imported from cpp header
  ## Syntax:
  ## annotate_class(header, namespace, nim_class_name, cpp_class_name)
  ##   header    -      string containing header filename (same syntax with #include in C++)
  ##   namespace -      string containing namespace name
  ##   nim_class_name - class name which be used to call class from Nim code
  ##   Note: nim_class_name can be defined as generic Class[T]. In this case cpp class will be considered as template
  ##   cpp_class_name - string containing name of class in C++ header file or library
  ##
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   wrapheader "<string>":
  ##     namespace "std":
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
  ##   wrapdynlib "libfoo.so": # libraries also can be "wrapped"
  ##     class Bar[T]: # namespace can be ommited as well as C++ name
  ##                   # if in C++ class has the same name with Nims one
  ##                   # actually class can be a template
  ##       proc Bar(x: T, y: int) # You may use template identifier in constructors
  ##                              # from declaration of class
  ##       proc some_method(): T  # as well as in methods
  ##      ...
  ##    var bar = newBar[string]("str", 5)        # costructors are formed as generics
  ##    assert(type(bar.some_method()) is string) # either methods
  ##
  ## class annotation without parameters generates new type, default constructor and destructor for this type
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
  # Creating type declaration
  # type nimclass* {.header: header, importcpp: ns::class.} = object.}
  let type_string = "type " & $nimclass & "* " & "{." & header_pragma &
                    ", importcpp: \"" & ns_prefix & cppname &
                    cpp_class_brackets & "\".} " & t_brackets & " = object"

  let type_stmt = parseExpr(type_string)
  result.add(type_stmt)
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
      if (s[0].kind == nnkIdent):
        let name:string = $s[0]
        s[0] = ident(name).postfix("*")
      let fname = $(s[0].basename)
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
      let method_pragma = parseExpr(method_pragma_string % [fname, cpp_brackets])
      s[4] = method_pragma
      result.add(s.copy())
    of nnkDiscardStmt:
      discard
    else:
      error("NIY:\n\r" & s.treeRepr())



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
  let proc_pragma_string = "{."& head_pragma & ", importcpp: \"" &
                           ns_prefix & "$1$2(@)\".}"
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
    else:
      error("Expression $1 not supported in wrapper. $2" %
            [$expression, expression.lineinfo()])


macro wrapheader*(header: expr, imports: expr): expr =
  ## Wraps all supplied annotations as C++ stuff included from file
  ##
  ##
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   wrapheader "<string>":
  ##     namespace "std":
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
  ##   wrapdynlib "libfoo.so": # libraries also can be "wrapped"
  ##     class Bar[T]: # namespace can be ommited as well as C++ name
  ##                   # if in C++ class has the same name with Nims one
  ##                   # actually class can be a template
  ##       proc Bar(x: T, y: int) # You may use template identifier in constructors
  ##                              # from declaration of class
  ##       proc some_method(): T  # as well as in methods
  ##      ...
  ##    var bar = newBar[string]("str", 5)        # costructors are formed as generics
  ##    assert(type(bar.some_method()) is string) # either methods
  ##
  ## class annotation without parameters generates new type, default constructor and destructor for this type
  let header_string =
    if header.kind == nnkIdent:
      $header
    else:
      "\"" & $header & "\""
  wrap(header_string, dynlib = false, "", imports)

macro wrapdynlib*(lib: expr, imports: expr): expr =
  let lib_string =
    if lib.kind == nnkIdent:
      $lib
    else:
      "\"" & $lib & "\""
  wrap(lib_string, dynlib = true, "", imports)

discard """ macro namespace*(header: expr, ns: expr, body: expr):expr =
  ## Macro allowing define namespace and header classes imported which from
  ## Syntax:
  ## namespace(header, namespace)
  ##   header    - string containing header filename (same syntax with #include in C++)
  ##   namespace - string containing namespace name
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   namespace("<someheader.hpp>", "somenamespace"):
  ##   ...Classes and procedures annotations...
  ##
  ## Header parameter is optional
  echo body
  result = newStmtList()
  let ns_string = $ns & "::"
  let header_string =
    if $header == "":
      "nodecl,"
    elif header.kind == nnkIdent:
      "header: " & $header & ","
    else:
      "header: \"" & $header & "\","
  let proc_pragma_string = "{." & header_string & "importcpp:\"" &
                           ns_string & "$1$2" & "(@)\".}"
  for decl in body.children:
    case decl.kind
    of nnkCall:
      if not ($decl[0] == "annotate_class"):
        error("Unexpected expression " & $decl & " in namespace block" & decl.lineinfo())

      #If Header not exists
      if decl.len < 5:
        decl.insert(1, header)
      else:
        if ($header).len > 0:
          warning("Header redefinition: " & $decl.toStrLit() & decl.lineinfo())
          warning("Old one: " & $header.toStrLit() & header.lineinfo())
      # If notation not full exists
      if decl.len < 6:
        decl.insert(decl.len-3, newStrLitNode(ns_string))
      else:
        error("Classes with already defined namespace cannot be in namespace block: " & $decl & decl.lineinfo())
      result.add(decl.copy())
    of nnkProcDef:
      # proc name [T](args) {.pragma.}
      #       0    2   3        4
      if (decl[0].kind == nnkIdent):
        let name:string = $decl[0]
        decl[0] = ident(name).postfix("*")
      let procname = $(decl[0].basename)
      var template_brackets = ""
      if not (decl[2].kind == nnkEmpty):
        if not (decl[2][1].kind == nnkEmpty):
          error("Multiparametric templates not supported yet")
        template_brackets = ($decl[2][0]).generate_cpp_brackets(decl[3])
      let proc_pragma = parseExpr(proc_pragma_string % [procname, template_brackets])
      decl[4] = proc_pragma
      result.add(decl.copy())
    else:
      error("Invalid statement in namespace block: " & $decl)

template namespace*(ns: expr, body: expr):expr =
  namespace("", ns, body) """

discard """ macro annotate_class*(header:expr , ns_prefix: expr, classname: expr, cppname: expr, body: expr): expr =
  ## Macro allowing define class should be imported from cpp header
  ## Syntax:
  ## annotate_class(header, namespace, nim_class_name, cpp_class_name)
  ##   header    -      string containing header filename (same syntax with #include in C++)
  ##   namespace -      string containing namespace name
  ##   nim_class_name - class name which be used to call class from Nim code
  ##   Note: nim_class_name can be defined as generic Class[T]. In this case cpp class will be considered as template
  ##   cpp_class_name - string containing name of class in C++ header file or library
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   annotate_class("<library.hpp>", "libspace", LibClass, "LibClass"): # import libspace::LibClass and its methods
  ##     proc libmethod(): cint      # method of class
  ##     proc LibClass(somevar:cint) # overloaded constructor (default constructor generated automaticaly)
  ##     ...
  ##   var lc = newLibClass(4) # constructors are generated with names compilled from "new" word and class name in Nim
  ##   echo($lc.libmethod())
  ##   lc.destroyLibClass()    # destructors are generated with names compiled from "destroy" word and class name in Nim
  ##   # Destructors usage is unnesessary according to Nim manual
  ##   # http://nim-lang.org/docs/manual.html#importcpp-pragma-wrapping-destructors
  ##     ...
  ##   namespace("somespace"): # annotate_class can be combined with namespace statement
  ##     annotate_class(SomeTemplate[T], "SomeTemplate_"): # namespace and header fields can be ommited
  ##     # if header field is set - header from namespace will be overwritten for this class
  ##       proc SomeTemplate(x: T, y: int) # You may use template identifier in constructors
  ##       proc some_method(): T           # as well as in methods in this block without repeated declaration
  ##      ...
  ##    var sc = newSomeTemplate[string]("str", 5) # costructors are formed as generics
  ##    assert(type(sc.some_method()) is string)   # either methods
  ##
  ## Header and namespace parameters is optional
  ## annotate_class generates new type, default constructor and destructor for this type
  result = newNimNode(nnkStmtList)
  let cppclass:string = $cppname
  let ns: string = $ns_prefix
  var nimclass: string
  let header =
    if $header == "":
      "nodecl,"
    elif header.kind == nnkIdent:
      "header: " & $header & ","
    else:
      "header: \"" & $header & "\","
  var template_brackets: seq[string] = newSeq[string]()
  var t_brackets: string = ""
  var cpp_class_brackets: string = ""
  var cpp_constructor_brackets: string = ""
  var cpp_method_brackets: string  = ""
  var cpp_destructor_brackets: string =""
  case classname.kind
  of nnkIdent:
    # standart class
    nimclass = $classname
  of nnkBracketExpr:
    # class template
    nimclass = $classname[0]
    cpp_class_brackets = "<'0>"
    cpp_constructor_brackets = "<'*0>"
    cpp_method_brackets  = "<'*1>"
    cpp_destructor_brackets ="<'**1>"
    for i in 1..classname.len-1:
      template_brackets.add($classname[i])
    t_brackets = ($template_brackets)
    t_brackets = t_brackets[1..t_brackets.len]
    let pragma_no_unused_hint = parseExpr("{.push hint[XDeclaredButNotUsed]: off.}")
    result.add(pragma_no_unused_hint)
  else:
    error("Invalid class name: " & $classname & classname.lineinfo())

  # Creating type declaration
  # type nimclass* {.header: header, importcpp: ns::class.} = object.}
  let type_string = "type " & $nimclass & "* " &
                    "{." & header & " importcpp: \"" & ns &
                    cppclass & cpp_class_brackets & "\".} " &
                    t_brackets & " = object"

  let type_stmt = parseExpr(type_string)
  result.add(type_stmt)
  if template_brackets.len > 0:
    let pop_pragma = parseExpr("{.pop.}")
    result.add(pop_pragma)

  let basic_constructor = "proc new" & nimclass & "*" & t_brackets &
                          "(): " & nimclass & t_brackets &
                          " {." & header & "importcpp:\"" & ns &
                          cppclass & cpp_constructor_brackets & "(@)\", constructor.}"
  result.add(parseExpr(basic_constructor))
#  Experimental pragma required (should be implemented when it will become stable)
#  let basic_destructor = "proc `=destroy`*" & t_brackets &
#                          "(self: var " & nimclass & t_brackets &
#                          ") {." & header & "importcpp:\"#." & ns &
#                          cppclass & cpp_destructor_brackets & "::~" &
#                          cppclass & "()\".}"
  let basic_destructor = "proc destroy" & nimclass & "*" & t_brackets &
                          "(self: var " & nimclass & t_brackets &
                          ") {." & header & "importcpp:\"#." & ns &
                          cppclass & cpp_destructor_brackets & "::~" &
                          cppclass & "()\".}"
  result.add(parseExpr(basic_destructor))
  let self_arg = newIdentDefs(ident("self"),
                              parseExpr(nimclass & t_brackets))

  let method_pragma_string = "{." & header & "importcpp:\"#." & ns &
                             cppclass & cpp_method_brackets & "::$1$2(@)\".}"
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
      if (s[0].kind == nnkIdent):
        let name:string = $s[0]
        s[0] = ident(name).postfix("*")
      let fname = $(s[0].basename)
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
      let method_pragma = parseExpr(method_pragma_string % [fname, cpp_brackets])
      s[4] = method_pragma
      result.add(s.copy())
    of nnkDiscardStmt:
      discard
    else:
      error("NIY:\n\r" & s.treeRepr())

template annotate_class*(head:expr ,classname: expr, cppname: expr, body: expr): expr =
  annotate_class(head, "", classname, cppname, body)

template annotate_class*(classname: expr, cppname: expr, body: expr): expr =
  annotate_class("", "", classname, cppname, body) """
