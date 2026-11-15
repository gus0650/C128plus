"""Small two-pass 6502 assembler for the C128plus BASIC 7.1 function ROM.

Syntax
  label:              define label at current PC
  NAME = expr         constant
  mnemonic operand    instructions (all official 6502 opcodes and modes)
  .org expr           set PC (output follows PC relative to .base)
  .base expr          address that output offset 0 corresponds to
  .rorg expr / .rend  assemble at a different run address (code copied there at runtime)
  .byte / .word       data; .byte accepts "strings" (copied as-is, ASCII = PETSCII upper case)
  .fill n[,value]
  .assert expr, "message"
Expressions: $hex %bin dec 'c' labels * (current PC), + - * / & | ^ << >> ( ),
  prefix < (low byte) and > (high byte). Comments start with ';'.
"""
import re, sys

OPS = {
 'adc': {'imm':0x69,'zp':0x65,'zpx':0x75,'abs':0x6D,'absx':0x7D,'absy':0x79,'indx':0x61,'indy':0x71},
 'and': {'imm':0x29,'zp':0x25,'zpx':0x35,'abs':0x2D,'absx':0x3D,'absy':0x39,'indx':0x21,'indy':0x31},
 'asl': {'acc':0x0A,'zp':0x06,'zpx':0x16,'abs':0x0E,'absx':0x1E},
 'bcc': {'rel':0x90}, 'bcs': {'rel':0xB0}, 'beq': {'rel':0xF0}, 'bmi': {'rel':0x30},
 'bne': {'rel':0xD0}, 'bpl': {'rel':0x10}, 'bvc': {'rel':0x50}, 'bvs': {'rel':0x70},
 'bit': {'zp':0x24,'abs':0x2C},
 'brk': {'imp':0x00}, 'clc': {'imp':0x18}, 'cld': {'imp':0xD8}, 'cli': {'imp':0x58}, 'clv': {'imp':0xB8},
 'cmp': {'imm':0xC9,'zp':0xC5,'zpx':0xD5,'abs':0xCD,'absx':0xDD,'absy':0xD9,'indx':0xC1,'indy':0xD1},
 'cpx': {'imm':0xE0,'zp':0xE4,'abs':0xEC}, 'cpy': {'imm':0xC0,'zp':0xC4,'abs':0xCC},
 'dec': {'zp':0xC6,'zpx':0xD6,'abs':0xCE,'absx':0xDE}, 'dex': {'imp':0xCA}, 'dey': {'imp':0x88},
 'eor': {'imm':0x49,'zp':0x45,'zpx':0x55,'abs':0x4D,'absx':0x5D,'absy':0x59,'indx':0x41,'indy':0x51},
 'inc': {'zp':0xE6,'zpx':0xF6,'abs':0xEE,'absx':0xFE}, 'inx': {'imp':0xE8}, 'iny': {'imp':0xC8},
 'jmp': {'abs':0x4C,'ind':0x6C}, 'jsr': {'abs':0x20},
 'lda': {'imm':0xA9,'zp':0xA5,'zpx':0xB5,'abs':0xAD,'absx':0xBD,'absy':0xB9,'indx':0xA1,'indy':0xB1},
 'ldx': {'imm':0xA2,'zp':0xA6,'zpy':0xB6,'abs':0xAE,'absy':0xBE},
 'ldy': {'imm':0xA0,'zp':0xA4,'zpx':0xB4,'abs':0xAC,'absx':0xBC},
 'lsr': {'acc':0x4A,'zp':0x46,'zpx':0x56,'abs':0x4E,'absx':0x5E}, 'nop': {'imp':0xEA},
 'ora': {'imm':0x09,'zp':0x05,'zpx':0x15,'abs':0x0D,'absx':0x1D,'absy':0x19,'indx':0x01,'indy':0x11},
 'pha': {'imp':0x48}, 'php': {'imp':0x08}, 'pla': {'imp':0x68}, 'plp': {'imp':0x28},
 'rol': {'acc':0x2A,'zp':0x26,'zpx':0x36,'abs':0x2E,'absx':0x3E},
 'ror': {'acc':0x6A,'zp':0x66,'zpx':0x76,'abs':0x6E,'absx':0x7E},
 'rti': {'imp':0x40}, 'rts': {'imp':0x60},
 'sbc': {'imm':0xE9,'zp':0xE5,'zpx':0xF5,'abs':0xED,'absx':0xFD,'absy':0xF9,'indx':0xE1,'indy':0xF1},
 'sec': {'imp':0x38}, 'sed': {'imp':0xF8}, 'sei': {'imp':0x78},
 'sta': {'zp':0x85,'zpx':0x95,'abs':0x8D,'absx':0x9D,'absy':0x99,'indx':0x81,'indy':0x91},
 'stx': {'zp':0x86,'zpy':0x96,'abs':0x8E}, 'sty': {'zp':0x84,'zpx':0x94,'abs':0x8C},
 'tax': {'imp':0xAA}, 'tay': {'imp':0xA8}, 'tsx': {'imp':0xBA}, 'txa': {'imp':0x8A},
 'txs': {'imp':0x9A}, 'tya': {'imp':0x98},
}
SIZE = {'imp':1,'acc':1,'imm':2,'zp':2,'zpx':2,'zpy':2,'rel':2,'indx':2,'indy':2,
        'abs':3,'absx':3,'absy':3,'ind':3}
ZP_OF = {'abs':'zp','absx':'zpx','absy':'zpy'}

class AsmError(Exception): pass

class Assembler:
    def __init__(self, src, name='<src>'):
        self.lines = src.splitlines(); self.name = name

    def ev(self, expr, pc, final):
        e = expr.strip()
        if not e: raise AsmError('empty expression')
        part = None
        if e[0] in '<>' and not e.startswith('<<') and not e.startswith('>>'):
            part, e = e[0], e[1:].strip()
        def tok(m):
            t = m.group(0)
            if t.startswith('$'): return str(int(t[1:], 16))
            if t.startswith('%'): return str(int(t[1:], 2))
            if t.startswith("'"): return str(ord(t[1]))
            if t == '*': return str(pc)
            if re.fullmatch(r'\d+', t): return t
            if t in self.syms: return str(self.syms[t])
            if final: raise AsmError('undefined symbol ' + t)
            self.unresolved = True
            return '0'
        py = re.sub(r"\$[0-9A-Fa-f]+|%[01]+|'.'|[A-Za-z_][A-Za-z0-9_]*|\d+|(?<![\w)])\*(?![\w(])", tok, e)
        if not re.fullmatch(r"[0-9\s+\-*/&|^<>()=!]*", py): raise AsmError('bad expression ' + expr)
        v = int(eval(py.replace('/', '//')))
        if part == '<': v &= 0xFF
        elif part == '>': v = (v >> 8) & 0xFF
        return v

    def split_args(self, s):
        out, cur, q = [], '', False
        for ch in s:
            if ch == '"': q = not q
            if ch == ',' and not q: out.append(cur); cur = ''
            else: cur += ch
        out.append(cur)
        return [a.strip() for a in out]

    def operand_mode(self, mn, op):
        op = op.strip()
        if op == '' : return ('acc' if 'acc' in OPS[mn] else 'imp'), None
        if op.lower() == 'a' and 'acc' in OPS[mn]: return 'acc', None
        if op.startswith('#'): return 'imm', op[1:]
        if 'rel' in OPS[mn]: return 'rel', op
        m = re.fullmatch(r'\((.*),\s*[xX]\s*\)', op)
        if m: return 'indx', m.group(1)
        m = re.fullmatch(r'\((.*)\)\s*,\s*[yY]', op)
        if m: return 'indy', m.group(1)
        m = re.fullmatch(r'\((.*)\)', op)
        if m and mn == 'jmp': return 'ind', m.group(1)
        m = re.fullmatch(r'(.*),\s*[xX]', op)
        if m: return 'absx', m.group(1)
        m = re.fullmatch(r'(.*),\s*[yY]', op)
        if m: return 'absy', m.group(1)
        return 'abs', op

    def run(self):
        self.syms = {}; self.decisions = {}
        for passno in (1, 2):
            final = passno == 2
            self.out = {}; pc = 0; base = 0; rorg = None; out_pc = 0
            for ln, raw in enumerate(self.lines, 1):
                line = raw
                # strip comment (not inside quotes)
                q = False; cut = len(line)
                for i, ch in enumerate(line):
                    if ch == '"': q = not q
                    if ch == ';' and not q: cut = i; break
                line = line[:cut].rstrip()
                if not line.strip(): continue
                try:
                    m = re.match(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$', line)
                    if m:
                        self.unresolved = False
                        v = self.ev(m.group(2), pc, final)
                        self.syms[m.group(1)] = v
                        continue
                    m = re.match(r'^\s*([A-Za-z_][A-Za-z0-9_]*):(.*)$', line)
                    if m:
                        name = m.group(1)
                        if not final and name in self.syms and self.syms[name] != pc and name in self._defined:
                            raise AsmError('duplicate label ' + name)
                        self.syms[name] = pc
                        self._defined = getattr(self, '_defined', set()) | {name}
                        line = m.group(2)
                        if not line.strip(): continue
                    parts = line.strip().split(None, 1)
                    word = parts[0].lower(); arg = parts[1] if len(parts) > 1 else ''
                    def emit(b):
                        nonlocal pc, out_pc
                        for x in b:
                            if final:
                                if out_pc in self.out: raise AsmError('overlapping output at %04X' % out_pc)
                                self.out[out_pc] = x & 0xFF
                            pc += 1; out_pc += 1
                    if word == '.base':
                        base = self.ev(arg, pc, True); continue
                    if word == '.org':
                        pc = self.ev(arg, pc, True); out_pc = pc - base; continue
                    if word == '.rorg':
                        rorg = (pc, out_pc); pc = self.ev(arg, pc, True); continue
                    if word == '.rend':
                        pc = rorg[0] + (out_pc - rorg[1]); rorg = None; continue
                    if word == '.byte':
                        for a in self.split_args(arg):
                            if a.startswith('"'):
                                emit(a[1:-1].encode('ascii'))
                            else:
                                emit([self.ev(a, pc, final) if final else 0])
                        continue
                    if word == '.word':
                        for a in self.split_args(arg):
                            v = self.ev(a, pc, final) if final else 0
                            emit([v & 0xFF, v >> 8])
                        continue
                    if word == '.fill':
                        a = self.split_args(arg)
                        n = self.ev(a[0], pc, True); v = self.ev(a[1], pc, True) if len(a) > 1 else 0
                        emit([v] * n); continue
                    if word == '.assert':
                        if final:
                            a = self.split_args(arg)
                            if not self.ev(a[0], pc, True): raise AsmError('assert failed: ' + (a[1] if len(a) > 1 else a[0]))
                        continue
                    if word not in OPS: raise AsmError('unknown mnemonic ' + word)
                    mode, expr = self.operand_mode(word, arg)
                    key = (ln,)
                    if mode in ZP_OF:
                        if not final:
                            self.unresolved = False
                            v = self.ev(expr, pc, False)
                            use_zp = (not self.unresolved) and v < 256 and ZP_OF[mode] in OPS[word]
                            self.decisions[key] = use_zp
                        if self.decisions[key]: mode = ZP_OF[mode]
                    if mode not in OPS[word]:
                        raise AsmError('mode %s not valid for %s' % (mode, word))
                    opc = OPS[word][mode]; size = SIZE[mode]
                    if size == 1: emit([opc]); continue
                    v = self.ev(expr, pc, final) if final else 0
                    if mode == 'rel':
                        if final:
                            d = v - (pc + 2)
                            if not -128 <= d <= 127: raise AsmError('branch out of range (%d)' % d)
                            v = d & 0xFF
                        emit([opc, v]); continue
                    if size == 2:
                        if final and not 0 <= v <= 255: raise AsmError('operand too large: %s = %d' % (expr, v))
                        emit([opc, v]); continue
                    emit([opc, v & 0xFF, (v >> 8) & 0xFF])
                except AsmError as e:
                    raise AsmError('%s:%d: %s\n    %s' % (self.name, ln, e, raw))
        return self.out, self.syms

def assemble(src, name='<src>'):
    return Assembler(src, name).run()

if __name__ == '__main__':
    out, syms = assemble(open(sys.argv[1]).read(), sys.argv[1])
    print(len(out), 'bytes')
