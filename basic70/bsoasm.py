#!/usr/bin/env python3
"""Small multi-pass assembler for the Commodore BSO-style 6502 sources in
mist64/cbmsrc (C128 BASIC).  Produces a flat image for a given address range.

usage: bsoasm.py SRCDIR main.src out.bin [start end]
"""
import re, sys, os

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

class Undef(Exception): pass

class Asm:
    def __init__(s, srcdir):
        s.dir = srcdir
        s.sym = {}
        s.errors = []
        s.forceabs = set()

    def read(s, name):
        for cand in (name, name + '.src', name.lower(), name.lower() + '.src'):
            p = os.path.join(s.dir, cand)
            if os.path.exists(p):
                return open(p, encoding='latin-1').read().replace('\r', '').split('\n')
        raise FileNotFoundError(name)

    # ---- expressions ----
    def tok(s, e):
        out = []; i = 0
        while i < len(e):
            c = e[i]
            if c in ' \t': i += 1; continue
            if c == "'":
                if i + 2 < len(e) + 1 and i + 1 < len(e):
                    out.append(('n', ord(e[i+1])))
                    i += 2
                    if i < len(e) and e[i] == "'": i += 1
                    continue
                out.append(('n', 32)); i += 1; continue
            if c == '$':
                m = re.match(r'\$[0-9a-fA-F]+', e[i:]); out.append(('n', int(m.group()[1:], 16))); i += len(m.group()); continue
            if c == '%':
                m = re.match(r'%[01]+', e[i:]); out.append(('n', int(m.group()[1:], 2))); i += len(m.group()); continue
            if c == '@':
                m = re.match(r'@[0-7]+', e[i:]); out.append(('n', int(m.group()[1:], 8))); i += len(m.group()); continue
            if c.isdigit():
                m = re.match(r'\d+\$', e[i:])
                if m:
                    out.append(('s', s.local(m.group()))); i += len(m.group()); continue
                m = re.match(r'\d+', e[i:]); out.append(('n', int(m.group()))); i += len(m.group()); continue
            if c.isalpha() or c in '_.':
                m = re.match(r'[A-Za-z_.][A-Za-z0-9_.$]*', e[i:]); out.append(('s', m.group().lower())); i += len(m.group()); continue
            if c == '*':
                # location counter if at operand position
                if not out or out[-1][0] == 'o' and out[-1][1] not in ')]':
                    out.append(('n', s.pc)); i += 1; continue
            out.append(('o', c)); i += 1
        return out

    def local(s, name):
        return s.scope + ':' + name

    def ev(s, e):
        t = s.tok(e); s._t = t; s._i = 0
        v = s.expr()
        if s._i != len(t): raise SyntaxError('junk in ' + e)
        return v

    def peek(s):
        return s._t[s._i] if s._i < len(s._t) else None

    def expr(s):
        v = s.term()
        while True:
            p = s.peek()
            if p and p[0] == 'o' and p[1] in '+-&!^':
                s._i += 1; r = s.term(); op = p[1]
                if op == '+': v = v + r
                elif op == '-': v = v - r
                elif op == '&': v = v & r
                elif op == '!': v = v | r
                elif op == '^': v = v ^ r
            else:
                return v

    def term(s):
        v = s.unary()
        while True:
            p = s.peek()
            if p and p[0] == 'o' and p[1] in '*/':
                s._i += 1; r = s.unary()
                v = v * r if p[1] == '*' else v // r
            else:
                return v

    def unary(s):
        p = s.peek()
        if p is None: raise SyntaxError('empty')
        s._i += 1
        if p[0] == 'n': return p[1]
        if p[0] == 's':
            if p[1] in s.sym: return s.sym[p[1]]
            raise Undef(p[1])
        if p[1] == '-': return -s.unary()
        if p[1] == '<': return s.expr_inner() & 0xff
        if p[1] == '>': return (s.expr_inner() >> 8) & 0xff
        if p[1] in '([':
            v = s.expr(); s._i += 1; return v
        raise SyntaxError('bad ' + str(p))

    def expr_inner(s):
        return s.expr()

    def ev_soft(s, e):
        try:
            return s.ev(e), True
        except Undef:
            return 0, False

    # ---- passes ----
    def run(s, main, passes=3):
        s.last = passes - 1
        for s.pas in range(passes):
            s.mem = {}; s.pc = 0; s.scope = ''; s.undef = set(); s.msgs = []
            s.changed = False; s.listing = []; s.linepc = {}
            s.file(main)
        return s

    def file(s, name):
        for ln, line in enumerate(s.read(name)):
            s.where = '%s:%d' % (name, ln + 1)
            pc0 = s.pc
            if s.pas == s.last: s.linepc[s.where] = pc0
            try:
                s.line(line)
                if s.pas == s.last and s.pc != pc0: s.listing.append((pc0, s.pc, s.where, line))
            except (SyntaxError, KeyError, AttributeError, ValueError, ZeroDivisionError) as ex:
                if s.pas == s.last: s.errors.append('%s: %s: %r' % (s.where, ex, line))

    def strip_comment(s, line):
        out = ''; q = False; i = 0
        while i < len(line):
            c = line[i]
            if c == "'" and not q:
                # char constant, possibly 'x or 'x'
                out += line[i:i+2]
                if i + 2 < len(line) and line[i+2] == "'":
                    out += "'"; i += 3
                else:
                    i += 2
                continue
            if c == '"': q = not q
            if c == ';' and not q: break
            out += c; i += 1
        return out

    def setsym(s, name, val):
        if name[0].isdigit(): name = s.local(name)
        old = s.sym.get(name)
        if old != val: s.changed = True
        s.sym[name] = val

    def line(s, line):
        line = s.strip_comment(line).rstrip()
        if not line.strip(): return
        m = re.match(r'^\s*([A-Za-z_][A-Za-z0-9_.$]*)\s*(?==)', line) or re.match(r'^([A-Za-z_][A-Za-z0-9_.$]*|\d+\$):?(?=\s|$|=)', line)
        label = None
        rest = line
        if m and (not line[0].isspace() or line[m.end(1):].lstrip().startswith('=')):
            label = m.group(1).lower(); rest = line[m.end():]
        rest = rest.strip()
        # equate
        if label and rest.startswith('=') or (label and re.match(r'(?i)\.equ\b', rest)):
            e = rest[1:] if rest.startswith('=') else rest[4:]
            e = e.strip()
            if e.startswith('*=*+') or e.startswith('*+'):
                pass
            v, ok = s.ev_soft(e)
            if ok: s.setsym(label, v)
            return
        if label and rest.startswith('*='):
            s.setsym(label, s.pc); label = None
        if label:
            if not label[0].isdigit():
                s.scope = label
            s.setsym(label, s.pc)
        if not rest: return
        if rest.startswith('*='):
            v, ok = s.ev_soft(rest[2:])
            if not ok: raise SyntaxError('undef org')
            s.pc = v; return
        if rest.startswith('='):
            return
        m = re.match(r'(\.?[A-Za-z]+)\s*(.*)$', rest)
        op = m.group(1).lower(); arg = s.cut(m.group(2).strip(), op)
        if op.startswith('.'):
            return s.directive(op, arg)
        if op not in OPS: raise SyntaxError('unknown op ' + op)
        return s.instr(op, arg)

    def cut(s, arg, op):
        if op in ('.include','.subttl','.nam','.messg','.page'): return arg
        out = ''; i = 0
        while i < len(arg):
            c = arg[i]
            if c == "'":
                if op in ('.byte','.byt'):
                    j = i + 1
                    while True:
                        k = arg.find("'", j)
                        if k < 0: k = len(arg) - 1; break
                        if k + 1 < len(arg) and arg[k+1] == "'": j = k + 2; continue
                        break
                    out += arg[i:k+1]; i = k + 1; continue
                out += arg[i:i+2]; i += 2
                if i < len(arg) and arg[i] == "'": out += "'"; i += 1
                continue
            if c == '"':
                k = arg.find('"', i + 1)
                if k < 0: k = len(arg) - 1
                out += arg[i:k+1]; i = k + 1; continue
            if c in ' \t':
                if out.rstrip().endswith(','): i += 1; continue
                break
            out += c; i += 1
        return out

    def emit(s, b):
        s.mem[s.pc & 0xffff] = b & 0xff; s.pc += 1

    def split_args(s, arg):
        parts = []; cur = ''; q = False; i = 0
        while i < len(arg):
            c = arg[i]
            if c == '"': q = not q
            if c == "'" and not q:
                j = i + 1
                while True:
                    k = arg.find("'", j)
                    if k < 0: k = i + 1; break
                    if k + 1 < len(arg) and arg[k+1] == "'": j = k + 2; continue
                    break
                cur += arg[i:k+1]; i = k + 1
                continue
            if c == ',' and not q:
                parts.append(cur.strip()); cur = ''; i += 1; continue
            cur += c; i += 1
        if cur.strip(): parts.append(cur.strip())
        return parts

    def directive(s, op, arg):
        if op == '.include':
            name = arg.split()[0]; sc = s.scope
            s.file(name); return
        if op in ('.byte', '.byt'):
            for p in s.split_args(arg):
                m = re.match(r"^'((?:[^']|'')*)'$", p)
                if p.startswith('"') or (m and len(m.group(1)) >= 2):
                    st = p[1:-1].replace("''", "'")
                    for ch in st: s.emit(ord(ch))
                else:
                    v, ok = s.ev_soft(p); s.emit(v)
            return
        if op in ('.word', '.wor'):
            for p in s.split_args(arg):
                v, ok = s.ev_soft(p); s.emit(v); s.emit(v >> 8)
            return
        if op == '.dbyte':
            for p in s.split_args(arg):
                v, ok = s.ev_soft(p); s.emit(v >> 8); s.emit(v)
            return
        if op == '.ifge':
            v, ok = s.ev_soft(arg)
            if ok and v >= 0 and s.pas == s.last: s.msgs.append('ADDRESS CHECK at ' + s.where)
            return
        return  # .page .subttl .nam .formln .messg .endif .end

    def instr(s, op, arg):
        modes = OPS[op]
        if not arg or arg.lower() == 'a':
            if 'acc' in modes and arg.lower() == 'a' or ('acc' in modes and not arg):
                return s.emit(modes['acc'])
            return s.emit(modes['imp'])
        if 'rel' in modes:
            v, ok = s.ev_soft(arg)
            d = v - (s.pc + 2) if ok else 0
            if ok and not -128 <= d <= 127 and s.pas == s.last: raise ValueError('branch range')
            s.emit(modes['rel']); s.emit(d); return
        if arg.startswith('#'):
            v, ok = s.ev_soft(arg[1:]); s.emit(modes['imm']); s.emit(v); return
        a = arg.lower().replace(' ', '')
        if a.startswith('(') and a.endswith(',x)'):
            v, ok = s.ev_soft(arg.strip()[1:-3]); s.emit(modes['indx']); s.emit(v); return
        if a.startswith('(') and a.endswith('),y'):
            v, ok = s.ev_soft(arg.strip()[1:arg.strip().lower().rfind(')')]); s.emit(modes['indy']); s.emit(v); return
        if op == 'jmp' and a.startswith('(') and a.endswith(')'):
            v, ok = s.ev_soft(arg.strip()[1:-1]); s.emit(modes['ind']); s.emit(v); s.emit(v >> 8); return
        idx = ''
        if a.endswith(',x'): idx = 'x'; e = arg.strip()[:-2]
        elif a.endswith(',y'): idx = 'y'; e = arg.strip()[:-2]
        else: e = arg
        v, ok = s.ev_soft(e)
        key = (s.where, s.pc)
        if s.pas == 0 and not ok: s.forceabs.add(s.where)
        zp = ok and 0 <= v < 256 and s.where not in s.forceabs
        # keep size decision stable once made in a previous pass
        zpm = 'zp' + idx; absm = 'abs' + idx
        if zp and zpm in modes:
            s.emit(modes[zpm]); s.emit(v)
        else:
            s.emit(modes[absm]); s.emit(v); s.emit(v >> 8)


if __name__ == '__main__':
    srcdir, main, out = sys.argv[1:4]
    lo = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0x4000
    hi = int(sys.argv[5], 16) if len(sys.argv) > 5 else 0xc000
    a = Asm(srcdir).run(main, passes=4)
    img = bytes(a.mem.get(x, 0xff) for x in range(lo, hi))
    open(out, 'wb').write(img)
    for e in a.errors[:40]: print('ERR', e)
    print(len(a.errors), 'errors;', ' '.join(a.msgs))
    import json
    with open(out + '.lst', 'w') as f:
        for a0, a1, w, l in a.listing:
            f.write('%04x %-12s %-20s %s\n' % (a0, ' '.join('%02x' % a.mem.get(x & 0xffff, 0) for x in range(a0, min(a1, a0 + 4))), w, l.strip()))
    json.dump({k: v for k, v in a.sym.items() if ':' not in k}, open(out + '.sym.json', 'w'))
