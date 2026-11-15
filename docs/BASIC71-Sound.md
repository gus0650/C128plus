# Six-voice sound in BASIC 7.1

The C128+ has two SIDs. With BASIC 7.1 (`boot2.rom`), BASIC's own sound
commands use both of them, for six voices:

| Voices | SID | Address |
|---|---|---|
| 1–3 | SID 1 | `$D400` (54272) |
| 4–6 | SID 2 | `$D420` (54304) |

This is the layout Commodore planned for the C65, whose BASIC 10 also used
voices 1–6 on two SIDs at these addresses. Everything else stays C128 BASIC
7.0: the same commands, the same parameters, the same `PLAY` strings.

## Setting up

1. Copy `boot2.rom` from `basic71/` to `/media/fat/games/C128plus/`.
2. In the core's menu, leave **Right SID Port** on **D420** (the default).
   With **Same**, both SIDs sit at `$D400` and voices 4–6 are not heard
   separately.
3. Start the core. The start-up screen shows
   `C128+ BASIC 7.1 - VIC-IIX EXTENSIONS`.

Six-voice sound is on from the start. You don't need to enter a command first.

## Quick start

```
PLAY "V1O4HCV4O3HE"          : REM C on SID 1 and E on SID 2, together
SOUND 5,3000,60              : REM one second of sound on voice 5 (SID 2)
VOL 15,8                     : REM SID 1 loud, SID 2 half volume
```

## Commands

### SOUND

```
SOUND v, f, d [, dir [, min [, step [, wave [, pw]]]]]
```

Same as BASIC 7.0's `SOUND`, with **v = 1–6**.

| Parameter | Range | Meaning |
|---|---|---|
| `v` | 1–6 | voice; 4–6 are on SID 2 |
| `f` | 0–65535 | frequency (SID register value) |
| `d` | 0–32767 | duration in jiffies (1/60 s NTSC, 1/50 s PAL); 0 stops the voice |
| `dir` | 0–2 | sweep: 0 up, 1 down, 2 oscillate (default 0) |
| `min` | 0–65535 | lowest frequency of the sweep (default 0) |
| `step` | 0–32767 | sweep step per jiffy (default 0: no sweep) |
| `wave` | 0–3 | 0 triangle, 1 sawtooth, 2 pulse (default), 3 noise |
| `pw` | 0–4095 | pulse width (default 2048) |

`SOUND` returns at once. The sound and its sweep run in the background. If
the voice is still busy, `SOUND` first waits until it is free.

```
SOUND 2,4000,180,2,1500,120,1   : REM sawtooth siren on SID 1
SOUND 5,9000,180,2,5000,250,0   : REM triangle siren on SID 2 at the same time
```

### PLAY

```
PLAY "string"
```

Same as BASIC 7.0's `PLAY`, with voices `V1`–`V6`. A string can switch
voices as often as it likes, so one `PLAY` can play on both chips.

| Element | Meaning |
|---|---|
| `V1`–`V6` | select the voice for the following notes; 4–6 are on SID 2 |
| `O0`–`O6` | octave |
| `T0`–`T9` | instrument (envelope) for the current voice, see below |
| `U0`–`U9` | volume of the current voice's SID |
| `X0` / `X1` | current voice through its SID's filter: off / on |
| `M` | wait until all six voices have finished their notes |
| `A`–`G` | play a note |
| `#` / `$` | sharp / flat (before the note) |
| `W H Q I S` | note length: whole, half, quarter, eighth, sixteenth |
| `.` | dotted: the next note is 1.5 times as long |
| `R` | rest |

A note waits only for the previous note on its own voice. Mixing voices in
one string makes them play at the same time:

```
PLAY "V1O4HCV2O4HEV3O4HG"            : REM chord on SID 1
PLAY "V4T0O2HCV1T6O4QCQE"            : REM bass on SID 2 under a melody on SID 1
```

The octave and the note length are shared by all voices, as in BASIC 7.0. So
repeat `O` when you switch between voices in different octaves.

**Instruments (`T0`–`T9`):** 0 piano, 1 accordion, 2 calliope, 3 drum, 4
flute, 5 guitar, 6 harpsichord, 7 organ, 8 trumpet, 9 xylophone. BASIC's
`ENVELOPE` command changes them for all six voices.

### VOL

```
VOL a [, b]
```

| Form | Effect |
|---|---|
| `VOL a` | both SIDs to volume `a` (0–15) |
| `VOL a, b` | SID 1 to `a`, SID 2 to `b` |

`VOL 15,0` and `VOL 0,15` are a quick way to tell which SID is on which
stereo channel.

### FILTER

```
FILTER [f] [, lp] [, bp] [, hp] [, res]
```

Same parameters as BASIC 7.0's `FILTER`: cut-off frequency `f` (0–2047),
low pass / band pass / high pass on or off (0/1), resonance `res` (0–15).
The settings apply to both SIDs.

As in BASIC 7.0, `FILTER` only stores the settings. They take effect with
`PLAY "X1"`, which routes the current voice through the filter of its own
SID. Each SID keeps its own routing and volume.

```
FILTER 500,1,0,0,12
PLAY "V1X0O3ICEG"      : REM voice 1 unfiltered
PLAY "V4X1O3ICEG"      : REM voice 4 through SID 2's low pass filter
```

### ENVELOPE and TEMPO

These stay BASIC 7.0's own commands. `ENVELOPE` defines instruments 0–9 for
all six voices, and `TEMPO` sets the speed of `PLAY` on both chips.

### SID6 ON / SID6 OFF

```
SID6 ON
SID6 OFF
```

BASIC 7.1 catches the keywords `SOUND`, `PLAY`, `VOL` and `FILTER` when you
type a line. `SID6` decides whether it does:

| Setting | Lines you type from now on |
|---|---|
| `SID6 ON` (default) | the four keywords become BASIC 7.1 keywords: six voices |
| `SID6 OFF` | the four keywords stay BASIC 7.0's own: three voices on SID 1 |

`SID6` only affects lines typed afterwards. Lines already in memory keep the
keywords they were typed with. Both kinds work in the same program.

## Compatibility

- **Programs loaded from disk** contain BASIC 7.0's keywords. They run as
  before, on BASIC's own three-voice code, and play only on SID 1.
- **Programs typed or edited with `SID6 ON`** contain BASIC 7.1 keywords.
  `LIST` shows them normally, but they need the C128+ with BASIC 7.1. On a
  normal C128, those lines stop with `?SYNTAX ERROR`. The same applies to
  `SPRITE` and the other BASIC 7.1 commands.
- **Programs that must also run on a normal C128:** type `SID6 OFF` before
  writing or editing the sound lines.
- **Sound from both kinds of keywords at once:** BASIC 7.0's and BASIC 7.1's
  sound code are separate. If both drive the same voice on SID 1 at the same
  time, the last one wins.
- **RUN/STOP + RESTORE** silences all six voices.

## Test program

`basic71/test/sid6test.prg` (source: `sid6test.bas`) goes through all of the
above with sound you can check by ear:

1. C major chord on SID 1 (voices 1–3)
2. A minor chord on SID 2 (voices 4–6)
3. all six voices together, over five octaves
4. the same arpeggio with `VOL 15,0`, then `VOL 0,15`: you should hear it on
   one stereo channel, then on the other
5. two `SOUND` sirens at once, on voice 2 and voice 5
6. a phrase on voice 1 without filter, then on voice 4 with a resonant low
   pass filter
7. a melody on SID 1 over a bass line on SID 2

Load and run it with BASIC 7.1 installed:

```
DLOAD "SID6TEST"
RUN
```

If a part stays silent: check that `boot2.rom` is the stage 6 version (the
program uses `SID6`, which earlier versions don't know: `?SYNTAX ERROR` in
line 30), and that **Right SID Port** is on **D420**.

## How it works

BASIC 7.1 is a C128 function ROM, so this uses only documented ways into
BASIC and the Kernal. No Commodore ROM is changed.

- **Keywords:** when you type a line, BASIC 7.1's hook on BASIC's tokenizer
  turns `SOUND`, `PLAY`, `VOL` and `FILTER` into BASIC 7.1 escape tokens
  (`$FE $43`–`$FE $46`; `SID6` is `$FE $47`).
- **Sound engine:** BASIC 7.1 has its own copy of BASIC 7.0's sound engine,
  for six voices. It keeps note counters for `PLAY`, sweeps and durations for
  `SOUND`, and a filter/volume record for each SID.
- **Timing:** BASIC 7.1 hooks the Kernal's IRQ vector (`$0314`) and advances
  the engine once per tick of the jiffy clock. This is the same rate as
  BASIC's own music, also when split screens use extra raster interrupts.
- **Shared settings:** `ENVELOPE` instruments, `TEMPO`, the current octave
  and note length are BASIC 7.0's own variables. BASIC 7.1 reads them, so
  both work together.
- **RESTORE:** RUN/STOP + RESTORE resets the Kernal's IRQ vector. BASIC 7.1
  also hooks the Kernal's warm start vector (`$0A00`) to silence both SIDs
  and install its IRQ hook again.
- **RAM:** the engine's tables are in BASIC 7.1's RAM area at `$1800`.

The tests in `basic71/test_sound.py` boot the real Kernal and BASIC with
BASIC 7.1 in a C128 simulator, type the commands and check every write to
both SIDs.
