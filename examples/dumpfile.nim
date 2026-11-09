## Hexdump a file from disk: hexdump dumpfile.nim [somefile]

import std/os
import hexdump

proc main() =
  if paramCount() < 1:
    quit "usage: dumpfile <path>", 1
  let path = paramStr(1)
  let data = readFile(path)
  stdout.write(dump(data))
  echo "parsed back: ", parseDump(dumpLines(data)).len, " bytes of ",
      data.len

main()
