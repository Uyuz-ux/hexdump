## Basic hexdump usage: dump a string with the default layout, then a
## custom one, then round-trip it back.

import hexdump

let data = "Hello, world!"

echo "Default layout (xxd style):"
echo dump(data)

echo "8 bytes per line, one space between bytes:"
let opts = DumpOptions(width: 8, group: 1, baseAddr: 0, unprintable: '.')
echo dump(data, opts)

echo "Round trip:", parseDump(dumpLines(data)) == data
