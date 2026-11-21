"""Set the version field of every code directory in a signed Mach-O.
Modern signers write version 0x20400; the iOS 8 kernel predates it.  The
fields added after 0x20001 are ignored when the version says they are absent.
usage: cdversion.py <file> <hexversion>"""
import struct, sys
path, ver = sys.argv[1], int(sys.argv[2], 16)
data = bytearray(open(path, 'rb').read())
n, off = 0, 0
while True:
    off = data.find(b'\xfa\xde\x0c\x02', off)
    if off < 0: break
    struct.pack_into('>I', data, off + 8, ver)
    n += 1; off += 4
open(path, 'wb').write(data)
print('patched %d code directories' % n)
