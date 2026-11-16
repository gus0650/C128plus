# VIC-IIx graphics in BASIC 7.1

BASIC 7.1 (`boot2.rom`) adds commands for the VIC-IIx, the C128+'s graphics
chip:

| Command | Purpose |
|---|---|
| `SPRITE` | BASIC 7.0's `SPRITE`, for sprites 1–24 |
| `MOVSPR` | BASIC 7.0's `MOVSPR`, for sprites 1–24, including automatic movement |
| `RSPRITE()`, `RSPPOS()` | BASIC 7.0's functions, for sprites 1–24 |
| `BUMP()` | BASIC 7.0's collision function, with values 3–6 for sprites 9–24 |
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
- with PTRSEP on: in the sprite pointer page

It only supports RAM bank 0.

To design shapes for sprites 9–24, use BASIC's sprite tools on sprites 1–8,
then point the others at those blocks. Sprite 1 uses block 56, sprite 2
block 57, and so on:

```
SPRDEF                    : REM draw the shape as sprite 2 in the sprite editor
SPRPTR 10,57              : REM sprite 10 gets sprite 2's shape
```

### MOVSPR

```
MOVSPR n, x, y          absolute position
MOVSPR n, +x, -y        relative: move by x and y
MOVSPR n, d ; a         relative: move distance d at angle a
MOVSPR n, a # s         move automatically at angle a with speed s
```

Same as BASIC 7.0's `MOVSPR`, with **n = 1–24**. Coordinates are sprite
coordinates as in BASIC 7.0: X 0–511, Y 0–255, the visible area roughly
X 24–343 and Y 50–249. Angles are in degrees, 0 = up, 90 = right. Speed is
0–15; `MOVSPR n,0#0` stops the sprite.

```
MOVSPR 12,160,120       : REM sprite 12 to the middle of the screen
MOVSPR 12,+10,+0        : REM 10 pixels to the right
MOVSPR 20,45#3          : REM sprite 20 drifts up and to the right
```

Sprites 9–24 move exactly like sprites 1–8: BASIC 7.1 uses BASIC 7.0's own
code for the parsing and the maths (including `SCALE`) and moves them in
the same interrupt, at the same rate. A moving sprite only moves while it is
switched on.

Automatic movement doesn't know about the slot rule: sprites *n*, *n*+8 and
*n*+16 that drift into each other's rows will hide one another (see above).
Moving many sprites costs some CPU time in each interrupt, so BASIC runs a
little slower while lots of sprites are moving.

### RSPPOS

```
v = RSPPOS(n, a)
```

| `a` | Returns |
|---|---|
| 0 | X position (0–511) |
| 1 | Y position (0–255) |
| 2 | speed of the automatic movement (0–15) |

```
MOVSPR 9,RSPPOS(1,0),RSPPOS(1,1)+30   : REM sprite 9 30 pixels below sprite 1
```

### RSPRITE

```
v = RSPRITE(n, a)
```

| `a` | Returns |
|---|---|
| 0 | 1 if the sprite is on, 0 if off |
| 1 | colour (1–16) |
| 2 | 1 if behind the screen, 0 if in front |
| 3 | 1 if double width |
| 4 | 1 if double height |
| 5 | 1 if multicolour |

### Positions with POKE

`MOVSPR` is the easy way. For machine code or very fast BASIC loops, the
position registers of sprites 9–24 can also be written directly. With
*k* = *n*−9 for sprites 9–16, or *k* = *n*−17 for sprites 17–24:

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

This doesn't work for sprites 1–8: BASIC rewrites their position registers
from its own copy in every interrupt, so a `POKE` there doesn't stick. Use
`MOVSPR` for those.

### Collisions: BUMP and COLLISION

```
v = BUMP(t)
```

| `t` | Sprites | Collision with |
|---|---|---|
| 1 | 1–8 | another sprite |
| 2 | 1–8 | the screen (text or graphics) |
| 3 | 9–16 | another sprite |
| 4 | 9–16 | the screen |
| 5 | 17–24 | another sprite |
| 6 | 17–24 | the screen |

Each bit stands for one sprite of the group: bit 0 (value 1) for the first,
bit 7 (value 128) for the last. `BUMP(3)` = 6 means sprites 10 and 11 have
collided. The value collects every collision since the last call, and
reading it resets it. BUMP 1–2 work exactly as in BASIC 7.0.

BASIC's `COLLISION` command reacts to collisions of all 24 sprites: its
`GOSUB` runs whenever any sprite collides. Use `BUMP(1)`–`BUMP(6)` in the
subroutine to find out which ones:

```
10 COLLISION 1,100
...
100 A=BUMP(1):B=BUMP(3):C=BUMP(5)
110 PRINT "SPRITE-SPRITE:";A;B;C:RETURN
```

A sprite only reports a collision while it is actually displayed: if it is
skipped because it shares its slot with another sprite on the same line, it
doesn't collide either.

Don't `PEEK` `$D01E`/`$D01F` (53278/53279) yourself while using `BUMP`:
reading them clears the collision bits of all 24 sprites, and BASIC 7.1
then can't collect them.

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
- `MOVSPR`, `RSPRITE`, `RSPPOS` and `BUMP` typed with BASIC 7.1 are also
  stored as BASIC 7.1 keywords. For sprites 1–8 they behave exactly as in
  BASIC 7.0.
- `PALETTE`, `RPALETTE` and `SPRPTR` are new BASIC 7.1 keywords.
- Programs that use any of these need the C128+ with BASIC 7.1. On a normal
  C128, those lines stop with `?SYNTAX ERROR`.
- Programs loaded from disk keep BASIC 7.0's own sprite keywords and work as
  before, for sprites 1–8.
- `SID6 OFF` only affects the sound keywords, not the graphics commands.

## Still limited to sprites 1–8

| Command | For sprites 9–24 |
|---|---|
| `SPRDEF` | design the shape on sprites 1–8, then `SPRPTR` |
| `SPRSAV` | load the shape into sprites 1–8, then `SPRPTR` |

## Test programs

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

`basic71/test/sprtest.prg` (source: `sprtest.bas`, also on `sprtest.d64`)
tests sprite movement:

1. `MOVSPR`: 24 solid sprites in three rows
2. `RSPPOS(20,0)` and `RSPPOS(20,1)`: prints 130 180
3. relative `MOVSPR`: row 3 steps to the right
4. automatic movement: row 2 drifts right, row 3 left; `RSPPOS(9,2)` prints
   the speed, 2
5. `RSPRITE(9,1)`: prints sprite 9's colour, 9
6. `BUMP`: sprite 10 is moved onto sprite 11; `BUMP(3)` prints 6

```
DLOAD "SPRTEST"
RUN
```

If a program stops at line 30 with "VIC-IIX LOCKED", BASIC 7.1 isn't
installed or the VIC-IIx was locked.

## Tests

`basic71/test_graphics.py` boots the real Kernal and BASIC with BASIC 7.1
in a C128 simulator, types the commands and checks the VIC-IIx registers and
sprite pointers. It also checks the default pointers, the errors for out of
range values and a locked chip, `SPRPTR` with PTRSEP, every form of
`MOVSPR` for sprites 9–24 (including automatic movement and an error in the
middle of a `MOVSPR`), `RSPPOS`, `RSPRITE`, and `BUMP` 1–6 with simulated
collisions.

## How it works

- **Keywords:** BASIC 7.1 stores `MOVSPR` as `$FE $48`, and `RSPRITE`,
  `RSPPOS` and `BUMP` as `$CE $41`–`$CE $43`.
- **MOVSPR for sprites 9–24:** BASIC 7.1 doesn't have its own copy of
  `MOVSPR`'s maths. It puts the sprite's position and motion record into
  BASIC 7.0's slot for the sprite that shares its hardware slot (*n*−1
  AND 7), holds off BASIC's interrupt, lets BASIC 7.0's `MOVSPR` code do the
  rest, then takes the result out and puts the slot back. If `MOVSPR` stops
  with an error, a hook on BASIC's error vector undoes the swap first.
- **Automatic movement:** BASIC 7.1 keeps BASIC 7.0's 11-byte motion record
  for each of sprites 9–24 and moves them with the same algorithm, once per
  jiffy, from its hook on the Kernal's IRQ vector.
- **Collisions:** the same hook reads `$D056`/`$D057` and `$D096`/`$D097` at
  the start of every interrupt, before BASIC 7.0 reads `$D01E`/`$D01F`, which
  clears all 24 bits.
