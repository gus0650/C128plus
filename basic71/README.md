# C128+ BASIC 7.1

BASIC 7.1 extends the C128's BASIC 7.0 with commands for the VIC-IIx and for the second SID. It is an internal function ROM: the C128 Kernal finds it at power-up and starts it automatically. The ROM unlocks the VIC-IIx and prints `C128+ BASIC 7.1 - VIC-IIX EXTENSIONS` under the normal start-up message.

All code here was written for the C128+. No Commodore ROM code is included or modified.

## Installing

Copy `boot2.rom` to `/media/fat/games/C128plus/` on the MiSTer. The core loads it at start-up. You can also load it from the core's menu (Hardware → Internal Function ROM), which resets the machine.

## Status

BASIC 7.1 is being built in stages:

| Stage | Contents | Status |
|---|---|---|
| 1 | ROM detected at power-up, VIC-IIx unlocked, start-up line | done, tested on MiSTer |
| 2 | `PALETTE`, `RPALETTE()` | done, tested on MiSTer |
| 3 | `SPRITE`, `SPRPTR` for sprites 1–24 | done, tested on MiSTer |
| 4 | `MOVSPR` with automatic movement for all 24 sprites, `RSPRITE`, `RSPPOS`, `BUMP` | done, tested on MiSTer |
| 6 | six-voice sound: `SOUND`, `PLAY`, `VOL`, `FILTER` for voices 1–6, `SID6 ON/OFF` | done, tested on MiSTer |

## Commands so far

| Command | Function |
|---|---|
| `PALETTE c,hue,lum` | set palette entry c (0–15) to hue (0–15) and luminance (0–15) |
| `PALETTE ON` / `PALETTE OFF` | switch the programmable palette on or off |
| `PALETTE RESET` | restore the standard palette and switch it off |
| `RPALETTE(c)` | read palette entry c; returns hue × 16 + luminance |
| `SPRITE n [,e [,c [,p [,x [,y [,r]]]]]]` | as BASIC 7.0's `SPRITE`, for sprites 1–24: enable, colour 1–16, background priority, x/y expansion, multicolour |
| `SPRPTR n,block` | sprite n (1–24) shows the 64-byte shape in block 0–255 of the VIC's 16K bank |
| `MOVSPR n,...` | as BASIC 7.0's `MOVSPR` (absolute, relative, distance;angle, angle#speed), for sprites 1–24 |
| `RSPPOS(n,a)`, `RSPRITE(n,a)` | as BASIC 7.0's functions, for sprites 1–24 |
| `BUMP(t)` | 1/2 as BASIC 7.0 (sprites 1–8); 3/4 for sprites 9–16, 5/6 for 17–24 (sprite-sprite / sprite-screen) |

Sprites 9–16 and 17–24 start with the shapes of sprites 1–8 (blocks 56–63 at `$0E00`), so 9 and 17 look like 1 until you give them their own with `SPRPTR`. `SPRPTR` writes the pointer where the VIC-IIx reads it: after the screen, or in the pointer page when that is switched on. It only supports RAM bank 0.

`SPRITE` typed with BASIC 7.1 installed is stored as a BASIC 7.1 keyword, so it reaches all 24 sprites, including after `THEN` and in direct mode. Programs saved without BASIC 7.1 keep BASIC's own `SPRITE` and work as before (sprites 1–8).

While the VIC-IIx is locked, `PALETTE`, `RPALETTE`, `SPRPTR`, and `SPRITE` for sprites 9–24 give `?ILLEGAL QUANTITY ERROR`: their registers would otherwise be mirrors of the stock ones.

Hue 0 is grey; hues 1–15 go round the colour wheel (see `docs/VIC-IIx.md`).

The full description, with a test program (`test/gfxtest.prg`, also on `test/gfxtest.d64`), is in [docs/BASIC71-Graphics.md](../docs/BASIC71-Graphics.md).

## Six-voice sound (stage 6)

With BASIC 7.1, BASIC's sound commands play on both SIDs: voices 1–3 on the SID at `$D400`, voices 4–6 on the SID at `$D420`. This is the layout Commodore used for the C65. Leave the core's "Right SID Port" setting on D420, which is the default.

| Command | Function |
|---|---|
| `SOUND v,f,d [,dir [,min [,step [,wave [,pw]]]]]` | as BASIC 7.0's `SOUND`, for voices 1–6 |
| `PLAY "..."` | as BASIC 7.0's `PLAY`, with `V1`–`V6`. `U` (volume) and `X` (filter) act on the SID of the current voice; `M` waits for all six voices |
| `VOL a [,b]` | volume of SID 1 (`a`) and SID 2 (`b`), 0–15. `VOL a` sets both |
| `FILTER [f] [,lp] [,bp] [,hp] [,res]` | as BASIC 7.0's `FILTER`; cut-off, filter type and resonance apply to both SIDs. Each SID keeps its own voice routing (`PLAY "Xn"`) and volume |
| `SID6 ON` / `SID6 OFF` | whether BASIC 7.1 takes over `SOUND`, `PLAY`, `VOL` and `FILTER` in lines you type (default: on) |

`ENVELOPE` and `TEMPO` stay BASIC's own commands; their settings apply to all six voices. One `PLAY` string can play on both chips, for example `PLAY "V1O4HCV4O3HE"`.

Like `SPRITE`, the four sound keywords typed with BASIC 7.1 are stored as BASIC 7.1 keywords, and `LIST` shows them normally. Programs saved that way need the C128+ with BASIC 7.1. Programs loaded from disk keep BASIC's own keywords and run on BASIC's three-voice code as before. To write a program that must also run on a normal C128, type `SID6 OFF` first: from then on the four keywords stay BASIC 7.0's own.

The full description, with a test program (`test/sid6test.prg`, also on `test/sid6test.d64`), is in [docs/BASIC71-Sound.md](../docs/BASIC71-Sound.md).

Inside, BASIC 7.1 has its own sound engine for all six voices, with the same algorithms as BASIC 7.0. It hooks the Kernal's IRQ vector and advances once per jiffy clock tick, so notes on both chips stay in step at BASIC's tempo. RUN/STOP + RESTORE silences both SIDs and installs the hook again.

## How it works

- **Detection:** the ROM image is 32K. The code is in the upper 16K, which the C128 sees at `$C000` (internal function ROM high), with the usual `CBM` key at `$C007`.
- **New keywords:** BASIC 7.1 hooks BASIC 7.0's escape-token vectors for tokenizing (`$030C`), listing (`$030E`) and executing statements (`$0310`) and functions (`$02FC`). BASIC 7.1 statements are `$FE $40` and up, functions `$CE $40` and up, above BASIC's own escape tokens.
- **Running BASIC 7.1 code:** while BASIC 7.1 code runs, the MMU maps the BASIC 7.1 ROM at `$C000` with both BASIC ROMs and I/O visible (configuration `$10`). The Kernal is not visible then, and BASIC switches the memory map while it reads variables. So every call into BASIC or the Kernal goes through a small routine in RAM that calls it with the Kernal's `JSRFAR` in the normal BASIC map. `JSRFAR` returns through common RAM, so this also works for BASIC routines that return with RAM bank 1 switched in.
- **Interrupts:** the interrupt entry and exit code at `$FF05–$FF41` is byte-identical to the Kernal's, because the CPU continues in the other copy at the same address when the map changes.
- **RAM:** BASIC 7.1 uses `$1800–$1B7F` (879 bytes so far, of 896), part of the 1K that the C128 Kernal reserves for function ROM software. It also uses the Kernal's `JSRFAR` parameters at `$02–$08`, which BASIC itself only uses for `SYS`.

## Building and testing

Requires Python 3 only.

```
python3 build.py boot2.rom    # assemble basic71.asm into the 32K ROM image
python3 test_basic71.py            # run the tests on a simulated 6502
python3 test_sound.py boot0.rom    # six-voice sound, with the real Kernal and BASIC
python3 test_graphics.py boot0.rom # VIC-IIx commands, with the real Kernal and BASIC
```

`asm6502.py` is a small 6502 assembler written for this project. `test_basic71.py` runs BASIC 7.1 on a simulated 6502 with Python stand-ins for the BASIC routines, and checks that the memory map is correct whenever BASIC 7.1 or BASIC code runs. `test_sound.py` boots the real Kernal and BASIC from an original C128 `boot0.rom` together with BASIC 7.1 in the C128 simulator from `../basic70`, types commands and checks the writes to both SIDs.
