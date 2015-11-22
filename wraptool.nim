import macros


macro namespace*(header: expr, ns: expr, body: expr):expr =
  ## Macro allowing define namespace and header classes imported which from
  ## Syntax:
  ## namespace(header, namespace)
  ##   header    - string containing header filename (same syntax with #include in C++)
  ##   namespace - string containing namespace name
  ## Usage:
  ##
  ## .. code-block:: nim
  ##   namespace("<someheader.hpp>", "somenamespace"):
  ##   ...Classes annotations...
  ##
  ## Header parameter is optional
  result = newStmtList()
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
        decl.insert(decl.len-3, newStrLitNode($ns & "::"))
      else:
        error("Classes with already defined namespace cannot be in namespace block: " & $decl & decl.lineinfo())
      result.add(decl)
    else:
      error("Invalid statement in namespace block: " & $decl)

template namespace*(ns: expr, body: expr):expr =
  namespace("", ns, body)

from strutils import `%`

macro annotate_class*(header:expr , ns_prefix: expr, classname: expr, cppname: expr, body: expr): expr =
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
  ## annotate_class generates new type and default constructor for this type
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
  var template_brackets: seq[string]
  var t_brackets: string
  var cpp_class_brackets: string = ""
  var cpp_proc_brackets: string = ""
  var cpp_method_brackets: string = ""
  case classname.kind
  of nnkIdent:
    # standart class
    nimclass = $classname
  of nnkBracketExpr:
    # class template
    nimclass = $classname[0]
    cpp_class_brackets = "<'0>"
    cpp_proc_brackets = "<'*0>"
    cpp_method_brackets = "<'*1>"
    template_brackets = newSeq[string]()
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
                          cppclass & cpp_proc_brackets & "(@)\", constructor.}"
  result.add(parseExpr(basic_constructor))
  let self_arg = newIdentDefs(ident("self"),
                              parseExpr(nimclass & t_brackets))

  let method_pragma_string = "{." & header & "importcpp:\"#." &
                             ns & cppclass & cpp_method_brackets & "::$1" & "(@)\".}"
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
      if template_brackets.len > 0:
        if s[2].kind == nnkEmpty:
          s[2] = newNimNode(nnkGenericParams)
        var generic_expr = newNimNode(nnkIdentDefs)
        for t in template_brackets:
          generic_expr.add(ident(t))
        if template_brackets.len < 3:
          for i in template_brackets.len..<3:
            generic_expr.add(newEmptyNode())
        s[2].add(generic_expr)
      let method_pragma = parseExpr(method_pragma_string % fname)
      s[4] = method_pragma
      result.add(s.copy())
    else:
      error("NIY")

template annotate_class*(head:expr ,classname: expr, cppname: expr, body: expr): expr =
  annotate_class(head, "", classname, cppname, body)

template annotate_class*(classname: expr, cppname: expr, body: expr): expr =
  annotate_class("", "", classname, cppname, body)
