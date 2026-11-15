#!/usr/bin/env python3
"""Minimal C128 (8502 side) simulator for testing BASIC ROM changes.

Runs the real Kernal and BASIC from boot0.rom: 6502 CPU, 8722 MMU, 256K RAM,
VIC raster IRQ, VIC-IIx unlock and extension registers, keyboard buffer
input, SID write log. No video, no disk:
the Kernal's disk boot ($F890) is skipped.
"""
import sys

# ------------------------------------------------------------------- 6502
OPS = {
 'adc':{'imm':0x69,'zp':0x65,'zpx':0x75,'abs':0x6d,'absx':0x7d,'absy':0x79,'indx':0x61,'indy':0x71},
 'and':{'imm':0x29,'zp':0x25,'zpx':0x35,'abs':0x2d,'absx':0x3d,'absy':0x39,'indx':0x21,'indy':0x31},
 'asl':{'acc':0x0a,'zp':0x06,'zpx':0x16,'abs':0x0e,'absx':0x1e},
 'bit':{'zp':0x24,'abs':0x2c},
 'bpl':{'rel':0x10},'bmi':{'rel':0x30},'bvc':{'rel':0x50},'bvs':{'rel':0x70},
 'bcc':{'rel':0x90},'bcs':{'rel':0xb0},'bne':{'rel':0xd0},'beq':{'rel':0xf0},
 'brk':{'imp':0x00},
 'cmp':{'imm':0xc9,'zp':0xc5,'zpx':0xd5,'abs':0xcd,'absx':0xdd,'absy':0xd9,'indx':0xc1,'indy':0xd1},
 'cpx':{'imm':0xe0,'zp':0xe4,'abs':0xec},'cpy':{'imm':0xc0,'zp':0xc4,'abs':0xcc},
 'dec':{'zp':0xc6,'zpx':0xd6,'abs':0xce,'absx':0xde},
 'eor':{'imm':0x49,'zp':0x45,'zpx':0x55,'abs':0x4d,'absx':0x5d,'absy':0x59,'indx':0x41,'indy':0x51},
 'clc':{'imp':0x18},'sec':{'imp':0x38},'cli':{'imp':0x58},'sei':{'imp':0x78},
 'clv':{'imp':0xb8},'cld':{'imp':0xd8},'sed':{'imp':0xf8},
 'inc':{'zp':0xe6,'zpx':0xf6,'abs':0xee,'absx':0xfe},
 'jmp':{'abs':0x4c,'ind':0x6c},'jsr':{'abs':0x20},
 'lda':{'imm':0xa9,'zp':0xa5,'zpx':0xb5,'abs':0xad,'absx':0xbd,'absy':0xb9,'indx':0xa1,'indy':0xb1},
 'ldx':{'imm':0xa2,'zp':0xa6,'zpy':0xb6,'abs':0xae,'absy':0xbe},
 'ldy':{'imm':0xa0,'zp':0xa4,'zpx':0xb4,'abs':0xac,'absx':0xbc},
 'lsr':{'acc':0x4a,'zp':0x46,'zpx':0x56,'abs':0x4e,'absx':0x5e},
 'nop':{'imp':0xea},
 'ora':{'imm':0x09,'zp':0x05,'zpx':0x15,'abs':0x0d,'absx':0x1d,'absy':0x19,'indx':0x01,'indy':0x11},
 'tax':{'imp':0xaa},'txa':{'imp':0x8a},'dex':{'imp':0xca},'inx':{'imp':0xe8},
 'tay':{'imp':0xa8},'tya':{'imp':0x98},'dey':{'imp':0x88},'iny':{'imp':0xc8},
 'rol':{'acc':0x2a,'zp':0x26,'zpx':0x36,'abs':0x2e,'absx':0x3e},
 'ror':{'acc':0x6a,'zp':0x66,'zpx':0x76,'abs':0x6e,'absx':0x7e},
 'rti':{'imp':0x40},'rts':{'imp':0x60},
 'sbc':{'imm':0xe9,'zp':0xe5,'zpx':0xf5,'abs':0xed,'absx':0xfd,'absy':0xf9,'indx':0xe1,'indy':0xf1},
 'sta':{'zp':0x85,'zpx':0x95,'abs':0x8d,'absx':0x9d,'absy':0x99,'indx':0x81,'indy':0x91},
 'stx':{'zp':0x86,'zpy':0x96,'abs':0x8e},'sty':{'zp':0x84,'zpx':0x94,'abs':0x8c},
 'txs':{'imp':0x9a},'tsx':{'imp':0xba},'pha':{'imp':0x48},'pla':{'imp':0x68},
 'php':{'imp':0x08},'plp':{'imp':0x28},
}
DECODE = {}
for _mn, _modes in OPS.items():
    for _mode, _opc in _modes.items():
        DECODE[_opc] = (_mn, _mode)


class CPU:
    def __init__(s, mem):
        s.m = mem; s.a = s.x = s.y = 0; s.sp = 0xFD; s.pc = 0
        s.c = s.z = s.i = s.d = s.v = s.n = 0
    def rd(s, a): return s.m.read(a & 0xFFFF)
    def wr(s, a, v): s.m.write(a & 0xFFFF, v & 0xFF)
    def rw(s, a): return s.rd(a) | (s.rd(a + 1) << 8)
    def push(s, v): s.wr(0x100 + s.sp, v); s.sp = (s.sp - 1) & 0xFF
    def pull(s): s.sp = (s.sp + 1) & 0xFF; return s.rd(0x100 + s.sp)
    def p(s): return s.c | s.z << 1 | s.i << 2 | s.d << 3 | 0x20 | s.v << 6 | s.n << 7
    def setp(s, v): s.c, s.z, s.i, s.d, s.v, s.n = v & 1, v >> 1 & 1, v >> 2 & 1, v >> 3 & 1, v >> 6 & 1, v >> 7 & 1
    def nz(s, v): v &= 0xFF; s.z = int(v == 0); s.n = v >> 7; return v

    def irq(s):
        if s.i: return False
        s.push(s.pc >> 8); s.push(s.pc & 0xFF); s.push(s.p() & ~0x10)
        s.i = 1; s.pc = s.rw(0xFFFE); return True

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
        if op not in DECODE: raise RuntimeError('illegal opcode %02x at %04x' % (op, s.pc - 1))
        mn, mode = DECODE[op]
        if mode == 'rel':
            off = s.rd(s.pc); s.pc = (s.pc + 1) & 0xFFFF
            cond = {'bcc': not s.c, 'bcs': s.c, 'beq': s.z, 'bne': not s.z,
                    'bmi': s.n, 'bpl': not s.n, 'bvc': not s.v, 'bvs': s.v}[mn]
            if cond: s.pc = (s.pc + (off - 256 if off > 127 else off)) & 0xFFFF
            return
        ea = None if mode in ('imp', 'acc') else s.addr(mode)
        s.pc &= 0xFFFF
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
        elif mn == 'adc':
            v = s.rd(ea)
            if s.d:
                lo = (s.a & 15) + (v & 15) + s.c
                if lo > 9: lo += 6
                hi = (s.a >> 4) + (v >> 4) + (lo > 15)
                if hi > 9: hi += 6
                r = ((hi << 4) | (lo & 15)) & 0xFF; s.c = int(hi > 15); s.a = s.nz(r)
            else:
                r = s.a + v + s.c
                s.v = int(((s.a ^ r) & (v ^ r) & 0x80) != 0); s.c = int(r > 0xFF); s.a = s.nz(r)
        elif mn == 'sbc':
            v = s.rd(ea)
            if s.d:
                lo = (s.a & 15) - (v & 15) - (1 - s.c)
                hi = (s.a >> 4) - (v >> 4)
                if lo < 0: lo -= 6; hi -= 1
                if hi < 0: hi -= 6
                s.c = int(s.a - v - (1 - s.c) >= 0)
                s.a = s.nz(((hi << 4) | (lo & 15)) & 0xFF)
            else:
                v ^= 0xFF; r = s.a + v + s.c
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
        elif mn == 'php': s.push(s.p() | 0x10)
        elif mn == 'pla': s.a = s.nz(s.pull())
        elif mn == 'plp': s.setp(s.pull())
        elif mn == 'jmp': s.pc = ea
        elif mn == 'jsr': r = (s.pc - 1) & 0xFFFF; s.push(r >> 8); s.push(r & 0xFF); s.pc = ea
        elif mn == 'rts': lo = s.pull(); hi = s.pull(); s.pc = ((hi << 8 | lo) + 1) & 0xFFFF
        elif mn == 'rti': s.setp(s.pull()); lo = s.pull(); hi = s.pull(); s.pc = hi << 8 | lo
        elif mn == 'brk':
            s.pc = (s.pc + 1) & 0xFFFF
            s.push(s.pc >> 8); s.push(s.pc & 0xFF); s.push(s.p() | 0x10); s.i = 1; s.pc = s.rw(0xFFFE)
        elif mn == 'clc': s.c = 0
        elif mn == 'sec': s.c = 1
        elif mn == 'cli': s.i = 0
        elif mn == 'sei': s.i = 1
        elif mn == 'cld': s.d = 0
        elif mn == 'sed': s.d = 1
        elif mn == 'clv': s.v = 0
        elif mn == 'nop': pass
        else: raise NotImplementedError(mn)


# ------------------------------------------------------------------ memory
class C128Mem:
    def __init__(s, boot0, boot2=None):
        s.fn = boot2 or bytes([0xFF]) * 0x8000
        s.ram = [bytearray(0x10000) for _ in range(4)]
        s.kernal = boot0[0x4000:0x8000]       # $C000-$FFFF
        s.basic = boot0[0x8000:0x10000]       # $4000-$BFFF
        s.chargen = boot0[0x10000:0x11000]
        s.cr = 0; s.pcr = [0, 0, 0, 0]; s.mcr = 0xB9; s.rcr = 0; s.mmu = bytearray(12)
        s.vic = bytearray(0x40); s.raster = 0; s.vic_irq = 0
        s.vicx = bytearray(0x100); s.vicx_unlocked = False; s.vicx_step = 0   # VIC-IIx
        s.sid_log = []            # (address, value)
        s.cia = bytearray(0x200)
        s.ext = {}                # other I/O

    def bank_of(s, a):
        b = (s.cr >> 6) & 3
        if b and s.rcr & 0x0C:
            size = (0x400, 0x1000, 0x2000, 0x4000)[s.rcr & 3]
            if (s.rcr & 4 and a < size) or (s.rcr & 8 and a >= 0x10000 - size):
                return 0
        return b

    def read(s, a):
        if 0xFF00 <= a <= 0xFF04:
            return s.cr if a == 0xFF00 else s.pcr[a - 0xFF01]
        cr = s.cr
        if 0xD000 <= a < 0xE000 and not cr & 1:
            return s.io_read(a)
        if 0x4000 <= a < 0x8000 and not cr & 2:
            return s.basic[a - 0x4000]
        if 0x8000 <= a < 0xC000:
            m = (cr >> 2) & 3
            if m == 0: return s.basic[a - 0x4000]
            if m == 1: return s.fn[a - 0x8000]
            if m == 2: return 0xFF
        if a >= 0xC000:
            m = (cr >> 4) & 3
            if m == 0:
                if 0xD000 <= a < 0xE000: return s.chargen[a - 0xD000]
                return s.kernal[a - 0xC000]
            if m == 1:
                if 0xD000 <= a < 0xE000 and not cr & 1: return s.io_read(a)
                return s.fn[a - 0x8000]
            if m == 2: return 0xFF
        return s.ram[s.bank_of(a)][a]

    def write(s, a, v):
        if a == 0xFF00: s.cr = v; return
        if 0xFF01 <= a <= 0xFF04: s.cr = s.pcr[a - 0xFF01]; return
        if 0xD000 <= a < 0xE000 and not s.cr & 1:
            s.io_write(a, v); return
        s.ram[s.bank_of(a)][a] = v

    def io_read(s, a):
        if a < 0xD400:
            if s.vicx_unlocked and 0x40 <= (a & 0xFF) < 0xC0:
                return s.vicx[a & 0xFF]
            r = a & 0x3F
            if r == 0x3F: return 0xFE if s.vicx_unlocked else 0xFF
            if r in (0x11, 0x12): s.raster = (s.raster + 1) % 312
            if r == 0x12: return s.raster & 0xFF
            if r == 0x11: return (s.vic[0x11] & 0x7F) | ((s.raster >> 1) & 0x80)
            if r == 0x19: return s.vic_irq | (0x80 if s.vic_irq else 0) | 0x70
            if r in (0x1E, 0x1F): return 0
            return s.vic[r]
        if a < 0xD500: return 0
        if a < 0xD600:
            r = a & 0xFF
            if r == 0: return s.cr
            if 1 <= r <= 4: return s.pcr[r - 1]
            if r == 5: return s.mcr
            if r == 6: return s.rcr
            if r < 12: return s.mmu[r]
            if r == 0x0B: return 0x20
            return 0xFF
        if a < 0xD700: return 0x80 if a == 0xD600 else 0xFF   # no VDC
        if 0xDC00 <= a < 0xDE00:
            r = a & 0x10F; base = a & 0xDD00
            if a & 0xFF0F == 0xDC01 and base == 0xDC00: return 0xFF   # no keys
            if r in (0x0D, 0x10D): return 0
            return s.cia[(a - 0xDC00) & 0x1FF]
        return 0xFF

    def io_write(s, a, v):
        if a < 0xD400:
            if s.vicx_unlocked and 0x40 <= (a & 0xFF) < 0xC0:
                s.vicx[a & 0xFF] = v; return
            r = a & 0x3F
            if r == 0x3F:                     # VIC-IIx unlock: $A5 then $96
                s.vicx_unlocked = (v == 0x96 and s.vicx_step == 1)
                s.vicx_step = 1 if v == 0xA5 else 0
                return
            if r == 0x19: s.vic_irq &= ~v & 0x0F; return
            s.vic[r] = v; return
        if a < 0xD500: s.sid_log.append((a, v)); return
        if a < 0xD600:
            r = a & 0xFF
            if r == 0: s.cr = v
            elif 1 <= r <= 4: s.pcr[r - 1] = v
            elif r == 5: s.mcr = (s.mcr & 0xB9) | (v & 0x46)
            elif r == 6: s.rcr = v
            elif r < 12: s.mmu[r] = v
            return
        if 0xDC00 <= a < 0xDE00: s.cia[(a - 0xDC00) & 0x1FF] = v; return


class C128:
    KEYD, NDX = 0x034A, 0xD0

    def __init__(s, boot0, skip=(), boot2=None):
        s.mem = C128Mem(boot0, boot2); s.cpu = CPU(s.mem)
        s.cpu.pc = s.cpu.rw(0xFFFC); s.cpu.i = 1
        s.steps = 0
        s.traps = {0xF890} | set(skip)  # skip disk boot
    def do_rts(s):
        c = s.cpu; lo = c.pull(); hi = c.pull(); c.pc = ((hi << 8 | lo) + 1) & 0xFFFF

    def run(s, n, irq_every=4000):
        c = s.cpu; m = s.mem
        for _ in range(n):
            if c.pc in s.traps and m.cr & 0x30 == 0:
                s.do_rts(); continue
            c.step(); s.steps += 1
            if s.steps % irq_every == 0:
                m.vic_irq |= 1
                if m.vic[0x1A] & 1: c.irq()

    def screen(s):
        r = s.mem.ram[0]
        lines = []
        for y in range(25):
            row = ''
            for x in range(40):
                ch = r[0x400 + y * 40 + x] & 0x7F
                row += chr(ch + 64) if 1 <= ch <= 26 else chr(ch) if 32 <= ch < 64 else ' ' if ch == 0x20 else '@' if ch == 0 else '?'
            lines.append(row.rstrip())
        return '\n'.join(lines)

    def ready(s):
        return s.mem.ram[0][s.NDX] == 0

    def type(s, text, steps_per_chunk=300000):
        """Type text (use \\r for RETURN) and run until the buffer is consumed."""
        text = text.upper()
        i = 0
        while i < len(text):
            s.run_until(s.ready, 2000000)
            chunk = text[i:i + 10]; i += 10
            for k, ch in enumerate(chunk):
                s.mem.ram[0][s.KEYD + k] = ord(ch)
            s.mem.ram[0][s.NDX] = len(chunk)
        s.run_until(s.ready, 2000000)

    def run_until(s, cond, limit, chunk=2000):
        n = 0
        while not cond():
            s.run(chunk); n += chunk
            if n > limit: raise TimeoutError('timeout at pc=%04x' % s.cpu.pc)

    def idle(s, n):
        s.run(n)
