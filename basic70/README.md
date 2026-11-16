# Six-voice BASIC 7.0 (second SID)

`make_rom.py` turns an original C128 `boot0.rom` into one with a patched
BASIC 7.0. No ROM file is included here: Commodore's ROMs are copyrighted,
so build it from your own copy. BASIC's sound commands can use the second SID at $D420, which gives six voices.
The layout is the same one Commodore used for the C65: voices 1–3 play on the
SID at $D400 and voices 4–6 on the SID at $D420.

To use it, build `boot0.rom` as shown below and copy it to `games/C128plus/`
on the MiSTer, replacing the one there. Keep a copy of your original. Leave the core's "Right SID Port"
setting on D420, which is the default.

## Commands

| Command | What changed |
|---|---|
| `SOUND v,f,d,...` | `v` = 1–6. Voices 4–6 play on SID 2, with sweeps and durations as before. |
| `PLAY "V4 ..."` | `V1`–`V6`. The `U` (volume) and `X` (filter) settings act on the SID of the current voice. `M` waits for all six voices. |
| `VOL a[,b]` | `a` = SID 1, `b` = SID 2. `VOL a` sets both. |
| `FILTER f,l,b,h,r` | Sets cut-off, resonance and filter type on both SIDs. Each SID keeps its own voice routing (`PLAY "Xn"`) and volume. |
| `ENVELOPE`, `TEMPO` | Unchanged. The 10 instruments apply to all six voices. |

Programs written for the normal three voices behave as before.

## How it is built

`make_rom.py` rebuilds BASIC 7.0 (318018/318019-04) from Commodore's original
source in [mist64/cbmsrc](https://github.com/mist64/cbmsrc) with its own
assembler (`bsoasm.py`):

1. It assembles the unchanged source and checks that the result matches the
   BASIC in the input `boot0.rom` byte for byte.
2. It applies the changes: the sound tables grow from 3 to 6 voices, and the
   changed routines jump to new code in `sid6.src`.
3. It checks that all 2154 original BASIC labels keep their address, so
   programs that call BASIC routines directly still work.

The new code is 641 bytes long and sits in free ROM space after the machine
language monitor, at $BB72–$BDF2 (461 bytes are still free). The six-voice
tables live in RAM at $1B80–$1BDE, at the top of the function-key area. This
ROM patch can't be used together with BASIC 7.1, which needs the whole area
and has six-voice sound of its own.

```
git clone https://github.com/mist64/cbmsrc
python3 make_rom.py cbmsrc /path/to/original/boot0.rom boot0.rom
python3 test_sid6.py boot0.rom ../releases/boot0.rom
```

`test_sid6.py` boots the real Kernal and BASIC in a small C128 simulator
(`c128sim.py`), types commands and checks the writes to both SIDs.
