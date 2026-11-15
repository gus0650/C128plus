#!/usr/bin/env python3
"""Build the C128+ six-voice BASIC 7.0 and put it into a boot0.rom.

usage: make_rom.py CBMSRC_DIR boot0.rom out_boot0.rom

CBMSRC_DIR is a checkout of https://github.com/mist64/cbmsrc (Commodore's
original sources). The script

  1. assembles the unchanged BASIC_C128_04 source and checks that it is
     byte-identical to the BASIC in boot0.rom,
  2. applies the six-voice changes (see EDITS below) plus sid6.src,
  3. checks that every original BASIC label keeps its address,
  4. writes boot0.rom with the new BASIC lo/hi ROMs ($4000-$BFFF).

Bytes the source does not produce (machine language monitor, copyright
string, patch data) are taken from the input ROM unchanged.
"""
import os, re, shutil, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bsoasm import Asm

HERE = os.path.dirname(os.path.abspath(__file__))
BASIC_OFS = 0x8000          # BASIC lo+hi ($4000-$BFFF) inside boot0.rom
LO, HI = 0x4000, 0xC000
NEW_CODE = 0xBB72           # free space after the monitor
NEW_END = 0xBFC0            # copyright string starts here


def assemble(srcdir):
    a = Asm(srcdir).run('basic.src', passes=4)
    if a.errors:
        raise SystemExit('assembly errors:\n' + '\n'.join(a.errors[:20]))
    if a.msgs:
        raise SystemExit('address checks failed: ' + ', '.join(a.msgs))
    return a


def merge(a, base):
    img = bytearray(base)
    for addr in range(LO, HI):
        if addr in a.mem:
            img[addr - LO] = a.mem[addr]
    return bytes(img)


# ---------------------------------------------------------------- edits

def lines_of(d, f):
    return open(os.path.join(d, f + '.src'), encoding='latin-1').read().replace('\r', '').split('\n')


def put(d, f, lines):
    open(os.path.join(d, f + '.src'), 'w', encoding='latin-1').write('\n'.join(lines))


def find(lines, pat, start=0):
    for i in range(start, len(lines)):
        if re.search(pat, lines[i]):
            return i
    raise SystemExit('pattern not found: ' + pat)


def replace_range(d, f, orig, first_pat, next_pat, new):
    """Replace lines [first, next) of file f with `new`, then set the
    location counter to where line `next` was, so everything after keeps
    its address. The old bytes stay in the ROM (dead code)."""
    L = lines_of(d, f)
    i = find(L, first_pat)
    j = find(L, next_pat, i + 1) if next_pat else len(L)
    O = lines_of(orig.dir, f)                    # unmodified source
    oi = find(O, first_pat)
    oj = find(O, next_pat, oi + 1) if next_pat else len(O) - 1
    end = orig.linepc['%s:%d' % (f, oj + 1)]
    L[i:j] = new + ['\t*=$%04x\t\t;C128+: keep the following addresses' % end,
                    '\t.ifge *-$%04x' % (end + 1), '\t.messg "*** C128+ PATCH TOO LONG ***"', '\t.endif']
    put(d, f, L)


def rename(d, f, names, suffix_map):
    L = lines_of(d, f)
    out = []
    for l in L:
        code, sep, com = l.partition(';')
        for n in names:
            code = re.sub(r'\b%s(?=[+,])' % re.escape(n), suffix_map(n), code)
        out.append(code + sep + com)
    put(d, f, out)


def subst(d, f, pat, repl, count=1, start_pat=None):
    L = lines_of(d, f)
    i0 = find(L, start_pat) if start_pat else 0
    n = 0
    for i in range(i0, len(L)):
        if re.search(pat, L[i]):
            L[i] = re.sub(pat, repl, L[i]); n += 1
            if n == count: break
    if n != count: raise SystemExit('subst failed: %s %s' % (f, pat))
    put(d, f, L)


SOUND_TABS = ['sound_time_lo', 'sound_time_hi', 'sound_max_lo', 'sound_max_hi',
              'sound_min_lo', 'sound_min_hi', 'sound_direction', 'sound_step_lo',
              'sound_step_hi', 'sound_freq_lo', 'sound_freq_hi']
REN = {'voices': 'voices6', 'wave0': 'wave06', 'offtab': 'offtab6', 'times2': 'times26',
       'filters': 'fil6'}
REN.update({n: n + '6' for n in SOUND_TABS})


def apply_edits(d, orig):
    # --- SOUND: whole command moves to sound6
    replace_range(d, 'sound', orig, r'^sound\s', None, ['sound\tjmp sound6'])
    # --- VOL: whole command moves to volume6
    replace_range(d, 'volume', orig, r'^volume\s', None, ['volume\tjmp volume6'])
    # --- FILTER: read SID 1 settings from fil6, end goes to filter_end6
    rename(d, 'filter', ['filters'], REN.get)
    replace_range(d, 'filter', orig, r'^70\$\s', r'^90\$', ['70$\tjmp filter_end6'])
    # --- init_voices: both SIDs
    replace_range(d, 'init', orig, r'^init_voices', r'^init_mmu', ['init_voices', '\tjmp init_voices6', ''])
    # --- PLAY
    replace_range(d, 'play', orig, r'^set_filter', r'^set_voice', ['set_filter', '\tjmp set_filter6', ''])
    replace_range(d, 'play', orig, r'^set_volume', r'^clear_flag', ['set_volume', '\tjmp set_volume6', ''])
    subst(d, 'play', r'cpx #3\b', 'cpx #6', start_pat=r'^set_voice')          # V1..V6
    subst(d, 'play', r'ldy #5\b', 'ldy #11', start_pat=r'^play_command')      # M waits for 6 voices
    rename(d, 'play', ['voices', 'wave0', 'offtab', 'times2'], REN.get)
    # --- BASIC IRQ: 6 PLAY counters, 6 SOUND voices
    rename(d, 'irq', ['voices', 'wave0', 'offtab'] + SOUND_TABS, REN.get)
    subst(d, 'irq', r'cpx #6\b', 'cpx #12', start_pat=r'^music_irq')
    subst(d, 'irq', r'ldy #2\b', 'ldy #5', start_pat=r'^sound_irq')
    # --- new code after the monitor
    shutil.copy(os.path.join(HERE, 'sid6.src'), os.path.join(d, 'sid6.src'))
    L = lines_of(d, 'basic')
    i = find(L, r'^\s*\.end\b') - 1
    L[i + 1:i + 1] = ['\t*=$%04x' % NEW_CODE, '\t.include sid6',
                      '\t.ifge *-$%04x' % NEW_END, '\t.messg "*** C128+ CODE TOO LONG ***"', '\t.endif']
    put(d, 'basic', L)


def main():
    cbmsrc, rom_in, rom_out = sys.argv[1:4]
    src = os.path.join(cbmsrc, 'BASIC_C128_04')
    rom = open(rom_in, 'rb').read()
    base = rom[BASIC_OFS:BASIC_OFS + 0x8000]

    tmp = tempfile.mkdtemp(prefix='basic70_')
    d = os.path.join(tmp, 'src')
    shutil.copytree(src, d)

    orig = assemble(src)
    img0 = merge(orig, base)
    if img0 != base:
        diff = [hex(LO + i) for i in range(len(base)) if img0[i] != base[i]]
        raise SystemExit('input ROM is not the C128 BASIC 318018/19-04: %d bytes differ (%s ...)'
                         % (len(diff), ', '.join(diff[:8])))
    print('original BASIC reassembled byte-identical')

    apply_edits(d, orig)
    new = assemble(d)

    moved = [k for k, v in orig.sym.items() if ':' not in k and new.sym.get(k) != v]
    if moved:
        raise SystemExit('labels moved: ' + ', '.join(sorted(moved)[:30]))
    print('all %d original labels keep their address' % len([k for k in orig.sym if ':' not in k]))
    print('new code $%04x-$%04x (%d bytes, %d free)' % (NEW_CODE, new.sym['sid6_end'] - 1,
          new.sym['sid6_end'] - NEW_CODE, NEW_END - new.sym['sid6_end']))

    img = merge(new, base)
    out = bytearray(rom)
    out[BASIC_OFS:BASIC_OFS + 0x8000] = img
    open(rom_out, 'wb').write(out)
    # list changed ranges
    diff = [LO + i for i in range(len(base)) if img[i] != base[i]]
    rs = []
    for x in diff:
        if rs and x <= rs[-1][1] + 4: rs[-1][1] = x
        else: rs.append([x, x])
    print('changed:', ', '.join('$%04x-$%04x' % (a, b) for a, b in rs))
    shutil.rmtree(tmp)


if __name__ == '__main__':
    main()
