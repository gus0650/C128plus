# C128+ core for [MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

The C128+ is a (rumored) prototype home computer developed by Commodore in 1986. It was never released as a finished product.

It is an improved and streamlined version of the C128.

It has 256 KB of RAM.

It has Dual SID chips and stereo output.

It has an improved graphics chip called the VIC-IIx. This chip adds some cool features:
-	256 color palette (16 colors on screen at a time)
-	24 sprites (up to 8 per scanline)
- improved scrolling registers (no memory copy necessary).

It comes with BASIC 7.1 that supports these new features natively.

It scraps the CP/M subsystem to save cost. So no Z80 and no VDC chip.

This is the ultimate 8-bit homecomputer and the pinnacle of CBM's 6502-based product line!

Notes:

See [docs/VIC-IIx.md](docs/VIC-IIx.md) for the VIC-IIx registers, and BASIC test programs.

See [docs/BASIC71-Graphics.md](docs/BASIC71-Graphics.md) for the BASIC 7.1 graphics commands (`SPRITE`, `MOVSPR`, `RSPRITE`, `RSPPOS` and `BUMP` for 24 sprites, `SPRPTR`, `PALETTE`, `RPALETTE`) and test programs.

See [docs/BASIC71-Sound.md](docs/BASIC71-Sound.md) for six-voice sound with both SIDs (BASIC 7.1 `SOUND`, `PLAY`, `VOL`, `FILTER`) and a test program.

ROMs:

The core needs the C128 system and drive ROMs. Put boot0.rom (system ROMs) and boot1.rom (drive ROMs) and boot2.rom (BASIC extensions) in games/C128plus.


Acknowledgements:

Based on [C128_MiSTer](https://github.com/MiSTer-devel/C128_MiSTer).
