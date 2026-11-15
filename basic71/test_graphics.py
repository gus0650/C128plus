#!/usr/bin/env python3
"""End-to-end tests for BASIC 7.1's VIC-IIx commands: boots the real Kernal
and BASIC from boot0.rom plus BASIC 7.1 (boot2.rom) in the C128 simulator,
types commands and checks the VIC-IIx registers and sprite pointers.

usage: test_graphics.py boot0.rom [boot2.rom]
"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'basic70'))
from c128sim import C128

fails = 0


def check(name, cond, info=''):
    global fails
    print(('ok   ' if cond else 'FAIL ') + name + ('' if cond else '  ' + str(info)))
    if not cond: fails += 1


def do(m, line):
    m.type(line + '\r')
    m.run(100000)
    return m.screen()


def last_error(m):
    return 'ILLEGAL QUANTITY' in m.screen().split('READY.')[-2] if m.screen().count('READY.') > 1 else False


def main():
    rom = open(sys.argv[1], 'rb').read()
    b2 = open(sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'boot2.rom'), 'rb').read()
    m = C128(rom, boot2=b2)
    m.run_until(lambda: 'READY.' in m.screen(), 6000000)
    x = m.mem.vicx; r = m.mem.ram[0]
    check('start-up line', 'C128+ BASIC 7.1' in m.screen(), m.screen())
    check('VIC-IIx unlocked at start-up', m.mem.vicx_unlocked)
    check('default pointers: sprites 9-16 = blocks 56-63', list(r[0x7F0:0x7F8]) == list(range(56, 64)), list(r[0x7F0:0x7F8]))
    check('default pointers: sprites 17-24 = blocks 56-63', list(r[0x7E8:0x7F0]) == list(range(56, 64)), list(r[0x7E8:0x7F0]))

    do(m, 'SPRITE 9,1,5')
    check('SPRITE 9,1,5: enable bit 0 of $D051, colour 4 in $D058', x[0x51] & 1 and x[0x58] == 4, (x[0x51], x[0x58]))
    do(m, 'SPRITE 17,1,16')
    check('SPRITE 17,1,16: $D091 bit 0, colour 15 in $D098', x[0x91] & 1 and x[0x98] == 15, (x[0x91], x[0x98]))
    do(m, 'SPRITE 24,1,,1,1,1,1')
    check('SPRITE 24 priority/x/y/multicolour bits', all(x[a] & 0x80 for a in (0x93, 0x95, 0x92, 0x94)),
          [hex(x[a]) for a in (0x93, 0x95, 0x92, 0x94)])
    do(m, 'SPRITE 24,,,0,0,0,0')
    check('SPRITE 24 bits cleared again, still enabled', not any(x[a] & 0x80 for a in (0x93, 0x95, 0x92, 0x94)) and x[0x91] & 0x80)
    do(m, 'SPRITE 3,1,8')
    check('SPRITE 3 uses the stock registers', m.mem.vic[0x15] & 4 and m.mem.vic[0x29] == 7, (m.mem.vic[0x15], m.mem.vic[0x29]))
    do(m, 'SPRITE 25,1')
    check('SPRITE 25 is ILLEGAL QUANTITY', 'ILLEGAL' in m.screen())

    do(m, 'SPRPTR 9,57:SPRPTR 24,58:SPRPTR 1,60')
    check('SPRPTR writes after the screen', r[0x7F0] == 57 and r[0x7EF] == 58 and r[0x7F8] == 60,
          (r[0x7F0], r[0x7EF], r[0x7F8]))

    do(m, 'POKE 53364,2:POKE 53365,48:SPRPTR 10,61:POKE 53364,0')
    check('SPRPTR with PTRSEP: pointer page $30', r[0x30F1] == 61, r[0x30F1])

    do(m, 'PALETTE 3,9,12')
    check('PALETTE 3,9,12 -> $D063 = $9C', x[0x63] == 0x9C, hex(x[0x63]))
    do(m, 'PALETTE ON')
    check('PALETTE ON sets PALEN', x[0x70] == 1)
    do(m, 'PRINT RPALETTE(3)')
    check('RPALETTE(3) = 156', ' 156' in m.screen())
    do(m, 'PALETTE OFF')
    check('PALETTE OFF clears PALEN', x[0x70] == 0)
    do(m, 'PALETTE ON:PALETTE RESET')
    check('PALETTE RESET: stock values, PALEN off',
          bytes(x[0x60:0x70]).hex() == '000f148be678b34d26331804076db80a' and x[0x70] == 0, bytes(x[0x60:0x70]).hex())
    do(m, 'SCNCLR:PALETTE 16,0,0')
    check('PALETTE 16 is ILLEGAL QUANTITY', 'ILLEGAL' in m.screen())

    do(m, 'SCNCLR:POKE 53311,0:PALETTE 1,1,1')
    check('locked: PALETTE is ILLEGAL QUANTITY', 'ILLEGAL' in m.screen())
    do(m, 'SCNCLR:SPRITE 10,1')
    check('locked: SPRITE 10 is ILLEGAL QUANTITY', 'ILLEGAL' in m.screen())
    do(m, 'SCNCLR:SPRITE 2,1')
    check('locked: SPRITE 2 still works', 'ILLEGAL' not in m.screen() and m.mem.vic[0x15] & 2)

    print('%d failed' % fails)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
