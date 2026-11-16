# VIC-IIx

The VIC-IIx is the C128+'s graphics chip, an improved VIC-IIe. It adds some nice features: 24 hardware-multiplexed sprites, a programmable 256-colour palette and hardware coarse scrolling. None of them uses any extra memory cycles, so CPU speed and timing are the same as on a stock C128.

## Unlocking

Until a program unlocks the extensions, the chip behaves exactly like a stock VIC-IIe. All existing software runs unchanged.

To unlock:

Write `$A5` and then `$96` to `$D03F`. Any other value written to `$D03F` locks the chip again.

Reading `$D03F` returns `$FF` while locked and `$FE` while unlocked. On a stock VIC-IIe the register always reads `$FF`, so this also tells a program whether it is running on a VIC-IIx.

Once unlocked, `$D040–$D07F` and `$D080–$D0BF` are extension register banks, and `$D0C0–$D0FF` is unused. While locked, these ranges mirror `$D000–$D03F` as on stock hardware. The extensions can only be unlocked in C128 mode or C64 mode, not in "Pure C64" mode.

## Register map (unlocked)

| Address | Function |
|---|---|
| `$D040–$D04F` | Sprite 8–15 X/Y position (same layout as `$D000–$D00F`) |
| `$D050` | Sprite 8–15 X position bit 8 |
| `$D051` | Sprite 8–15 enable |
| `$D052` | Sprite 8–15 Y expand |
| `$D053` | Sprite 8–15 background priority |
| `$D054` | Sprite 8–15 multicolour |
| `$D055` | Sprite 8–15 X expand |
| `$D056` | Sprite 8–15 sprite–sprite collisions (read only) |
| `$D057` | Sprite 8–15 sprite–background collisions (read only) |
| `$D058–$D05F` | Sprite 8–15 colour |
| `$D060–$D06F` | Palette entry 0–15: hue in bits 7–4, luminance in bits 3–0 |
| `$D070` | Bit 0 = PALEN: 1 = use the programmable palette |
| `$D071` | Screen start offset, bits 7–0. Writing it also applies the bits held in `$D072` (applied at the next frame) |
| `$D072` | Screen start offset, bits 9–8. Held until `$D071` is written |
| `$D073` | Row length in characters; values below 40 mean 40 (applied at the next frame) |
| `$D074` | Bit 1 = PTRSEP: sprite pointers in their own page. Bit 0 is unused and reads 1 |
| `$D075` | PTRPAGE: page for the sprite pointers, VIC address bits 13–8 (bits 5–0) |
| `$D076–$D07F` | Unused, read `$FF` |
| `$D080–$D08F` | Sprite 16–23 X/Y position |
| `$D090` | Sprite 16–23 X position bit 8 |
| `$D091` | Sprite 16–23 enable |
| `$D092` | Sprite 16–23 Y expand |
| `$D093` | Sprite 16–23 background priority |
| `$D094` | Sprite 16–23 multicolour |
| `$D095` | Sprite 16–23 X expand |
| `$D096` | Sprite 16–23 sprite–sprite collisions (read only) |
| `$D097` | Sprite 16–23 sprite–background collisions (read only) |
| `$D098–$D09F` | Sprite 16–23 colour |
| `$D0A0–$D0FF` | Unused, read `$FF` |

## Sprites 8–23

The chip still has 8 hardware sprite slots. Each slot is shared by three sprites: slot *n* serves sprites *n*, *n*+8 and *n*+16. For example, slot 0 serves sprites 0, 8 and 16, and slot 7 serves sprites 7, 15 and 23. A slot is assigned at the start of each sprite, in raster cycles 55–56:

- When the slot is free, it goes to the lowest-numbered of its three sprites that starts on this line: *n* first, then *n*+8, then *n*+16.
- A sprite keeps its slot until it has finished displaying all its lines.

In practice:

- Up to 8 sprites can appear on any raster line, and up to 24 on screen.
- The three sprites that share a slot must be stacked vertically without overlapping. Leave at least one free line between the bottom of one and the top of the next: 22 lines from Y to Y for normal sprites, 43 for Y-expanded ones. If they do overlap, the one already displayed keeps the slot and the other is skipped for that frame.
- Sprite pointers sit in the free bytes after the 1000 screen codes. With the default screen at `$0400`:
  - sprites 0–7: screen + `$3F8`…`$3FF` (`$07F8–$07FF`, stock)
  - sprites 8–15: screen + `$3F0`…`$3F7` (`$07F0–$07F7`)
  - sprites 16–23: screen + `$3E8`…`$3EF` (`$07E8–$07EF`)
- Display priority between sprites follows the slot: the lower slot is drawn in front. Sprites 0, 8 and 16 are frontmost, sprites 7, 15 and 23 rearmost.
- Collisions are reported for the sprite that was actually displayed. Read `$D056`/`$D057` and `$D096`/`$D097` before `$D01E`/`$D01F`, because reading `$D01E`/`$D01F` clears all 24 bits, as on the stock chip.
- Multicolour sprites 8–23 use the shared multicolour registers `$D025`/`$D026`.

## Palette

With PALEN set, every one of the 16 colour indices is replaced by its palette entry. This covers colour RAM, background and border colours, and sprite colours. Each entry is a hue and a luminance, as on the Atari GTIA:

- **Hue 0** is grey. Hues 1–15 go round the colour wheel in 24° steps: 1 red, 2 orange, 3 ochre, 4 olive, 5–7 green, 8 teal, 9 sky blue, 10–11 blue, 12–13 purple, 14 magenta, 15 pink.
- **Luminance** 0–15 runs from black to full brightness.

That gives 256 colours, 16 of them on screen at a time. A raster interrupt can rewrite palette entries mid-frame to show more.

At reset, the palette holds the closest hue/luminance match to each stock VIC colour, so setting PALEN without programming the palette changes the picture only slightly. With PALEN clear, the stock colours come from the palette selected in the MiSTer OSD.

## Hardware scrolling

On a stock VIC-II, the CPU has to copy 1000 bytes of screen and 1000 bytes of colour RAM every time the picture moves by 8 pixels. The VIC-IIx registers move the display window instead. The existing fine-scroll bits in `$D011`/`$D016` still scroll by 0–7 pixels; the new registers handle the whole-character steps.

### Screen start offset (`$D071`/`$D072`)

The display starts this many characters into screen memory, instead of at the beginning. The offset is 10 bits wide (0–1023) and is split over two registers. **Write `$D072` (high bits) first, then `$D071` (low byte).** The high bits are held until the low byte is written, and then both change together, so a frame never sees half an update. The same offset applies to colour RAM, so colours move with the characters. Screen memory is treated as a ring of 1024 characters: it wraps from `$3FF` back to `$000`.

To scroll up one character row, add the row length (normally 40) to the offset and write the one new row that comes into view at the bottom.

### Row length (`$D073`)

This sets the distance in memory from one screen row to the next. With a row length of 64, for example, the 40 visible columns are a window onto a map 64 characters wide. Adding 1 to the start offset scrolls one character sideways. The ring is still 1024 characters, so longer rows mean fewer rows in memory: with 64 characters per row it holds 16 rows, and the display wraps round to the top of the ring after them. To scroll further, write the new rows as they come into view.

### Sprite pointer page (`$D074` bit 1, `$D075`)

When the display scrolls through the whole ring, the sprite pointer bytes at the end of screen memory come into view. Setting PTRSEP moves all 24 pointers to their own page in the VIC's 16K:

- sprites 0–7 at page + `$F8`…`$FF`
- sprites 8–15 at page + `$F0`…`$F7`
- sprites 16–23 at page + `$E8`…`$EF`

`$D075` holds address bits 13–8 of that page. For example, `$0E` puts the pointers at `$0EE8–$0EFF`.

### Applied at the start of each frame

The start offset and row length are copied into the VIC at the start of each frame. A program can update them at any time during a frame, and the next frame is drawn entirely with the new values, without tearing. PTRSEP and PTRPAGE take effect immediately.

The C128 screen editor knows nothing about these registers. It still assumes a 40 × 25 screen starting at its normal address. Hardware scrolling is meant for programs that run their own display, such as games and demos.

### Smooth scrolling

For smooth scrolling, combine the start offset with the fine-scroll bits of `$D011`. To scroll up by one pixel per frame:

1. Select 24-row mode (`$D011` bit 3 = 0), so the partly scrolled row is hidden behind the border.
2. Once per frame, while the beam is in the bottom border (for example at raster line 251), lower the fine scroll (`$D011` bits 2–0) by one.
3. When it goes below 0, set it back to 7 and add the row length (40) to the start offset, writing `$D072` and then `$D071`.

The start offset is applied at the next frame, and the fine scroll takes effect from the top of the next frame as well, so both change together. Each new character row costs two register writes, where a stock VIC-II needs 2000 bytes copied.

### Example (C128 BASIC 7.0)

This scrolls the text screen up one whole row at a time through its 1K ring, then puts it back. It pauses after each step so you can follow it:

```basic
10 BANK 15
20 POKE 53311,165:POKE 53311,150:REM UNLOCK ($D03F)
30 FOR S=0 TO 1023 STEP 40
40 POKE 53362,INT(S/256):POKE 53361,S AND 255:REM START OFFSET, HIGH ($D072) FIRST
50 FOR D=1 TO 150:NEXT D,S
60 POKE 53362,0:POKE 53361,0
```

The last 24 bytes of the ring, `$3E8–$3FF`, scroll past as a few odd characters: those are the sprite pointers, which PTRSEP would move out of the way.

## Sprite and palette test program (C128 BASIC 7.0)

```basic
10 BANK 15
20 POKE 53311,165:POKE 53311,150:REM UNLOCK ($D03F)
30 IF PEEK(53311)<>254 THEN PRINT "NO VIC-IIX":END
40 FOR I=3584 TO 4095:POKE I,255:NEXT:REM SOLID SHAPES IN BLOCKS 56-63
50 FOR N=1 TO 8:SPRITE N,1,N+1:MOVSPR N,30+(N-1)*32,70:NEXT:REM SPRITES 0-7
60 FOR N=0 TO 7
70 POKE 2032+N,56:REM POINTER FOR SPRITE N+8 ($07F0+N)
80 POKE 53312+2*N,30+N*32:REM X ($D040+2N)
90 POKE 53313+2*N,130:REM Y ($D041+2N)
100 POKE 53336+N,15-N:REM COLOUR ($D058+N)
110 POKE 2024+N,56:REM POINTER FOR SPRITE N+16 ($07E8+N)
120 POKE 53376+2*N,30+N*32:REM X ($D080+2N)
130 POKE 53377+2*N,190:REM Y ($D081+2N)
140 POKE 53400+N,N+8:REM COLOUR ($D098+N)
150 NEXT
160 POKE 53329,255:REM ENABLE SPRITES 8-15 ($D051)
170 POKE 53393,255:REM ENABLE SPRITES 16-23 ($D091)
180 POKE 53360,1:REM PALEN ($D070)
190 FOR C=0 TO 255:POKE 53357,C:FOR D=1 TO 30:NEXT D,C:REM CYCLE PALETTE ENTRY 13
200 POKE 53360,0:REM BACK TO STOCK COLOURS
```

The program shows three rows of 8 sprites, 24 in all. Lines 180–190 then step palette entry 13, the default C128 border and text colour, through all 256 colours.
