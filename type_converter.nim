from macros import error



proc nim_to_c*(nimtype: string): string =
  case nimtype
  of "clong": "long"
  of "culong": "unsigned long"
  of "cchar": "char"
  of "cschar": "signed char"
  of "cshort": "short"
  of "cint": "int"
  of "csize": "size_t"
  of "clonglong": "long long"
  of "cfloat": "float"
  of "cdouble": "double"
  of "clongdouble": "long double"
  of "cuchar": "unsigned char"
  of "cushort": "unsigned short"
  of "cuint": "unsigned int"
  of "culonglong": "unsigned long long"
  of "cstringArray": "char**"
  else: "void*"