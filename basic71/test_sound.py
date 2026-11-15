#!/usr/bin/env python3
"""End-to-end tests for BASIC 7.1's six-voice sound (stage 6): boots the real
Kernal and BASIC from boot0.rom plus BASIC 7.1 (boot2.rom) in the C128
simulator, types commands and checks the writes to both SIDs.

usage: test_sound.py boot0.rom [boot2.rom]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "basic70"))
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
    b2 = open(sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'boot2.rom'), 'rb').read()
    m = boot(rom, b2)
    check('boots to READY with BASIC 7.1', 'READY.' in m.screen() and 'BASIC 7.1' in m.screen())

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

    # --- LIST shows the keywords, tokens are BASIC 7.1's
    m.type('NEW\r30 SOUND 5,1000,10:PLAY "V4C":VOL 9:FILTER 500\rLIST\r')
    m.run(200000)
    check('LIST shows SOUND/PLAY/VOL/FILTER', m.screen().count('SOUND 5,1000,10:PLAY "V4C":VOL 9:FILT\nER 500') == 2, m.screen())
    prg = bytes(m.mem.ram[0][0x1C00:0x1C30])
    check('stored as BASIC 7.1 tokens', bytes([0xFE, 0x43]) in prg and bytes([0xFE, 0x44]) in prg, prg.hex())

    # --- SID6 OFF: BASIC's own commands again
    do(m, 'SID6 OFF')
    m.type('NEW\r40 SOUND 1,1000,10\r'); m.run(100000)
    prg = bytes(m.mem.ram[0][0x1C00:0x1C20])
    check('SID6 OFF: SOUND stays a BASIC 7.0 token', 0xDA in prg and bytes([0xFE, 0x43]) not in prg, prg.hex())
    do(m, 'SOUND 4,1000,10')
    check('SID6 OFF: BASIC\'s SOUND rejects voice 4', 'ILLEGAL' in m.screen())
    do(m, 'SID6 ON')
    log = do(m, 'SOUND 4,1000,10')
    check('SID6 ON: SOUND 4 works again', 0x41 in writes_to(log, 0xD424), log)

    # --- after IF ... THEN, and both chips in one PLAY string
    m.type('NEW\r10 IF 1 THEN SOUND 6,1500,5\rRUN\r'); m.run(100000)
    check('SOUND after IF ... THEN', (0xD42E, 1500 & 255) in m.mem.sid_log)
    m.run(300000)
    m.mem.sid_log.clear()
    m.type('PLAY "V1O4HCV4O3HE"\r')
    t0 = len(m.mem.sid_log)
    ends = {}
    for k in range(80):
        m.run(5000)
        for a, v in m.mem.sid_log[t0:]:
            if a in (0xD404, 0xD424) and v & 1 == 0 and a not in ends: ends[a] = k
        t0 = len(m.mem.sid_log)
    g1 = writes_to(m.mem.sid_log, 0xD404); g2 = writes_to(m.mem.sid_log, 0xD424)
    check('PLAY V1/V4 chord: both voices start', any(v & 1 for v in g1) and any(v & 1 for v in g2), (g1, g2))
    check('PLAY V1/V4 chord: both notes end together', len(ends) == 2 and abs(ends[0xD404] - ends[0xD424]) <= 1, ends)

    # --- RUN/STOP + RESTORE: Kernal restores the IRQ vector, then warm starts
    r = m.mem.ram[0]
    hook = r[0x314] | r[0x315] << 8
    do(m, 'SOUND 5,2000,600')
    m.run(20000)
    r[0x314], r[0x315] = 0x65, 0xFA          # what RESTOR puts back (Kernal IRQ)
    m.mem.sid_log.clear()
    c = m.cpu; c.i = 1; c.pc = r[0xA00] | r[0xA01] << 8
    m.run_until(lambda: 'READY.' in m.screen().split('\n')[-1] or m.ready(), 3000000)
    m.run(100000)
    g = writes_to(m.mem.sid_log, 0xD42B)
    check('RESTORE silences SID 2', g and g[-1] & 1 == 0, g)
    check('RESTORE re-installs the IRQ hook', (r[0x314] | r[0x315] << 8) == hook)
    log = do(m, 'SOUND 4,1000,20')
    m.run(300000); g = writes_to(m.mem.sid_log, 0xD424)
    check('SOUND 4 times out after RESTORE', g and g[-1] == 0x08 and 0x41 in g, g)

    print('%d failed' % fails)
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
