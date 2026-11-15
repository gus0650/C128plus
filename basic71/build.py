"""Build boot2.rom (C128plus BASIC 7.1 internal function ROM) from basic71.asm."""
import sys, os
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import asm6502

def build(src=os.path.join(here, 'basic71.asm')):
    out, syms = asm6502.assemble(open(src).read(), os.path.basename(src))
    img = bytearray([0xFF] * 0x8000)
    for a, v in out.items():
        img[a] = v
    return bytes(img), syms

if __name__ == '__main__':
    img, syms = build()
    dst = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, 'boot2.rom')
    open(dst, 'wb').write(img)
    print('%s: 32768 bytes, RAM part %d bytes' % (dst, syms['ram_end'] - 0x1800))
