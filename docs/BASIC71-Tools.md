# Programming tools in BASIC 7.1

BASIC 7.1 (`boot2.rom`) adds a few tools that BASIC 7.0 lacks, in the spirit
of Simons' BASIC for the C64:

| Feature | Example |
|---|---|
| hex and binary numbers | `POKE $D040,%10000001` |
| `MOD()`, `DIV()` | `PRINT MOD(17,5);DIV(17,5)` → 2 3 |
| `FIND` | `FIND "SPRITE"` lists every line that uses `SPRITE` |
| `MERGE` | `MERGE "SUBS"` adds the lines of a program on disk |
| `DUMP` | lists all variables with their values |

## Hex and binary numbers

Anywhere BASIC expects a number, you can write it in hex with `$` or in
binary with `%`:

```
POKE $D020,0                 : REM border black (53280)
PRINT $D040, %1010           : REM 53312, 10
SPRITE 9,1:POKE $D051,PEEK($D051) OR %00000011
A=$FF+1                      : REM 256
```

- Values are 0–65535 (`$0`–`$FFFF`, up to 16 binary digits). A larger value
  gives `?ILLEGAL QUANTITY ERROR`, `$` or `%` without digits gives
  `?SYNTAX ERROR`.
- They work in expressions, in direct mode and in programs, and `LIST` shows
  them as typed. A minus sign works as usual: `-$10` is −16.
- They don't work in `DATA` lines or for `INPUT`: BASIC reads those numbers
  with its own routine.
- `$` after a letter or digit is still a string variable: `A$`, `X1$`.
- Leave a space between a hex number and a keyword that starts with A–F,
  otherwise the letters are read as hex digits: `IF X=$FF AND Y` rather
  than `IF X=$FFAND Y`.

`HEX$()` and `DEC()` still exist for converting at run time.

## MOD and DIV

```
v = MOD(a, b)       remainder of a / b
v = DIV(a, b)       a / b without the remainder
```

Both work with whole numbers 0–65535 (a negative number or more than 65535
gives `?ILLEGAL QUANTITY ERROR`, b = 0 gives `?DIVISION BY ZERO ERROR`).

```
PRINT MOD(17,5);DIV(17,5)              : REM 2 3
X=MOD(X+1,40)                           : REM count 0-39 and round again
ROW=DIV(P,40):COL=MOD(P,40)             : REM screen position -> row, column
```

## FIND

```
FIND "text"
```

Lists every line of the program in memory that contains `text`, like
`LIST`. RUN/STOP stops the listing.

`FIND` searches both ways a text can be stored: as typed (inside strings and
`REM`s) and as BASIC keywords. So `FIND "PRINT"` finds `PRINT` statements as
well as the word PRINT in a string, and `FIND "SPRITE 9"` finds that exact
statement. The text can be up to 39 characters.

## MERGE

```
MERGE "name" [, device]
```

Adds the lines of a program on disk to the program in memory, as if they
were typed in: lines with new numbers are inserted, and a line with the same
number as an existing one replaces it. The device is 8 unless given.

```
MERGE "SUBROUTINES"            : REM e.g. a library of lines 9000-9999
MERGE "LEVEL2",9
```

- Direct mode only: in a program it gives `?ILLEGAL QUANTITY ERROR`.
- The file must be a BASIC program (PRG). Its load address doesn't matter.
- The program's lines are stored exactly as saved: keywords of BASIC 7.0
  and BASIC 7.1 stay as they are.
- If the file doesn't exist, the error is `?FILE NOT FOUND ERROR` and the
  program in memory is unchanged. If memory runs out, merging stops with
  `?OUT OF MEMORY ERROR`, and the lines up to that point are in.
- As with typing a line, the variables keep their values.

## DUMP

```
DUMP
```

Lists all simple variables with their current values, one per line:

```
A= 5
B%=-3
C$="HI"
D= 1.5
```

Arrays and `DEF FN` functions are not listed. RUN/STOP stops the list.
`DUMP` also works inside a program, for example to see the variables at a
certain point while debugging.

## Compatibility

- The new keywords `FIND`, `MERGE`, `DUMP`, `MOD` and `DIV` are reserved
  words when BASIC 7.1 is installed. A variable whose name starts with them
  no longer works when typed: `MODE`, `DIVE`, `FINDX` and `DUMPS` are read as
  the keyword plus a letter. Programs loaded from disk are not affected.
- Programs that use these keywords or `$`/`%` numbers need the C128+ with
  BASIC 7.1. On a normal C128, those lines stop with `?SYNTAX ERROR`.
- The `$`/`%` numbers cost BASIC a little time on every number and variable
  it evaluates: about 4% in a loop full of arithmetic.

## Test program

`basic71/test/tooltest.prg` (source: `tooltest.bas`) and
`basic71/test/mergepart.prg`, both on `tools.d64`:

```
DLOAD "TOOLTEST"
RUN
```

It prints hex, binary, `MOD` and `DIV` results with the values they should
have and runs `DUMP`. Then it asks you to type `FIND "DUMP"`, which lists
lines 10, 80 and 100 (the keyword in line 80, the word in the `REM` and the
string), and `MERGE "MERGEPART"`. After that, `RUN` again ends with "MERGE
WORKED: 255".

`basic71/test_tools.py` tests all of this with the real Kernal and BASIC in
the C128 simulator; for `MERGE` it uses a pretend disk drive.

## How it works

- **`$`/`%` numbers:** BASIC 7.1 hooks BASIC's term evaluation vector
  (`$030A`). When a term starts with `$` or `%`, it reads the digits and puts
  the value into BASIC's floating point accumulator; otherwise BASIC carries
  on as usual. The tokenizer hook leaves the digits after `$` alone, so that
  `$DEC0` doesn't turn into the keyword `DEC`.
- **`MERGE`:** BASIC 7.1 opens the file, then points BASIC's main loop
  (`$0302`) at itself. For each line in the file it hands BASIC the line
  number and the tokenized text, and BASIC stores it with its own code,
  exactly as for a typed line. At the end of the file the main loop goes
  back to the keyboard.
- **`FIND`:** the text is searched for twice, as typed and after running it
  through BASIC's tokenizer; a matching line is printed with BASIC's own
  `LIST` code.
- **`DUMP`:** reads the variable table in RAM bank 1 and prints each value
  with BASIC's number and string output.
- **Tokens:** `FIND` `$FE $4A`, `MERGE` `$FE $4B`, `DUMP` `$FE $4C`, `MOD`
  `$CE $44`, `DIV` `$CE $45`.
