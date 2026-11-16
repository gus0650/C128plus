#!/usr/bin/env python3
"""End-to-end tests for BASIC 7.1's programming tools (stage 7): $hex and
%binary numbers, MOD(), DIV(), FIND, MERGE, DUMP. Boots the real Kernal and
BASIC from boot0.rom plus BASIC 7.1 in the C128 simulator; MERGE reads from
a pretend disk drive.

usage: test_tools.py boot0.rom [boot2.rom]
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


def boot(rom, b2):
    m = C128(rom, boot2=b2)
    m.run_until(lambda: 'READY.' in m.screen(), 6000000)
    return m


def do(m, line):
    m.type('SCNCLR\r' + line + '\r')
    m.run(100000)
    m.run_until(m.ready, 5000000)
    m.run(150000)
    return m.screen()


def lines_of(scr):
    return [l.strip() for l in scr.split('\n') if l.strip()]


def program(m):
    """Line numbers of the program in memory."""
    r = m.mem.ram[0]; a = r[0x2D] | r[0x2E] << 8; out = []
    while True:
        nxt = r[a] | r[a + 1] << 8
        if nxt == 0: return out
        out.append(r[a + 2] | r[a + 3] << 8); a = nxt


def main():
    rom = open(sys.argv[1], 'rb').read()
    b2 = open(sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'boot2.rom'), 'rb').read()
    m = boot(rom, b2)

    # --- $hex and %binary
    scr = do(m, 'PRINT $D040;%1010;$FFFF;-$10;$0;$DEF0;$DEC+1')
    check('$D040 %1010 $FFFF -$10 $0 $DEF0 $DEC+1', ' 53312  10  65535 -16  0  57072  3565' in scr, scr)
    scr = do(m, 'BANK 15:POKE $1300,%10101011:PRINT PEEK($1300)')
    check('POKE/PEEK with $ and %', ' 171' in scr, scr)
    scr = do(m, 'PRINT $10000')
    check('$10000 is ILLEGAL QUANTITY', 'ILLEGAL QUANTITY' in scr, scr)
    scr = do(m, 'PRINT $G')
    check('$ without digits is SYNTAX', 'SYNTAX' in scr, scr)
    scr = do(m, 'A$="X":B%=7:PRINT A$CHR$(65);B%')
    check('string variables still work (A$CHR$...)', 'XA 7' in scr, scr)
    m.type('NEW\r10 X=$D0+%11:PRINT X;$C0DE\rLIST\r'); m.run(200000)
    check('LIST keeps $D0+%11 and $C0DE', m.screen().count('10 X=$D0+%11:PRINT X;$C0DE') == 2, m.screen())
    scr = do(m, 'RUN')
    check('RUN with hex numbers', ' 211  49374' in scr, scr)

    # --- MOD / DIV
    scr = do(m, 'PRINT MOD(17,5);DIV(17,5);MOD(DIV(100,7),4);DIV($FFFF,256)')
    check('MOD(17,5)=2 DIV(17,5)=3, nested, DIV($FFFF,256)=255', ' 2  3  2  255' in scr, scr)
    scr = do(m, 'PRINT DIV(1,0)')
    check('DIV(1,0) is DIVISION BY ZERO', 'DIVISION BY ZERO' in scr, scr)
    scr = do(m, 'PRINT MOD(-1,2)')
    check('MOD(-1,2) is ILLEGAL QUANTITY', 'ILLEGAL QUANTITY' in scr, scr)

    # --- FIND
    m.type('NEW\r10 PRINT "HELLO"\r20 A=5:REM HELLO THERE\r30 PRINT A\r40 GOTO 10\r'); m.run(200000)
    scr = do(m, 'FIND "HELLO"')
    l = lines_of(scr)
    check('FIND "HELLO" lists lines 10 and 20', any(x.startswith('10 PRINT "HELLO"') for x in l) and any(x.startswith('20 A=5') for x in l)
          and not any(x.startswith('30 ') or x.startswith('40 ') for x in l), l)
    scr = do(m, 'FIND "PRINT"')
    l = lines_of(scr)
    check('FIND "PRINT" (keyword) lists 10 and 30', any(x.startswith('10 ') for x in l) and any(x.startswith('30 ') for x in l)
          and not any(x.startswith('20 ') or x.startswith('40 ') for x in l), l)
    scr = do(m, 'FIND "XYZ"')
    check('FIND with no match lists nothing', not any(x[:2] in ('10', '20', '30', '40') for x in lines_of(scr)), scr)

    # --- DUMP
    scr = do(m, 'CLR:A=5:B%=-3:C$="HI":D=1.5:DUMP')
    l = lines_of(scr)
    check('DUMP lists A, B%, C$, D', 'A= 5' in l and 'B%=-3' in l and 'C$="HI"' in l and 'D= 1.5' in l, l)

    # --- MERGE
    m2 = boot(rom, b2)
    m2.type('20 PRINT 2\r30 PRINT 33\r40 SOUND 4,1000,10\r\r'); m2.run(300000)
    r = m2.mem.ram[0]; end = r[0x1210] | r[0x1211] << 8
    prg = bytes([0x01, 0x1C]) + bytes(r[0x1C01:end])
    disk = m.fake_disk({'PART2': prg})
    m.type('NEW\r10 PRINT 1\r30 PRINT 3\r'); m.run(200000)
    scr = do(m, 'MERGE "PART2"')
    check('MERGE: lines 10, 20, 30, 40', program(m) == [10, 20, 30, 40], program(m))
    scr = do(m, 'LIST')
    check('MERGE: line 30 replaced, 40 keeps the BASIC 7.1 SOUND', '30 PRINT 33' in scr and '40 SOUND 4,1000,10' in scr and '10 PRINT 1' in scr, scr)
    scr = do(m, 'RUN')
    check('merged program runs', ' 1\n 2\n 33' in scr.replace('\n\n', '\n'), scr)
    scr = do(m, 'MERGE "NOPE"')
    check('MERGE of a missing file: FILE NOT FOUND, program kept', 'FILE NOT FOUND' in scr and program(m) == [10, 20, 30, 40], (scr, program(m)))
    m.type('NEW\r10 MERGE "PART2"\rRUN\r'); m.run(300000); m.run_until(m.ready, 3000000)
    check('MERGE in a program is ILLEGAL QUANTITY', 'ILLEGAL QUANTITY' in m.screen(), m.screen())
    m.type('NEW\r10 PRINT 1\r'); m.run(100000)
    do(m, 'MERGE "PART2"')
    scr = do(m, 'PRINT 7*6')
    check('after MERGE the keyboard works again', ' 42' in scr and program(m) == [10, 20, 30, 40], (scr, program(m)))

    print('%d failed' % fails)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
