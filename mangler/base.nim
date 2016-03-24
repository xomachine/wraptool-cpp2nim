from sequtils import filter
from strutils import `%`, join
import macros

    
# pre-defined substitutions
const patterns = ["std",
  parseExpr(""""std">allocator""").lispRepr(),
  parseExpr(""""std">basic_string""").lispRepr(),
  parseExpr(""""std">basic_string[var cchar, var ("std">char_traits[var cchar]),
    var ("std">allocator[var cchar])]""").lispRepr(),
  parseExpr(""""std">basic_istream[var cchar, var ("std">char_traits[var cchar])]"""
    ).lispRepr(),
  parseExpr(""""std">basic_ostream[var cchar, var ("std">char_traits[var cchar])]"""
    ).lispRepr(),
  parseExpr(""""std">basic_iostream[var cchar, var ("std">char_traits[var cchar])]"""
    ).lispRepr(),]
const default_substitutions = ["St", "Sa", "Sb", "Ss", "Si", "So", "Sd"]


type
  MangleInfo* = object
    # The structure containing
    # namespace and substitutions information
    namespace*: string
    mangled_namespace: string
    known_nodes: seq[string]
    nested_nodes: seq[int]

proc mangle_ident*(ident: string): string {.compileTime.} =
  if ident.len() > 0:
    $ident.len() & ident
  else:
    ""


proc enclose_if*(force: bool = false, names: string): string {.compileTime.} =
  if force:
    "N" & names & "E"
  else:
    names  

proc enclose*(self: MangleInfo, names: varargs[string]): string {.compileTime.} =
  let joined = names.join("")
  let nonempty_len = @names.filter(proc(x:string):bool {.closure.} = x != "").len()
  let nested = nonempty_len > 1 or (nonempty_len > 0 and
    (self.mangled_namespace != "St" and self.mangled_namespace != ""))
  enclose_if(nested, self.mangled_namespace& joined)


proc number_to_substitution(number: int): string {.compileTime.} =
  assert(number >= 0, "Number must be positive or zero")
  if number == 0:
    "S_"
  else:
    "S" & $(number - 1) & "_"

    
proc substitute*(self: MangleInfo, input:string): string {.compileTime.} =
  assert(patterns.len() == default_substitutions.len(),
    "Patterns length must be equal to substitutions length!")
  for i in 0..<patterns.len():
    if input == patterns[i]:
      return default_substitutions[i]
  for i in 1..self.known_nodes.len():
    let r = self.known_nodes.len() - i
    if input == self.known_nodes[r]:
      return enclose_if(r in self.nested_nodes, number_to_substitution(r))
  return ""

proc mark_last_as_nested*(self: var MangleInfo) =
  self.nested_nodes.add(self.known_nodes.len()-1)
  
proc remember*(self:var MangleInfo, input: string) =
  self.known_nodes.add(input)
  
proc new*[T: MangleInfo](namespace: string = "",
  previous: MangleInfo = MangleInfo(namespace: "", mangled_namespace: "",
  known_nodes: newSeq[string](0), nested_nodes: newSeq[int](0))): T {.compileTime.}=
  # Creates new MangleInfo with given namespace
  result = MangleInfo(namespace: namespace, mangled_namespace: "",
    known_nodes: previous.known_nodes, nested_nodes: previous.nested_nodes)
  var sub_ns = substitute(result, namespace)
  if sub_ns == "":
    sub_ns = mangle_ident(namespace)
  result.mangled_namespace = sub_ns
  


  
proc unwind_infixes*(self: var MangleInfo,infixes: NimNode) {.compileTime.}=
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
  self.known_nodes.add(infixes.lispRepr())


proc finalize*(encoding: string): string {.compileTime.} =
  "_Z" & encoding

