## Classic hex dump formatting and parsing for Nim (xxd style).
##
## Build a hex dump of binary data in the familiar xxd layout - address
## column, grouped hex bytes, ASCII gutter - and parse such dumps back
## into the original bytes:
##
## .. code-block:: nim
##
##   import hexdump
##
##   echo dump("Hello, world!")
##   ## 00000000: 4865 6c6c 6f2c 2077 6f72 6c64 21      Hello, world!
##
##   let back = parseDump(dumpLines("Hello, world!"))
##   assert back == "Hello, world!"
##
## The default layout follows xxd's defaults: 16 bytes per line, hex
## bytes grouped in pairs, lowercase hex, and an 8-hex-digit address
## column. Both the line width and the grouping are configurable, and
## `parseDump` understands any dump the module produces.
##
## Byte offsets always fall on code point boundaries for valid UTF-8
## input - matching is done on bytes, and UTF-8 is self-synchronizing,
## so a hex dump line never splits a character in the ASCII gutter into
## two entries: the gutter shows one placeholder per *byte*, exactly
## like xxd, which is the lossless view you need to inspect encoding
## problems.

import std/strutils

type
  DumpOptions* = object
    ## Layout options for `dumpLines` and `dump`. Use
    ## `defaultDumpOptions` instead of constructing this type directly
    ## on Nim 1.6, where object field defaults are not supported.
    width*: int          ## Bytes per line (default 16).
    group*: int          ## Bytes per hex group (default 2; 1 = one space per byte).
    baseAddr*: BiggestInt ## Address printed for the first byte (default 0).
    unprintable*: char   ## Placeholder for non-printable bytes (default '.').

proc defaultDumpOptions*(): DumpOptions =
  ## The xxd-compatible default layout: 16 bytes per line, pairs of
  ## bytes per hex group, address starting at 0, `.` for unprintables.
  DumpOptions(width: 16, group: 2, baseAddr: 0, unprintable: '.')

proc validateOptions*(opts: DumpOptions) {.raises: [ValueError].} =
  ## Checks `opts` and raises `ValueError` when the layout is
  ## impossible: `width` must be positive and `group` must be between 1
  ## and `width` inclusive.
  if opts.width < 1:
    raise newException(ValueError,
      "width must be at least 1, got " & $opts.width)
  if opts.group < 1:
    raise newException(ValueError,
      "group must be at least 1, got " & $opts.group)
  if opts.group > opts.width:
    raise newException(ValueError,
      "group (" & $opts.group & ") must not exceed width (" & $opts.width & ")")

proc hexVal(c: char): int {.inline.} =
  ## Hex digit to value; -1 when `c` is not a hex digit.
  case c
  of '0'..'9': ord(c) - ord('0')
  of 'a'..'f': ord(c) - ord('a') + 10
  of 'A'..'F': ord(c) - ord('A') + 10
  else: -1

proc isPrintableByte(b: uint8): bool {.inline.} =
  ## ASCII printable range used by xxd's gutter: 0x20 (space) through
  ## 0x7e (tilde). DEL (0x7f) and everything above are placeholders.
  b >= 0x20'u8 and b <= 0x7e'u8

proc formatAddr(a: BiggestInt): string {.inline.} =
  ## 8 lowercase hex digits. Addresses wider than 32 bits are truncated
  ## to the low 32 bits, matching xxd's `%08x` behaviour exactly.
  let v = uint64(a) and 0xFFFFFFFF'u64
  toHex(int(v), 8).toLowerAscii()

proc hexAreaLen(opts: DumpOptions): int {.inline.} =
  ## Number of characters the hex section occupies on a full line:
  ## two chars per byte plus one separator space between groups.
  opts.width * 2 + ((opts.width + opts.group - 1) div opts.group - 1)

proc dumpLines*(data: string; opts: DumpOptions = defaultDumpOptions()): seq[string] =
  ## Formats `data` as hex dump lines in xxd layout. The result has one
  ## entry per line, without trailing newlines; empty input produces an
  ## empty sequence. Raises `ValueError` for impossible `opts`.
  ##
  ## See also:
  ## * `dump proc`_ for a single string with trailing newlines
  ## * `parseDump proc`_ to decode the lines back to bytes
  validateOptions(opts)
  if data.len == 0:
    return @[]
  var offset = 0
  while offset < data.len:
    let stop = min(offset + opts.width, data.len)
    var row = formatAddr(BiggestInt(opts.baseAddr) + BiggestInt(offset)) & ": "
    var hexPart = ""
    var i = offset
    var firstGroup = true
    while i < stop:
      if not firstGroup:
        hexPart.add(' ')
      var g = 0
      while g < opts.group and i < stop:
        hexPart.add(toHex(uint8(data[i]), 2).toLowerAscii())
        inc g
        inc i
      firstGroup = false
    hexPart &= spaces(hexAreaLen(opts) - hexPart.len)
    row.add(hexPart)
    row.add("  ")
    for j in offset ..< stop:
      let b = uint8(data[j])
      row.add(if isPrintableByte(b): chr(int(b)) else: opts.unprintable)
    result.add(row)
    offset = stop

proc dump*(data: string; opts: DumpOptions = defaultDumpOptions()): string =
  ## `dumpLines` joined with newlines and a trailing newline, ready to
  ## print or write. Empty input produces the empty string.
  ##
  ## See also:
  ## * `dumpLines proc`_ for the line-by-line form
  ## * `parseDump proc`_ to decode the output back to bytes
  let lines = dumpLines(data, opts)
  if lines.len == 0:
    return ""
  result = lines.join("\n") & "\n"

proc parseDump*(lines: openArray[string]): string {.raises: [].} =
  ## Decodes hex dump lines back into the original bytes. Understands
  ## the layout this module produces (any width and grouping); the
  ## address column and the ASCII gutter are ignored. Blank lines are
  ## skipped, and the parser never raises: lines without an address
  ## column are skipped too, so truncated or mixed input degrades to
  ## "parse what you can" instead of losing the whole dump.
  ##
  ## See also:
  ## * `dumpLines proc`_ to produce the input format
  for line in lines:
    let ci = line.find(':')
    if ci < 0:
      continue
    let rest = line[ci + 1 .. ^1]
    var i = 0
    while i < rest.len:
      if rest[i] == ' ':
        # A second consecutive space marks the end of the hex area:
        # inside the area groups are separated by single spaces only.
        if i + 1 < rest.len and rest[i + 1] == ' ':
          break
        inc i
        continue
      if i + 1 >= rest.len:
        break
      let hi = hexVal(rest[i])
      let lo = hexVal(rest[i + 1])
      if hi < 0 or lo < 0:
        break
      result.add(chr((hi shl 4) or lo))
      i += 2

proc parseDump*(dump: string): string {.raises: [].} =
  ## Overload taking a whole dump as produced by `dump` (newlines
  ## included). See the line-based overload for details.
  parseDump(dump.splitLines())

runnableExamples:
  import std/strutils
  let data = "Hello, world!"
  assert dump(data).startsWith("00000000: 4865 6c6c 6f2c 2077 6f72 6c64 21")
  assert parseDump(dumpLines(data)) == data
  let opts = DumpOptions(width: 4, group: 1, baseAddr: 0x1000,
                         unprintable: '.')
  assert dumpLines(data, opts)[1] == "00001004: 6f 2c 20 77  o, w"
