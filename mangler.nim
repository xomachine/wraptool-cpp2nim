import macros
import strutils

# The name mangler for C++ Itanium mangler style

const npatterns = ["std", "std::allocator", "std::basic_string",
  "std::basic_stringIcSt11char_traitsIcESaIcEE", "std::basic_istreamIcSt11char_traitsIcEE",
  "std::basic_ostreamIcSt11char_traitsIcEE", "std::basic_iostreamIcSt11char_traitsIcEE"]
const default_subs = ["St", "Sa", "Sb", "Ss", "Si", "So", "Sd"]

type
  MangleInfo* = object
    # The structure containing
    # namespace and substitutions information
    namespace: string
    known_nodes: seq[string]




proc new*[T: MangleInfo](namespace: string = ""): T =
  # Creates new MangleInfo with given namespace
  MangleInfo(namespace: namespace,
    known_nodes: newSeq[string](0))
  

proc number_to_substitution(number: int): string {.compileTime.} =
  assert(number >= 0, "Number must be positive or zero")
  if number == 0:
    "S_"
  else:
    "S" & $(number - 1) & "_"
    

proc substitute(self: MangleInfo, input:string): string {.compileTime.} =
  assert(npatterns.len() == default_subs.len(),
    "Patterns length must be equal subs length!")
  for i in 0..<npatterns.len():
    if input == npatterns[i]:
      return default_subs[i]
  for i in 1..self.known_nodes.len():
    let r = self.known_nodes.len() - i
    if input == self.known_nodes[r]:
      return number_to_substitution(r)
  return ""


proc finalize(encoding: string): string {.compileTime.} = "_Z" & encoding

proc mangle_ident(ident: string): string {.compileTime.} =
  if ident.len() > 0:
    $ident.len() & ident
  else:
    ""

proc enclose(ns: string, t: string, name: string = ""): string {.compileTime.} =
  var nested = false
  result = ns & t & name
  if ns[0] in '0'..'9': nested = true
  if t[0] in '0'..'9' and (ns != "St" or name != ""): nested = true
  if nested:
    result = "N" & result & "E"

  
  
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

proc mangle_typename(self: var MangleInfo, input:string, forced_name: string = ""): string {.compileTime.} =
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
      let mi = self.substitute(self.namespace & "::" & input & forced_name)
      if mi != "":
        mi
      else:
        var mn = self.substitute(self.namespace)
        if mn == "" and self.namespace != "":
          mn = mangle_ident(self.namespace)
          self.known_nodes.add(self.namespace)
        let res = enclose(mn, mangle_ident($input), forced_name)
        self.known_nodes.add(self.namespace & "::" & input & forced_name)
        res

      
proc function(self: var MangleInfo, function:NimNode,
  templates:NimNode = newEmptyNode(), class: string = ""): string {.compileTime.}

proc mangle_type(self: var MangleInfo, input: NimNode, still_const: bool = true): string {.compileTime.} =
  result = ""
  let sub = self.substitute(input.lispRepr())
  if sub != "":
    return sub
  case input.kind:
  of nnkEmpty: return "v"
  of nnkRefTy:
    result = "R" & mangle_type(self, input[0], still_const)
  of nnkPtrTy:
    result = "P" & mangle_type(self, input[0], still_const)
  of nnkVarTy:
    return mangle_type(self, input[0], false)
    #result = replace_abbreveations(self, result)
  of nnkIdent:
    if still_const:
      result = "K" & mangle_type(self, input, false)
    else:
      case $input:
      of  "string":
        var mangled = ""
        var template_expr = newStmtList()
        # Too lazy to make AST by hands, so using the part of generated AST
        template_expr.add(parseExpr("var q:var cchar")[0][1])
        template_expr.add(parseExpr("var q:var char_traits[var cchar]")[0][1])
        template_expr.add(parseExpr("var q:var allocator[var cchar]")[0][1])
        var subfunc = parseExpr("proc basic_string()")
        # std::string is a part of std namespace, so lets create it with all
        # previous substitutions
        var cust_mi = self
        cust_mi.namespace = "std"
        mangled = function(cust_mi, subfunc, template_expr, "__cxx11")
        # Remove trailing void due to it is not actual function
        mangled = mangled.substr(0, mangled.len()-2)
        if self.known_nodes.len() < cust_mi.known_nodes.len():
          for i in self.known_nodes.len()..<cust_mi.known_nodes.len():
            self.known_nodes.add(cust_mi.known_nodes[i])
        result = mangled
      else:
        return result & mangle_typename(self, $input)
  of nnkBracketExpr:
    let arg = "I" & mangle_type(self, input[1]) & "E"
    let base = mangle_type(self, input[0], still_const)
    result = base & arg
  else:
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
#    hint mangled_func & ":" & number_to_substitution(i) & " " & self.substitutions[i] & "-" & self.known_nodes[i]


proc mangle*(self: var MangleInfo, function:NimNode,
  templates:NimNode = newEmptyNode(), class: string = ""): string {.compileTime.} =
  # Mangles given proc description as C++ function name and returns it as a string
  # "ref" and "ptr" used in C++'s terms of "&" and "*"
  # Abscence of "var" considered as C++'s "const"
  # "string" will be considered as "std::string" 
  #TODO: "seq" will be considered as "std::vector"
  
  finalize(function(self, function, templates, class))

      
proc mangle_native(function: string, headers: seq[string] = @[]): string {.compileTime.} =
  # Mangling via C++ compiller for code testing
  var source = ""
  source &= "#include <string>\n" # & header & "\n"
  for h in headers:
    source &= "#include "  & h & "\n"
  source &= function
  gorge("g++ -x c++ -S -o- - | sed -n 's/^\\(_Z[^ ]\\+\\):$/\\1/gp'", source)


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
    cpp = "class $1 { $2 };" % [classname, cpp]
  if namespace != "":
    cpp = "namespace $1 { $2 }" % [namespace, cpp]
  let native = mangle_native(cpp)
  let specimen = mangle(mi, f, class= classname)
  assert(specimen == native, "Test failed:\nConstr: " & specimen & "\nNative: " & native)
  return parseExpr(
    "echo \"\"\"Constr: $1\nNative: $2\nComparing output:\n$3\n==\n$4\nInternal test passed!\n\"\"\"" %
      [constructed, cpp, specimen, native])
      
  
when isMainModule:
  # basic string testing
  test("proc namedWindow(v:ref string, q:var cint)",
    "void namedWindow(const std::string& b, int w){}", "cv")
  # simple test
  test("proc waitKey(q:var cint)",
    "int waitKey(int w){}", "cv")
  # substitution basic test
  test("proc somefunc(a: var string, b: var string)",
    "void somefunc(std::string a, std::string b) {}")
