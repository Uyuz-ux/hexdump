# Package

version       = "0.1.0"
author        = "Uyuz-ux"
description   = "Classic hex dump formatting and parsing (xxd style) with round-trip support"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 1.6"

# Tests

task test, "Runs the test suite":
  exec "nim c -r --path:src tests/thexdump.nim"
