"""Tests for the C128plus BASIC 7.1 ROM on a small 6502 simulator.

BASIC/Kernal routines are replaced by Python stubs (traps). The simulator also
checks the MMU configuration: BASIC 7.1 ROM code ($C000-$FEFF) may only run with the
BASIC 7.1 map ($10) or the cold-start map ($16), and every BASIC/Kernal call must
happen in the system map ($00).
"""
import os, sys
here = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, here)
import build

# --------------------------------------------------------------------------- CPU
class CPU:
    def __init__(s, mem):
        s.m = mem; s.a = s.x = s.y = 0; s.sp = 0xFD; s.pc = 0
        s.c = s.z = s.i = s.d = s.v = s.n = 0
    def rd(s, a): return s.m.read(a & 0xFFFF)
    def wr(s, a, v): s.m.write(a & 0xFFFF, v & 0xFF)
    def rw(s, a): return s.rd(a) | (s.rd(a + 1) << 8)
    def push(s, v): s.wr(0x100 + s.sp, v); s.sp = (s.sp - 1) & 0xFF
    def pull(s): s.sp = (s.sp + 1) & 0xFF; return s.rd(0x100 + s.sp)
    def p(s): return s.c | s.z << 1 | s.i << 2 | s.d << 3 | 0x30 | s.v << 6 | s.n << 7
    def setp(s, v): s.c, s.z, s.i, s.d, s.v, s.n = v & 1, v >> 1 & 1, v >> 2 & 1, v >> 3 & 1, v >> 6 & 1, v >> 7 & 1
    def nz(s, v): v &= 0xFF; s.z = int(v == 0); s.n = v >> 7; return v

    def addr(s, mode):
        pc = s.pc
        if mode == 'imm': s.pc += 1; return pc
        if mode == 'zp':  s.pc += 1; return s.rd(pc)
        if mode == 'zpx': s.pc += 1; return (s.rd(pc) + s.x) & 0xFF
        if mode == 'zpy': s.pc += 1; return (s.rd(pc) + s.y) & 0xFF
        if mode == 'abs': s.pc += 2; return s.rw(pc)
        if mode == 'absx': s.pc += 2; return (s.rw(pc) + s.x) & 0xFFFF
        if mode == 'absy': s.pc += 2; return (s.rw(pc) + s.y) & 0xFFFF
        if mode == 'indx': s.pc += 1; z = (s.rd(pc) + s.x) & 0xFF; return s.rd(z) | s.rd((z + 1) & 0xFF) << 8
        if mode == 'indy': s.pc += 1; z = s.rd(pc); return ((s.rd(z) | s.rd((z + 1) & 0xFF) << 8) + s.y) & 0xFFFF
        if mode == 'ind': s.pc += 2; a = s.rw(pc); return s.rd(a) | s.rd((a & 0xFF00) | ((a + 1) & 0xFF)) << 8
        raise ValueError(mode)

    def step(s):
        op = s.rd(s.pc); s.pc = (s.pc + 1) & 0xFFFF
        mn, mode = DECODE[op]
        if mn in BRANCH:
            off = s.rd(s.pc); s.pc += 1
            cond = {'bcc': not s.c, 'bcs': s.c, 'beq': s.z, 'bne': not s.z,
                    'bmi': s.n, 'bpl': not s.n, 'bvc': not s.v, 'bvs': s.v}[mn]
            if cond: s.pc = (s.pc + (off - 256 if off > 127 else off)) & 0xFFFF
            return
        if mode in ('imp', 'acc'): ea = None
        else: ea = s.addr(mode)
        def val(): return s.a if mode == 'acc' else s.rd(ea)
        def store(v):
            if mode == 'acc': s.a = v & 0xFF
            else: s.wr(ea, v)
        if mn == 'lda': s.a = s.nz(s.rd(ea))
        elif mn == 'ldx': s.x = s.nz(s.rd(ea))
        elif mn == 'ldy': s.y = s.nz(s.rd(ea))
        elif mn == 'sta': s.wr(ea, s.a)
        elif mn == 'stx': s.wr(ea, s.x)
        elif mn == 'sty': s.wr(ea, s.y)
        elif mn in ('adc', 'sbc'):
            v = s.rd(ea)
            if mn == 'sbc': v ^= 0xFF
            r = s.a + v + s.c
            s.v = int(((s.a ^ r) & (v ^ r) & 0x80) != 0); s.c = int(r > 0xFF); s.a = s.nz(r)
        elif mn in ('and', 'ora', 'eor'):
            v = s.rd(ea); s.a = s.nz(s.a & v if mn == 'and' else s.a | v if mn == 'ora' else s.a ^ v)
        elif mn in ('cmp', 'cpx', 'cpy'):
            r = {'cmp': s.a, 'cpx': s.x, 'cpy': s.y}[mn]; v = s.rd(ea)
            s.c = int(r >= v); s.nz(r - v)
        elif mn == 'bit':
            v = s.rd(ea); s.z = int((s.a & v) == 0); s.n = v >> 7; s.v = v >> 6 & 1
        elif mn in ('inc', 'dec'): store(s.nz(val() + (1 if mn == 'inc' else -1)))
        elif mn == 'inx': s.x = s.nz(s.x + 1)
        elif mn == 'iny': s.y = s.nz(s.y + 1)
        elif mn == 'dex': s.x = s.nz(s.x - 1)
        elif mn == 'dey': s.y = s.nz(s.y - 1)
        elif mn == 'asl': v = val(); s.c = v >> 7; store(s.nz(v << 1))
        elif mn == 'lsr': v = val(); s.c = v & 1; store(s.nz(v >> 1))
        elif mn == 'rol': v = val(); r = (v << 1) | s.c; s.c = v >> 7; store(s.nz(r))
        elif mn == 'ror': v = val(); r = (v >> 1) | (s.c << 7); s.c = v & 1; store(s.nz(r))
        elif mn == 'tax': s.x = s.nz(s.a)
        elif mn == 'tay': s.y = s.nz(s.a)
        elif mn == 'txa': s.a = s.nz(s.x)
        elif mn == 'tya': s.a = s.nz(s.y)
        elif mn == 'tsx': s.x = s.nz(s.sp)
        elif mn == 'txs': s.sp = s.x
        elif mn == 'pha': s.push(s.a)
        elif mn == 'php': s.push(s.p())
        elif mn == 'pla': s.a = s.nz(s.pull())
        elif mn == 'plp': s.setp(s.pull())
        elif mn == 'jmp': s.pc = ea
        elif mn == 'jsr': r = (s.pc - 1) & 0xFFFF; s.push(r >> 8); s.push(r & 0xFF); s.pc = ea
        elif mn == 'rts': lo = s.pull(); hi = s.pull(); s.pc = ((hi << 8 | lo) + 1) & 0xFFFF
        elif mn == 'rti': s.setp(s.pull()); lo = s.pull(); hi = s.pull(); s.pc = hi << 8 | lo
        elif mn == 'clc': s.c = 0
        elif mn == 'sec': s.c = 1
        elif mn == 'cli': s.i = 0
        elif mn == 'sei': s.i = 1
        elif mn == 'cld': s.d = 0
        elif mn == 'sed': s.d = 1
        elif mn == 'clv': s.v = 0
        elif mn == 'nop': pass
        else: raise NotImplementedError(mn)

BRANCH = {'bcc', 'bcs', 'beq', 'bne', 'bmi', 'bpl', 'bvc', 'bvs'}
DECODE = {}
for mn, modes in build.asm6502.OPS.items():
    for mode, opc in modes.items():
        DECODE[opc] = (mn, mode)

# ------------------------------------------------------------------------ memory
class Mem:
    def __init__(s, rom_hi):
        s.ram = bytearray(0x10000); s.rom = rom_hi; s.cfg = 0; s.vic = {}; s.log = []; s.step = 0
    def ext_mapped(s): return (s.cfg >> 4) & 3 == 1
    def read(s, a):
        if a == 0xFF00: return s.cfg
        if 0xD000 <= a < 0xE000 and not (s.cfg & 1):
            return s.vic.get(a, 0xFF)
        if a >= 0xC000 and s.ext_mapped(): return s.rom[a - 0xC000]
        return s.ram[a]
    def write(s, a, v):
        if a == 0xFF00: s.cfg = v; return
        if 0xD000 <= a < 0xE000 and not (s.cfg & 1):
            s.log.append((a, v))
            if a == 0xD03F:                       # VIC-IIx unlock: $A5 then $96
                s.vic[0xD03F] = 0xFE if (v == 0x96 and s.step == 1) else 0xFF
                s.step = 1 if v == 0xA5 else 0
                return
            s.vic[a] = v; return
        s.ram[a] = v

# ------------------------------------------------------------------------ harness
class Basic(Exception): pass
class BasicError(Basic): pass

SENTINEL = 0xFFF0   # address that ends a call

class Machine:
    def __init__(s):
        img, s.syms = build.build()
        s.mem = Mem(img[0x4000:]); s.cpu = CPU(s.mem); s.out = ''
        s.traps = {}
        S = s.syms
        for name in ('chrget', 'chrgot', 'getbyt', 'combyt', 'conint', 'chkcls', 'snerr',
                     'fcerr', 'sngflt', 'chrout', 'optbyt'):
            s.traps[S[name]] = getattr(s, 't_' + name)
        s.traps[S['jsrfar']] = s.t_jsrfar
        s.fac = 0; s.result_y = None
        s.vars = {'R': 3}

    # text pointer helpers
    def tp(s): return s.mem.ram[0x3D] | s.mem.ram[0x3E] << 8
    def set_tp(s, a): s.mem.ram[0x3D] = a & 0xFF; s.mem.ram[0x3E] = a >> 8
    def ch(s): return s.mem.ram[s.tp()]
    def flags_for(s, a):
        c = s.cpu; c.a = a; c.z = int(a == 0 or a == ord(':')); c.c = int(not (ord('0') <= a <= ord('9'))); c.n = a >> 7

    # BASIC stubs
    def check_sys(s, name):
        assert s.mem.cfg == 0, '%s called with MMU config $%02X, must be $00' % (name, s.mem.cfg)
    def t_chrget(s):
        s.check_sys('chrget'); s.set_tp(s.tp() + 1)
        while s.ch() == 0x20: s.set_tp(s.tp() + 1)
        s.flags_for(s.ch())
    def t_chrgot(s):
        s.check_sys('chrgot')
        while s.ch() == 0x20: s.set_tp(s.tp() + 1)
        s.flags_for(s.ch())
    def parse_num(s):
        while s.ch() == 0x20: s.set_tp(s.tp() + 1)
        c = s.ch()
        if chr(c).isalpha():
            v = s.vars[chr(c)]; s.set_tp(s.tp() + 1); return v
        if not chr(c).isdigit(): raise BasicError('SYNTAX')
        v = 0
        while chr(s.ch()).isdigit(): v = v * 10 + s.ch() - 48; s.set_tp(s.tp() + 1)
        return v
    def t_getbyt(s):
        s.check_sys('getbyt'); v = s.parse_num()
        if v > 255: raise BasicError('ILLEGAL QUANTITY')
        s.cpu.x = v; s.t_chrgot()
    def t_combyt(s):
        s.check_sys('combyt')
        while s.ch() == 0x20: s.set_tp(s.tp() + 1)
        if s.ch() != ord(','): raise BasicError('SYNTAX')
        s.set_tp(s.tp() + 1); s.t_getbyt()
    def t_optbyt(s):                      # as BASIC's optbyt ($9E1E)
        s.check_sys('optbyt'); s.t_chrgot()
        if s.cpu.z and s.ch() in (0, ord(':')): s.cpu.c = 0; return
        if s.ch() != ord(','): raise BasicError('SYNTAX')
        s.t_chrget()
        if s.ch() == ord(','): s.cpu.c = 0; return
        s.t_getbyt(); s.cpu.c = 1
    def t_conint(s):
        s.check_sys('conint'); s.cpu.x = s.fac; s.t_chrgot()
    def t_chkcls(s):
        s.check_sys('chkcls')
        if s.ch() != ord(')'): raise BasicError('SYNTAX')
        s.t_chrget()
    def t_snerr(s): s.check_sys('snerr'); raise BasicError('SYNTAX')
    def t_fcerr(s): s.check_sys('fcerr'); raise BasicError('ILLEGAL QUANTITY')
    def t_sngflt(s): s.check_sys('sngflt'); s.result_y = s.cpu.y
    def t_chrout(s): s.check_sys('chrout'); s.out += chr(s.cpu.a)

    def t_jsrfar(s):                      # Kernal JSRFAR: bank $02, address $03/$04, regs $05-$08
        r = s.mem.ram; c = s.cpu
        assert r[2] == 15, 'JSRFAR bank %d' % r[2]
        tgt = r[3] << 8 | r[4]
        s.mem.cfg = 0x00
        c.setp(r[5]); c.a, c.x, c.y = r[6], r[7], r[8]
        if tgt not in s.traps: raise RuntimeError('JSRFAR to unknown $%04X' % tgt)
        s.traps[tgt]()
        r[5], r[6], r[7], r[8] = c.p(), c.a, c.x, c.y
        s.mem.cfg = 0x00

    def call(s, addr, a=0, x=0, y=0, c=0, limit=200000):
        cpu = s.cpu; cpu.a, cpu.x, cpu.y, cpu.c = a, x, y, c
        cpu.sp = 0xFD
        r = SENTINEL - 1; cpu.push(r >> 8); cpu.push(r & 0xFF)
        cpu.pc = addr
        for _ in range(limit):
            pc = cpu.pc
            if pc == SENTINEL: return
            if pc in s.traps:
                s.traps[pc]()
                lo = cpu.pull(); hi = cpu.pull(); cpu.pc = ((hi << 8 | lo) + 1) & 0xFFFF
                continue
            if pc in s.chain:
                s.chain[pc](); return
            if 0xC000 <= pc < 0xFF00:
                assert s.mem.ext_mapped(), 'BASIC 7.1 code at $%04X runs with MMU config $%02X' % (pc, s.mem.cfg)
            cpu.step()
        raise RuntimeError('no return')

def fresh():
    m = Machine(); S = m.syms; r = m.mem.ram
    # BASIC's default hook targets (we only record that the chain was taken)
    defaults = {0x030C: 0xE101, 0x030E: 0xE102, 0x0310: 0xE103, 0x02FC: 0xE104}
    for vec, tgt in defaults.items():
        r[vec] = tgt & 0xFF; r[vec + 1] = tgt >> 8
    m.chained = None
    def mk(name):
        def f(): m.chained = (name, m.cpu.a, m.cpu.x, m.cpu.y, m.cpu.c)
        return f
    m.chain = {0xE101: mk('crunch'), 0xE102: mk('list'), 0xE103: mk('exec'), 0xE104: mk('fn')}
    m.mem.cfg = 0x16                      # Kernal bank 4 during PHOENIX
    m.call(S['coldstart'])
    assert m.mem.cfg == 0x16
    m.mem.cfg = 0x00                      # BASIC runs in the system map
    return m

# --------------------------------------------------------------------------- tests
def put(m, addr, data):
    for i, b in enumerate(data): m.mem.ram[addr + i] = b
    m.mem.ram[addr + len(data)] = 0

def test_coldstart():
    m = fresh(); S = m.syms; r = m.mem.ram
    assert r[0x030C] | r[0x030D] << 8 == S['r_crunch']
    assert r[0x030E] | r[0x030F] << 8 == S['r_list']
    assert r[0x0310] | r[0x0311] << 8 == S['r_exec']
    assert r[0x02FC] | r[0x02FD] << 8 == S['r_fn']
    unlock = [w for w in m.mem.log if w[0] == 0xD03F]
    assert unlock[:2] == [(0xD03F, 0xA5), (0xD03F, 0x96)], unlock
    assert 'C128+ BASIC 7.1' in m.out, repr(m.out)

def crunch(m, text):
    put(m, 0x0200, text.encode()); m.set_tp(0x0200)
    m.chained = None
    m.call(m.syms['r_crunch'], a=text.encode()[0], c=1)
    assert m.mem.cfg == 0
    return m.chained

def test_crunch():
    m = fresh()
    name, a, x, y, c = crunch(m, 'PALETTE 13,6,8')
    assert (a, x, y, c) == (0x40, 0x00, 6, 0), (a, x, y, c)       # Y = index of last char
    name, a, x, y, c = crunch(m, 'RPALETTE(13)')
    assert (a, x, y, c) == (0x40, 0xFF, 7, 0), (a, x, y, c)
    name, a, x, y, c = crunch(m, 'PRINT')
    assert (a, c) == (ord('P'), 1), (a, c)
    name, a, x, y, c = crunch(m, 'PALET')                           # incomplete word
    assert (a, c) == (ord('P'), 1)

def test_list():
    m = fresh()
    for x, name in ((0x00, 'PALETTE'), (0xFF, 'RPALETTE')):
        m.call(m.syms['r_list'], a=0x40, x=x, c=1)
        _, a, xx, y, c = m.chained
        assert c == 0
        p = m.mem.ram[0x24] | m.mem.ram[0x25] << 8
        s = ''
        while True:
            b = m.mem.ram[p]; s += chr(b & 0x7F); p += 1
            if b & 0x80: break
        assert s == name, s
    for tok, name in ((0x41, 'SPRITE'), (0x42, 'SPRPTR')):
        m.call(m.syms['r_list'], a=tok, x=0, c=1)
        p = m.mem.ram[0x24] | m.mem.ram[0x25] << 8; s = ''
        while True:
            b = m.mem.ram[p]; s += chr(b & 0x7F); p += 1
            if b & 0x80: break
        assert s == name and m.chained[4] == 0, s
    m.call(m.syms['r_list'], a=0x50, x=0, c=1)                     # not ours
    assert m.chained[4] == 1 and m.chained[1] == 0x50

def run_stmt(m, body, tok=0x40):
    """body: bytes after the $FE <tok> token; returns error or None."""
    put(m, 0x1C10, bytes([0xFE, tok]) + body)
    m.set_tp(0x1C11)                                                # on second token byte
    try:
        m.call(m.syms['r_exec'], a=tok, c=1)
    except BasicError as e:
        m.mem.cfg = 0
        return str(e)
    assert m.mem.cfg == 0, 'MMU not restored after statement'
    assert m.ch() in (0, ord(':')), 'txtptr not on terminator: %r' % chr(m.ch())
    return None

def test_palette():
    m = fresh(); v = m.mem.vic
    assert run_stmt(m, b' 13,6,8') is None and v[0xD06D] == 0x68
    assert run_stmt(m, b' 0, 15 ,15:') is None and v[0xD060] == 0xFF
    assert run_stmt(m, b' R,5,8') is None and v[0xD063] == 0x58     # variable R = 3
    assert run_stmt(m, b' \x91') is None and v[0xD070] == 1         # ON
    assert run_stmt(m, b' \xfe\x24') is None and v[0xD070] == 0     # OFF
    run_stmt(m, b' \x91')
    assert run_stmt(m, b' RESET') is None
    assert v[0xD070] == 0 and v[0xD06D] == 0x6D and v[0xD060] == 0x00
    assert run_stmt(m, b' 16,1,1') == 'ILLEGAL QUANTITY'
    assert run_stmt(m, b' 1,16,1') == 'ILLEGAL QUANTITY'
    assert run_stmt(m, b' 1,1,16') == 'ILLEGAL QUANTITY'
    assert run_stmt(m, b'') == 'SYNTAX'
    assert run_stmt(m, b' 1,2') == 'SYNTAX'
    assert run_stmt(m, b' \xfe\x25') == 'SYNTAX'
    # foreign escape statement is passed on with carry set
    m.chained = None; put(m, 0x1C10, bytes([0xFE, 0x50])); m.set_tp(0x1C11)
    m.call(m.syms['r_exec'], a=0x50, c=1)
    assert m.chained[0] == 'exec' and m.chained[1] == 0x50 and m.chained[4] == 1
    lock(m)
    assert run_stmt(m, b' 1,2,3') == 'ILLEGAL QUANTITY'              # locked chip
    assert m.mem.vic.get(0xD061) != 0x23

def lock(m):
    m.mem.cfg = 0; m.mem.write(0xD03F, 0)
    assert m.mem.vic[0xD03F] == 0xFF

def test_rpalette():
    m = fresh(); m.mem.vic[0xD06D] = 0x6D
    put(m, 0x1C20, b')'); m.set_tp(0x1C20); m.fac = 13
    m.call(m.syms['r_fn'], a=0x40, c=1)
    assert m.result_y == 0x6D and m.cpu.c == 0 and m.mem.cfg == 0
    assert m.ch() == 0                                              # past ')'
    m.fac = 16; m.set_tp(0x1C20)
    try:
        m.call(m.syms['r_fn'], a=0x40, c=1); assert False
    except BasicError as e:
        assert str(e) == 'ILLEGAL QUANTITY'
    m.mem.cfg = 0; m.chained = None
    m.call(m.syms['r_fn'], a=0x41, c=1)                             # not ours
    assert m.chained[0] == 'fn' and m.chained[4] == 1

def test_crunch_sprite():
    m = fresh()
    assert crunch(m, 'SPRITE 10,1')[1:5] == (0x41, 0x00, 5, 0)
    assert crunch(m, 'SPRPTR 10,200')[1:5] == (0x42, 0x00, 5, 0)
    assert crunch(m, 'SPRDEF')[4] == 1                               # BASIC's own keyword
    assert crunch(m, 'SPRSAV 1,A$')[4] == 1

def test_sprite():
    m = fresh(); v = m.mem.vic
    sp = lambda body: run_stmt(m, body, 0x41)
    for a in (0xD015, 0xD01B, 0xD01D, 0xD017, 0xD01C, 0xD051, 0xD053, 0xD055, 0xD052, 0xD054,
              0xD091, 0xD093, 0xD095, 0xD092, 0xD094):
        v[a] = 0
    assert sp(b' 10,1,5,1,1,0,1') is None
    assert v[0xD051] == 0x02 and v[0xD059] == 4 and v[0xD053] == 0x02
    assert v[0xD055] == 0x02 and v[0xD052] == 0x00 and v[0xD054] == 0x02
    assert sp(b' 1,1,2') is None and v[0xD015] == 0x01 and v[0xD027] == 1
    assert sp(b' 24,1') is None and v[0xD091] == 0x80
    assert sp(b' 17,,3') is None and v[0xD098] == 2 and v[0xD091] == 0x80
    assert sp(b' 10,0') is None and v[0xD051] == 0x00
    assert sp(b' 24,1,16:') is None and v[0xD09F] == 15
    assert sp(b' 25') == 'ILLEGAL QUANTITY'
    assert sp(b' 0') == 'ILLEGAL QUANTITY'
    assert sp(b' 10,2') == 'ILLEGAL QUANTITY'
    assert sp(b' 10,1,17') == 'ILLEGAL QUANTITY'
    assert sp(b' 10,1,0') == 'ILLEGAL QUANTITY'
    lock(m)
    assert sp(b' 10,1') == 'ILLEGAL QUANTITY'                        # locked: 9-24 refused
    assert sp(b' 2,1') is None and v[0xD015] == 0x03                  # 1-8 still work

def test_default_pointers():
    m = fresh(); r = m.mem.ram
    assert list(r[0x07F0:0x07F8]) == list(range(56, 64))
    assert list(r[0x07E8:0x07F0]) == list(range(56, 64))

def test_sprptr():
    m = fresh(); v = m.mem.vic; r = m.mem.ram
    pp = lambda body: run_stmt(m, body, 0x42)
    v[0xD018] = 0x14; v[0xDD00] = 0x97; v[0xD074] = 0                # screen $0400, bank 0
    assert pp(b' 1,200') is None and r[0x07F8] == 200
    assert pp(b' 9,201') is None and r[0x07F0] == 201
    assert pp(b' 24,202') is None and r[0x07EF] == 202
    v[0xD018] = 0x24                                                  # screen $0800
    assert pp(b' 2,7') is None and r[0x0BF9] == 7
    v[0xD074] = 1                                                     # wide: $0800 + $7F8
    assert pp(b' 2,8') is None and r[0x0FF9] == 8
    v[0xD074] = 2; v[0xD075] = 0x0E                                   # pointer page $0E00
    assert pp(b' 1,9') is None and r[0x0EF8] == 9
    assert pp(b' 17,10') is None and r[0x0EE8] == 10
    v[0xD074] = 0; v[0xD018] = 0x14; v[0xDD00] = 0x96                 # VIC bank 1 ($4000)
    assert pp(b' 1,11') is None and r[0x47F8] == 11
    assert pp(b' 25,1') == 'ILLEGAL QUANTITY'
    assert pp(b' 1') == 'SYNTAX'
    assert m.mem.cfg == 0

if __name__ == '__main__':
    tests = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    for t in tests:
        t(); print('ok  ', t.__name__)
    print('all %d tests passed' % len(tests))
