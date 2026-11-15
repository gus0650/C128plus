#!/usr/bin/env python3
"""End-to-end tests for the six-voice BASIC: boots the real Kernal and BASIC
in c128sim and types commands, then checks the SID register writes.

usage: test_sid6.py boot0_patched.rom [boot0_original.rom]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from c128sim import C128

fails = 0


def check(name, cond, info=''):
    global fails
    print(('ok   ' if cond else 'FAIL ') + name + ('' if cond else '  ' + str(info)))
    if not cond: fails += 1


def boot(rom):
    m = C128(rom)
    m.run_until(lambda: 'READY.' in m.screen(), 6000000)
    return m


def do(m, line):
    m.mem.sid_log.clear()
    m.type(line + '\r')
    m.run(150000)
    return list(m.mem.sid_log)


def last_line(m):
    lines = [l for l in m.screen().split('\n') if l.strip()]
    return lines[-2] if len(lines) > 1 else ''


def regs(log):
    d = {}
    for a, v in log: d[a] = v
    return d


def writes_to(log, a):
    return [v for x, v in log if x == a]


def main():
    rom = open(sys.argv[1], 'rb').read()
    m = boot(rom)
    check('boots to READY', 'READY.' in m.screen())
    check('volume of SID 2 set at start-up', m.mem.ram[0][0x1BDD] == 0x0F)

    # --- SOUND on SID 2
    log = do(m, 'SOUND 4,4000,30')
    r = regs(log)
    check('SOUND 4 sets SID 2 voice 1 frequency', r.get(0xD420) == 4000 & 255 and r.get(0xD421) == 4000 >> 8, r)
    check('SOUND 4 gates SID 2 voice 1', 0x41 in writes_to(log, 0xD424), log)
    check('SOUND 4 leaves SID 1 alone', not any(a < 0xD418 for a, v in log), log)
    m.run(400000); g = writes_to(m.mem.sid_log, 0xD424)
    check('SOUND 4 times out (gate off from IRQ)', g and g[-1] == 0x08 and 0x41 in g, g)

    log = do(m, 'SOUND 6,1000,40,0,800,50')
    r = regs(log)
    check('SOUND 6 uses SID 2 voice 3', 0x41 in writes_to(log, 0xD432), log)
    m.mem.sid_log.clear(); m.run(200000)
    f = writes_to(m.mem.sid_log, 0xD42E)
    check('SOUND 6 sweep runs in the IRQ', len(set(f)) > 3, f[:10])

    log = do(m, 'SOUND 1,2000,10')
    r = regs(log)
    check('SOUND 1 still uses SID 1', (0xD400, 2000 & 255) in log and 0x41 in writes_to(log, 0xD404), log)

    do(m, 'SOUND 7,1000,10')
    check('SOUND 7 is ILLEGAL QUANTITY', 'ILLEGAL' in m.screen())

    # --- VOL
    log = do(m, 'VOL 5')
    r = regs(log)
    check('VOL 5 sets both SIDs', r.get(0xD418, 0) & 15 == 5 and r.get(0xD438, 0) & 15 == 5, r)
    log = do(m, 'VOL 3,9')
    r = regs(log)
    check('VOL 3,9 sets SID 1 = 3, SID 2 = 9', r.get(0xD418, 0) & 15 == 3 and r.get(0xD438, 0) & 15 == 9, r)
    do(m, 'VOL 16')
    check('VOL 16 is ILLEGAL QUANTITY', 'ILLEGAL' in m.screen())
    do(m, 'VOL 15')

    # --- PLAY on voices 4..6
    m.run(300000)
    log = do(m, 'PLAY "V5O4QC"')
    r = regs(log)
    check('PLAY V5 sets SID 2 voice 2 frequency', 0xD427 in r and 0xD428 in r, r)
    g = writes_to(log, 0xD42B)
    check('PLAY V5 gates SID 2 voice 2', any(v & 1 for v in g), g)
    m.run(400000); g = writes_to(m.mem.sid_log, 0xD42B)
    check('PLAY V5 note ends (gate off from IRQ)', g and g[-1] & 1 == 0, g)

    log = do(m, 'PLAY "V1O4QE"')
    r = regs(log)
    check('PLAY V1 still on SID 1', 0xD400 in r and any(v & 1 for v in writes_to(log, 0xD404)), log)

    log = do(m, 'PLAY "V4T7"')
    r = regs(log)
    check('PLAY V4 T7 sets envelope on SID 2 voice 1', r.get(0xD425) == 0x09 and r.get(0xD426) == 0x90, r)

    log = do(m, 'PLAY "V6U5"')
    r = regs(log)
    check('PLAY U on voice 6 sets SID 2 volume only', r.get(0xD438, 0) & 15 == 8 and 0xD418 not in r, r)

    # --- FILTER / PLAY X
    do(m, 'FILTER 1024,1,0,0,10')
    log = do(m, 'PLAY "V6X1"')
    r = regs(log)
    check('PLAY V6 X1 routes SID 2 voice 3 through the filter', r.get(0xD437, 0) & 0x0F == 4 and r.get(0xD437, 0) >> 4 == 10, r)
    check('PLAY X1 on SID 2 writes cut-off and mode', r.get(0xD436) == 1024 >> 3 and r.get(0xD438, 0) & 0x10, r)
    check('PLAY X1 on SID 2 leaves SID 1 alone', not any(a < 0xD420 for a in r), r)
    log = do(m, 'PLAY "V2X1"')
    r = regs(log)
    check('PLAY V2 X1 routes SID 1 voice 2', r.get(0xD417, 0) & 0x0F == 2, r)

    do(m, 'PLAY "V7"')
    check('PLAY V7 is ILLEGAL QUANTITY', 'ILLEGAL' in m.screen())

    # --- ordinary BASIC still works
    m.type('10 FOR I=1 TO 3:PRINT I*7;:NEXT\r20 PRINT "DONE"\rRUN\r')
    m.run(300000)
    check('a BASIC program runs', ' 7  14  21' in m.screen() and 'DONE' in m.screen(), m.screen())

    # --- original ROM: SOUND 4 must fail there (sanity check of the test)
    if len(sys.argv) > 2:
        o = boot(open(sys.argv[2], 'rb').read())
        do(o, 'SOUND 4,4000,30')
        check('original ROM rejects SOUND 4', 'ILLEGAL' in o.screen())

    print('%d failed' % fails)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
