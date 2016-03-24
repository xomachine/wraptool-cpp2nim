import macros
from strutils import `%`
from functions import function
from base import new, finalize
from base import MangleInfo

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
    let rt_bound = cpp.find(' ')
    let rettype = cpp[0..rt_bound]
    let fname = cpp[rt_bound+1..<cpp.len()]
    cpp = "class $1 { $2; }; $3 $1::$4{}" % [classname, cpp, rettype, fname]
  else:
    cpp = cpp & "{}"
  if namespace != "":
    cpp = "namespace $1 { $2 }" % [namespace, cpp]
  let native = mangle_native(cpp, @["<memory>", "<iostream>", "<vector>"])
  let specimen = finalize(function(mi, f, class= classname))
  assert(specimen == native, "Test failed:\n$3 Constr: $1\n$3 Native: $2" %
    [specimen, native, constructed_n.lineinfo()])
  result = newStmtList()
  result.add(parseExpr(
    ("assert(\"$3\" == \"$4\"," &
    "\"\"\"\nConstr: $1\nNative: $2\nComparing output:" &
    "\nConstr:\"$3\"\n==\nNative:\"$4\"\n\"\"\")") %
      [constructed, cpp, specimen, native]))

macro function_tests*(): stmt =
  # trivial function test
  test("proc trivialfunc()", "void trivialfunc()")
  # trivial namespace test
  test("proc trivialfunc()", "void trivialfunc()", "somenamespace")
  # trivial class test
  test("proc trivialfunc()", "void trivialfunc()", "", "someclass")
  # trivial class in namespace test
  test("proc trivialfunc()", "void trivialfunc()", "somenamespace", "someclass")
  # basic double namespace test
  test("proc trivialfunc(q: var ptr var (std>\"__cxx11\">messages[var cchar]))",
    "void trivialfunc(std::__cxx11::messages<char> *q)")
  # basic_string testing
  test("proc namedWindow(v: var ref string, q:var cint)",
    "void namedWindow(const std::string& b, int w)", "cv")
  # simple test
  test("proc waitKey(q:var cint)",
    "int waitKey(int w)", "cv")
  # basic double namespace substitution test
  test("proc trivialfunc(q: var ptr var (std>\"__cxx11\">messages[var cchar]), w: var string)",
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
  test("""proc func_of_func(a: var ptr proc(a: var cint))""",
    """void func_of_func(void(*) (int))""")
  # argument function with substitutions
  test("""proc foo(a: var ptr proc(a: var pointer): var pointer,
  b: var ptr proc(a: var ptr void): var pointer,
  c: var ptr proc(a: var pointer): ptr void)""",
  """void foo(void*(*)(void*),void*(*)(const void*),const void*(*)(void*))""")
  # seq to vector conversion
  test("""proc vecfunc(a:var seq[var cint])""",
    """void vecfunc(std::vector<int> a)""")
