# VIC-IIx graphics in BASIC 7.1

BASIC 7.1 (`boot2.rom`) adds commands for the VIC-IIx, the C128+'s graphics
chip:

| Command | Purpose |
|---|---|
| `SPRITE` | BASIC 7.0's `SPRITE`, for sprites 1–24 |
| `SPRPTR` | choose the shape of any of the 24 sprites |
| `PALETTE` | program the 256-colour palette, switch it on and off |
| `RPALETTE()` | read a palette entry |

For the registers behind them, see [VIC-IIx.md](VIC-IIx.md).

## Setting up

Copy `boot2.rom` from `basic71/` to `/media/fat/games/C128plus/` and start
the core. The start-up screen shows `C128+ BASIC 7.1 - VIC-IIX EXTENSIONS`.

BASIC 7.1 unlocks the VIC-IIx at start-up, so the commands work straight
away. `PEEK(53311)` returns 254 while the chip is unlocked. If a program
locks it again by writing to `$D03F`, unlock it with:

```
BANK 15:POKE 53311,165:POKE 53311,150
```

While the chip is locked, `PALETTE`, `RPALETTE`, `SPRPTR` and `SPRITE` for
sprites 9–24 stop with `?ILLEGAL QUANTITY ERROR`. Their registers would
otherwise be mirrors of the stock ones. `SPRITE` 1–8 keeps working.

## Sprites 1–24

BASIC numbers sprites from 1, the hardware from 0: BASIC's sprite *n* is
hardware sprite *n*−1.

| BASIC sprites | Hardware sprites | Registers |
|---|---|---|
| 1–8 | 0–7 | stock, `$D000–$D02E` |
| 9–16 | 8–15 | `$D040–$D05F` |
| 17–24 | 16–23 | `$D080–$D09F` |

Up to 8 sprites can appear on one raster line and 24 on the screen. Sprites
*n*, *n*+8 and *n*+16 share a hardware slot: for example 1, 9 and 17. They
must sit one above the other without overlapping, with at least one free
line in between. A sprite that overlaps the one using its slot is skipped
for that frame. [VIC-IIx.md](VIC-IIx.md#sprites-823) has the details.

### SPRITE

```
SPRITE n [, e [, c [, p [, x [, y [, m]]]]]]
```

Same as BASIC 7.0's `SPRITE`, with **n = 1–24**. Leave out a parameter to
keep its current setting, e.g. `SPRITE 12,,,,1,1`.

| Parameter | Range | Meaning |
|---|---|---|
| `n` | 1–24 | sprite |
| `e` | 0/1 | off / on |
| `c` | 1–16 | colour (BASIC colour numbers, as in `COLOR`) |
| `p` | 0/1 | 0: sprite in front of the screen, 1: behind it |
| `x` | 0/1 | double width |
| `y` | 0/1 | double height |
| `m` | 0/1 | 0: hi-res, 1: multicolour |

Multicolour sprites use the two shared colours set with BASIC's `SPRCOLOR`,
for all 24 sprites.

### SPRPTR

```
SPRPTR n, block
```

Sprite *n* (1–24) shows the 64-byte shape in **block** 0–255. Block *b*
starts at address *b* × 64 in the VIC's 16K bank. In the normal setup that
is RAM bank 0, `$0000–$3FFF`.

| Block | Address | Use |
|---|---|---|
| 56–63 | `$0E00–$0FFF` | BASIC's sprite area: `SPRDEF` and `SPRSAV` shapes of sprites 1–8 |
| 112–255 | `$1C00–$3FFF` | the hi-res graphics area: reserved by `GRAPHIC 1:GRAPHIC 0` (BASIC moves the program to `$4000`), usable as long as no hi-res graphics are drawn |

At start-up, sprites 9–16 and 17–24 point at blocks 56–63 like sprites 1–8.
So sprites 1, 9 and 17 share one shape until you change it.

`SPRPTR` writes the pointer where the VIC-IIx reads it:

- normally: after the 1000 bytes of the text screen
- in WIDE mode: at the end of the 2K screen map
- with PTRSEP on: in the sprite pointer page

It only supports RAM bank 0.

To design shapes for sprites 9–24, use BASIC's sprite tools on sprites 1–8,
then point the others at those blocks. Sprite 1 uses block 56, sprite 2
block 57, and so on:

```
SPRDEF                    : REM draw the shape as sprite 2 in the sprite editor
SPRPTR 10,57              : REM sprite 10 gets sprite 2's shape
```

### Positions

`MOVSPR` only handles sprites 1–8 for now. For sprites 9–24, `POKE` the
position registers. With *k* = *n*−9 for sprites 9–16, or *k* = *n*−17 for
sprites 17–24:

| | Sprites 9–16 | Sprites 17–24 |
|---|---|---|
| X (low 8 bits) | `53312+2*k` | `53376+2*k` |
| Y | `53313+2*k` | `53377+2*k` |
| X bit 8 (X > 255) | bit *k* of `53328` | bit *k* of `53392` |

```
BANK 15
POKE 53312,100:POKE 53313,150          : REM sprite 9 to X=100, Y=150
POKE 53328,PEEK(53328) OR 1            : REM sprite 9: X + 256
```

Use `MOVSPR` for sprites 1–8. BASIC rewrites their position registers from
its own copy in every interrupt, so a `POKE` there doesn't stick.

## Palette

The palette gives every one of the 16 colours a new hue and luminance out of
256 combinations. It applies to everything on screen: text, background,
border and sprites.

### PALETTE

```
PALETTE c, hue, lum
PALETTE ON
PALETTE OFF
PALETTE RESET
```

| Form | Effect |
|---|---|
| `PALETTE c,hue,lum` | set colour index `c` (0–15) to `hue` (0–15) and `lum` (0–15) |
| `PALETTE ON` | show the programmed palette |
| `PALETTE OFF` | back to the stock colours; the programmed values stay |
| `PALETTE RESET` | stock values in all 16 entries, palette off |

**Colour index vs. BASIC colour number:** `PALETTE` uses the hardware colour
index 0–15. `COLOR` and `SPRITE` use colour numbers 1–16. So `PALETTE c`
changes BASIC colour *c*+1. `PALETTE 1,...` changes white, colour 2.

**Hue:** 0 is grey. Hues 1–15 go round the colour wheel in 24° steps: 1 red,
2 orange, 3 ochre, 4 olive, 5–7 green, 8 teal, 9 sky blue, 10–11 blue,
12–13 purple, 14 magenta, 15 pink.

**Luminance:** 0 (black) to 15 (full brightness).

At start-up and after `PALETTE RESET`, the entries hold the closest match to
the stock colours:

| Index | BASIC colour | Stock colour | Hue | Lum |
|---|---|---|---|---|
| 0 | 1 | black | 0 | 0 |
| 1 | 2 | white | 0 | 15 |
| 2 | 3 | red | 1 | 4 |
| 3 | 4 | cyan | 8 | 11 |
| 4 | 5 | purple | 14 | 6 |
| 5 | 6 | green | 7 | 8 |
| 6 | 7 | blue | 11 | 3 |
| 7 | 8 | yellow | 4 | 13 |
| 8 | 9 | orange | 2 | 6 |
| 9 | 10 | brown | 3 | 3 |
| 10 | 11 | light red | 1 | 8 |
| 11 | 12 | dark grey | 0 | 4 |
| 12 | 13 | grey | 0 | 7 |
| 13 | 14 | light green | 6 | 13 |
| 14 | 15 | light blue | 11 | 8 |
| 15 | 16 | light grey | 0 | 10 |

With `PALETTE OFF`, the stock colours come from the palette chosen in the
MiSTer menu.

### RPALETTE

```
v = RPALETTE(c)
```

Returns entry *c* (0–15) as hue × 16 + luminance:

```
V=RPALETTE(5):PRINT "HUE";INT(V/16);"LUM";V AND 15
```

### Example: colour cycling

```
10 PALETTE ON
20 FOR H=1 TO 15:PALETTE 13,H,13:FOR D=1 TO 100:NEXT D,H
30 PALETTE RESET
```

Entry 13 is light green, BASIC colour 14: the default C128 border and text
colour. Line 20 takes it once round the colour wheel.

## Compatibility

- `SPRITE` typed with BASIC 7.1 installed is stored as a BASIC 7.1 keyword.
  It reaches all 24 sprites, also after `THEN` and in direct mode. `LIST`
  shows it normally.
- `PALETTE`, `RPALETTE` and `SPRPTR` are new BASIC 7.1 keywords.
- Programs that use any of these need the C128+ with BASIC 7.1. On a normal
  C128, those lines stop with `?SYNTAX ERROR`.
- Programs loaded from disk keep BASIC 7.0's own `SPRITE` and work as before,
  for sprites 1–8.
- `SID6 OFF` only affects the sound keywords, not the graphics commands.

## Still limited to sprites 1–8

These BASIC 7.0 commands don't know about sprites 9–24 yet:

| Command | For sprites 9–24 |
|---|---|
| `MOVSPR` | `POKE` the position registers (see above) |
| `SPRDEF`, `SPRSAV` | design or load the shape on sprites 1–8, then `SPRPTR` |
| `COLLISION`, `BUMP()` | `PEEK` the collision registers 53334/53335 (`$D056`/`$D057`) and 53398/53399 (`$D096`/`$D097`), before `BUMP` or `$D01E`/`$D01F`: reading those clears all 24 bits |
| `RSPRITE()`, `RSPPOS()` | `PEEK` the registers |

Stage 4 of BASIC 7.1 is planned to bring `MOVSPR`, `RSPRITE`, `RSPPOS` and
`BUMP` to all 24 sprites.

## Test program

`basic71/test/gfxtest.prg` (source: `gfxtest.bas`, also on `gfxtest.d64`)
goes through the commands step by step:

1. sprites 1–24 in three rows, in 16 colours
2. `SPRPTR`: row 2 changes to a checked shape, row 3 to a half-filled one
3. sprite 12 double size, sprite 20 multicolour, then back
4. `PALETTE`: white (sprites 2 and 18) goes through all 16 hues
5. `RPALETTE(5)` after `PALETTE 5,9,12`: prints 156
6. `PALETTE RESET`: stock colours

```
DLOAD "GFXTEST"
RUN
```

If it stops at line 30 with "VIC-IIX LOCKED", BASIC 7.1 isn't installed or
the VIC-IIx was locked.

## Tests

`basic71/test_graphics.py` boots the real Kernal and BASIC with BASIC 7.1
in a C128 simulator, types the commands and checks the VIC-IIx registers and
sprite pointers. It also checks the default pointers, the errors for out of
range values and a locked chip, and `SPRPTR` with PTRSEP.
