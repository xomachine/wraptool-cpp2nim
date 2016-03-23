import macros
import strutils

# The name mangler for C++ Itanium mangler style

# pre-defined substitutions
const patterns = ["std",
  parseExpr(""""std">allocator""").lispRepr(),
  parseExpr(""""std">basic_string""").lispRepr(),
  parseExpr("""std>basic_string[var cchar, var (std>char_traits[var cchar]),
    var (std>allocator[var cchar])]""").lispRepr(),
  parseExpr("""std>basic_istream[var cchar, var (std>char_traits[var cchar])]"""
    ).lispRepr(),
  parseExpr("""std>basic_ostream[var cchar, var (std>char_traits[var cchar])]"""
    ).lispRepr(),
  parseExpr("""std>basic_iostream[var cchar, var (std>char_traits[var cchar])]"""
    ).lispRepr(),]
const default_substitutions = ["St", "Sa", "Sb", "Ss", "Si", "So", "Sd"]



type
  MangleInfo* = object
    # The structure containing
    # namespace and substitutions information
    namespace: string
    mangled_namespace: string
    known_nodes: seq[string]
    nested_nodes: seq[int]



proc number_to_substitution(number: int): string {.compileTime.} =
  assert(number >= 0, "Number must be positive or zero")
  if number == 0:
    "S_"
  else:
    "S" & $(number - 1) & "_"

proc enclose(ns: string, t: string, name: string = "",
  force: bool = false): string {.compileTime.} =
  var nested = force
  result = ns & t & name
  if ns[0] in '0'..'9': nested = true
  if t[0] in '0'..'9' and (ns != "St" or name != ""): nested = true
  if nested:
    result = "N" & result & "E"

proc substitute(self: MangleInfo, input:string): string {.compileTime.} =
  assert(patterns.len() == default_substitutions.len(),
    "Patterns length must be equal to substitutions length!")
  for i in 0..<patterns.len():
    if input == patterns[i]:
      return default_substitutions[i]
  for i in 1..self.known_nodes.len():
    let r = self.known_nodes.len() - i
    if input == self.known_nodes[r]:
      return enclose(number_to_substitution(r), "", "", r in self.nested_nodes)
  return ""



proc finalize(encoding: string): string {.compileTime.} =
  "_Z" & encoding

proc mangle_ident(ident: string): string {.compileTime.} =
  if ident.len() > 0:
    $ident.len() & ident
  else:
    ""
proc new*[T: MangleInfo](namespace: string = ""): T {.compileTime.}=
  # Creates new MangleInfo with given namespace
  result = MangleInfo(namespace: namespace, mangled_namespace: "",
    known_nodes: newSeq[string](0), nested_nodes: newSeq[int](0))
  var sub_ns = substitute(result, namespace)
  if sub_ns == "":
    sub_ns = mangle_ident(namespace)
  result.mangled_namespace = sub_ns
  
proc unwind_infixes(self: var MangleInfo,infixes: NimNode) {.compileTime.}=
  expectKind(infixes, nnkInfix)
  assert(infixes.len() == 3, "Strange infixes length: $1" % $infixes.len())
  assert(infixes[2].kind in [nnkStrLit, nnkIdent],
    "Unknown node kind in infix: $1!" % infixes.treeRepr)
  let already_done = self.substitute(infixes.lispRepr())
  if already_done != "":
    self.mangled_namespace = already_done
    var tmp = new[MangleInfo]("")
    tmp.unwind_infixes(infixes)
    self.namespace = tmp.namespace
    return
  case infixes[1].kind:
  of nnkIdent, nnkStrLit:
    let ns = $infixes[1]
    var mns = substitute(self, ns)
    if mns == "":
      self.known_nodes.add(ns)
      mns = mangle_ident(ns)
    self.namespace = ns
    self.mangled_namespace = mns
  of nnkInfix:
    unwind_infixes(self, infixes[1])
  else:
    error("Unknown node kind: " & $infixes[1].kind)
  self.mangled_namespace &= mangle_ident($infixes[2])
  self.namespace &= "::" & $infixes[2]
  self.known_nodes.add(infixes.lispRepr)

  
  
proc mangle_operator(sign: string, unary: bool = false): string {.compileTime.} =
  case sign:
    of "new": "nw"
    of "new[]": "na"
    of "delete": "dl"
    of "delete[]": "da"
    of "~": "co"
    of "+":
      if unary: "ps"
      else: "pl"
    of "-":
      if unary: "ng"
      else: "mi"
    of "*":
      if unary: "de"
      else: "ml"
    of "/": "dv"
    of "%": "rm"
    of "&":
      if unary: "ad"
      else: "an"
    of "|": "or"
    of "^": "eo"
    of "=": "aS"
    of "+=": "pL"
    of "-=": "mI"
    of "*=": "mL"
    of "/=": "dV"
    of "%=": "rM"
    of "&=": "aN"
    of "|=": "oR"
    of "^=": "eO"
    of "<<": "ls"
    of ">>": "rs"
    of "<<=": "lS"
    of ">>=": "rS"
    of "==": "eq"
    of "!=": "ne"
    of "<": "lt"
    of ">": "gt"
    of "<=": "le"
    of ">=": "ge"
    of "!": "nt"
    of "&&": "aa"
    of "||": "oo"
    of "++": "pp"
    of "--": "mm"
    of ",": "cm"
    of "->*": "pm"
    of "->": "pt"
    of "()": "cl"
    of "[]": "ix"
    of "?": "qu"
    else: sign

proc mangle_typename(self: var MangleInfo, input:string,
  forced_name: string = ""): string {.compileTime.} =
  case input:
  of "wchar_t": "w"
  of "bool": "b"
  of "char", "cchar": "c"
  of "cschar", "int8": "a"
  of "cuchar": "h"
  of "cshort", "int16": "s"
  of "cushort", "uint16": "t"
  of "cint", "int32": "i"
  of "cuint", "uint32": "j"
  of "clong": "l"
  of "culong": "m"
  of "clonglong", "int64": "x"
  of "culonglong","uint64": "y"
  of "int128": "n"
  of "uint128": "o"
  of "cfloat", "float32": "f"
  of "cdouble", "float64": "d"
  of "clongdouble", "BiggestFloat": "e"
  of "std::nullptr_t", "typeof(nil)": "Dn"
  of "auto": "Da"
  of "float128": "g"
  of "ellipsis": "z"
  #of "IEEE 754r decimal floating point (64 bits)": "Dd"
  #of "IEEE 754r decimal floating point (128 bits)": "De"
  #of "IEEE 754r decimal floating point (32 bits)": "Df"
  #of "IEEE 754r half-precision floating point (16 bits)": "Dh"
  of "char32_t": "Di"
  of "char16_t": "Ds"
  of "decltype(auto)": "Dc"
  of "void": "v" # Actually it never happens
  else:
    if input != "":
      let nim_repr = "\"$1\" > $2" % [self.namespace, input]
    
      let sub_repr = parseExpr(nim_repr).lispRepr()
      #hint sub_repr
      let mi = self.substitute(sub_repr)
      if mi != "":
        return mi
      else:
        self.known_nodes.add(sub_repr)
    let mangled_name = enclose(self.mangled_namespace, mangle_ident($input), forced_name)
    if mangled_name[0] == 'N' and input != "":
      self.nested_nodes.add(self.known_nodes.len()-1)
    mangled_name


proc mangle_type(self: var MangleInfo, input: NimNode,
  still_const: bool = true): string {.compileTime.} =
  
  result = ""
  let sub = self.substitute(input.lispRepr())
  if sub != "":
    return sub
  case input.kind:
  of nnkEmpty: return "v"
  of nnkPar: return mangle_type(self, input[0], still_const)
  of nnkRefTy:
    result = "R" & mangle_type(self, input[0], still_const)
  of nnkPtrTy:
    result = "P" & mangle_type(self, input[0], still_const)
  of nnkVarTy:
    return mangle_type(self, input[0], false)
  of nnkIdent, nnkStrLit:
    if still_const:
      result = "K" & mangle_type(self, input, false)
    else:
      case $input:
      of "pointer": result = "Pv"
      of  "string":
        let bs_type = parseExpr(
          """std > "__cxx11" > basic_string[var cchar,
            var (std>char_traits[var cchar]), var (std>allocator[var cchar])]""")
        return mangle_type(self, bs_type, false)
        # Debug string substitutions
        #for i in self.nested_nodes:
        #  hint ($i)
        #for i in 0..<self.known_nodes.len():
        #  hint("$1 - $2" % [number_to_substitution(i), self.known_nodes[i]])
      else:
        return mangle_typename(self, $input)
  of nnkBracketExpr:
    let base = mangle_type(self, input[0], still_const)
    var arg: string = "I"
    for i in 1..<input.len():
      arg &= mangle_type(self, input[i])
    arg &= "E"
    if base[base.len()-1] == 'E':
      result = base[0..base.len()-2] & arg & 'E'
    else:
      result = base & arg
    return result
  of nnkInfix: # namespacing solution
    if input[0].kind != nnkIdent or $input[0] != ">":
      hint("Did you mean \">\" to specify namespace?")
      error("Unknown infix operation: $1!" % input.lispRepr)
    var submangle = self
    var ns: string
    case input[1].kind:
    of nnkIdent, nnkStrLit:
      ns = $input[1]
      submangle.namespace = ns
      var mns = substitute(submangle, ns)
      if mns == "":
        mns = mangle_ident(ns)
        submangle.known_nodes.add(ns)
      submangle.mangled_namespace = mns
    of nnkInfix:
      unwind_infixes(submangle, input[1])
    else:
      error("Unknown namespace specification: $1!" % input.lispRepr)
    result = mangle_type(submangle, input[2], still_const)
    self.known_nodes = submangle.known_nodes
    self.nested_nodes = submangle.nested_nodes
  
  of nnkProcTy:
    expectKind(input[0], nnkFormalParams)
    hint input.treeRepr()
    let arguments = input[0]
    result = "F"
    for arg in arguments.children():
      if arg.kind == nnkIdentDefs:
        result &= self.mangle_type(arg[1])
      else:
        result &= self.mangle_type(arg, false)
    if arguments.len() < 2:
      result &= "v"
    result &= "E"
  else:
    hint(input.treeRepr())
    error("Unsupported NodeKind: " & $input.kind)
  self.known_nodes.add(input.lispRepr)
  
    

  
proc mangle_function_name(node:NimNode, unary: bool = false): string {.compileTime.} =
  case node.kind:
    of nnkIdent: # function name
      mangle_ident($node)
    of nnkAccQuoted: # operator
      mangle_operator($node[0], unary)
    of nnkPostfix: # name with asteriks
      mangle_function_name(node[1])
    else:
      error("Unknown kind of function name: " & $node.kind)
      ""


  
      
proc function(self: var MangleInfo, function:NimNode,
  templates:NimNode = newEmptyNode(), class: string = ""): string  =
  result = ""
  expectKind(function, nnkProcDef)
  let arguments = function[3] # nnkFormalParams
  var mangled_templates = ""
  for t in templates.children():
    mangled_templates &= mangle_type(self, t)
  if mangled_templates != "":
    mangled_templates = "I" & mangled_templates & "E"
  let mangled_func = mangle_function_name(function[0], arguments.len() < 3)
  result = mangle_typename(self, class, mangled_func &  mangled_templates )
  for arg in arguments.children():
    if arg.kind == nnkIdentDefs:
      result &= mangle_type(self, arg[1])
  if arguments.len() < 2:
    result &= mangle_type(self, newEmptyNode())
# Debugging stuff
#  for i in 0..<self.substitutions.len():
#    hint mangled_func & ":" & number_to_substitution(i) & " " &
#      self.substitutions[i] & "-" & self.known_nodes[i]


proc mangle*(self: var MangleInfo, function:NimNode,
  templates:NimNode = newEmptyNode(), class: string = ""): string {.compileTime.} =
  # Mangles given proc description as C++ function name and returns it as a string
  # "ref" and "ptr" used in C++'s terms of "&" and "*"
  # Abscence of "var" considered as C++'s "const"
  # "string" will be considered as "std::string" 
  #TODO: "seq" will be considered as "std::vector"
  
  finalize(function(self, function, templates, class))

      
proc mangle_native(function: string,
  headers: seq[string] = @[]): string {.compileTime.} =
  # Mangling via C++ compiller for code testing
  var source = ""
  source &= "#include <string>\n" # & header & "\n"
  for h in headers:
    source &= "#include "  & h & "\n"
  source &= function
  gorge("g++ -x c++ -S -o- - | sed -n 's/^\\(_Z[^ ]\\+\\):$/\\1/p' | head -n 1", source)


macro test(constructed_n: string, native_cpp_n: string,
  namespace_n: string = "", classname_n: string =""): expr = 
  # Checking equivalence between C++ compiller generated name and constructed
  # here
  let constructed = $constructed_n
  let native_cpp = $native_cpp_n
  let namespace = $namespace_n
  let classname = $classname_n
  var mi = new[MangleInfo](namespace)
  var f = parseExpr(constructed)
  var cpp = native_cpp
  if classname != "":
    let rt_bound = cpp.find(" ")
    let rettype = cpp[0..rt_bound]
    let fname = cpp[rt_bound+1..<cpp.len()]
    cpp = "class $1 { $2; }; $3 $1::$4{}" % [classname, cpp, rettype, fname]
  else:
    cpp = cpp & "{}"
  if namespace != "":
    cpp = "namespace $1 { $2 }" % [namespace, cpp]
  let native = mangle_native(cpp, @["<memory>", "<iostream>"])
  let specimen = mangle(mi, f, class= classname)
  assert(specimen == native, "Test failed:\n$3 Constr: $1\n$3 Native: $2" %
    [specimen, native, constructed_n.lineinfo()])
  result = newStmtList()
  result.add(parseExpr(
    "assert(\"$3\" == \"$4\"," &
    "\"\"\"Constr: $1\nNative: $2\nComparing output:" &
    "\nConstr:$3\n==\nNative:$4\n\"\"\")" %
      [constructed, cpp, specimen, native]))
      
  
when isMainModule:
  # trivial function test
  test("proc trivialfunc()", "void trivialfunc()")
  # trivial namespace test
  test("proc trivialfunc()", "void trivialfunc()", "somenamespace")
  # trivial class test
  test("proc trivialfunc()", "void trivialfunc()", "", "someclass")
  # trivial class in namespace test
  test("proc trivialfunc()", "void trivialfunc()", "somenamespace", "someclass")
  # basic double namespace test
  test("proc trivialfunc(q: var ptr (std>\"__cxx11\">messages[var cchar]))",
    "void trivialfunc(std::__cxx11::messages<char> *q)")
  # basic_string testing
  test("proc namedWindow(v:ref string, q:var cint)",
    "void namedWindow(const std::string& b, int w)", "cv")
  # simple test
  test("proc waitKey(q:var cint)",
    "int waitKey(int w)", "cv")
  # basic double namespace substitution test
  test("proc trivialfunc(q: var ptr (std>\"__cxx11\">messages[var cchar]), w: var string)",
    "void trivialfunc(std::__cxx11::messages<char> *q, std::string w)")
  # substitution basic test
  test("proc somefunc(a: var string, b: var string)",
    "void somefunc(std::string a, std::string b)")
  # substitution hard test
  test("proc somefunc(a: var string, b: var (std>allocator[var cchar]), c: var (std>char_traits[var cchar]))",
    "void somefunc(std::string a, std::allocator<char> b, std::char_traits<char> c)", "std")
  # hard substitution test
  test("""proc trivialfunc(q: var string,
    w: var (std>char_traits[var cchar]),
    e: var(std>allocator[var cchar]),
    r: var (std>"__cxx11">basic_string[var wchar_t, var (std>char_traits[var wchar_t]),
      var (std>allocator[var wchar_t])])
    )""",
    """void trivialfunc(std::string q, std::char_traits<char> w, std::allocator<char> e,
    std::basic_string<wchar_t>)""")
  # trivial argument function
  test("""proc func_of_func(a: ptr proc(a: var cint))""",
    """void func_of_func(void(*) (int))""")
  # argument function with substitutions
  test("""proc foo(a: ptr proc(a: var pointer): pointer,
  b: ptr proc(a: pointer): pointer,
  c: ptr proc(a: var pointer): pointer)""",
  """void foo(void*(*)(void*),void*(*)(const void*),const void*(*)(void*))""")
    