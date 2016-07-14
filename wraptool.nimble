
version       = "0.1.0"
author        = "xomachine (Fomichev Dmitriy)"
description   = "Macros allowing generating compact and readable wrappers to C++ classes fior Nim programming language"
license       = "MIT"

requires "nim >= 0.10.0"

task tests, "Run autotests":
  let test_files = listFiles("tests")
  for file in test_files:
    exec "nim cpp --run " & file
