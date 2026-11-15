; =============================================================================
;  C128plus BASIC 7.1 - internal function ROM for the C128plus (C128 mode)
;
;  Loaded as boot2.rom (32K: the code is in the upper 16K, seen at $C000).
;  Adds BASIC 7.0 keywords for the VIC-IIx through the official BASIC
;  escape-token hooks, and unlocks the VIC-IIx at power-up.
;
;  Stage 1-3: start-up line, VIC-IIx unlock, PALETTE, RPALETTE(),
;              SPRITE for sprites 1-24, SPRPTR
;  Stage 4:   MOVSPR, RSPRITE(), RSPPOS(), BUMP() for sprites 1-24
;  Stage 6:   six-voice sound with the second SID at $D420: SOUND, PLAY,
;              VOL and FILTER for voices 1-6, SID6 ON/OFF
;
;  Memory map while BASIC 7.1 code runs (MMU config $10):
;    $0000-$3FFF RAM 0   $4000-$BFFF BASIC ROM   $C000-$FFFF BASIC 7.1 ROM
;    $D000-$DFFF I/O     $FF00-$FF04 MMU
;  The Kernal is not visible, and BASIC switches the memory map while it
;  reads variables, so every call into BASIC/Kernal goes through SYSCALL
;  (RAM), which switches to the normal BASIC map for the duration of the call.
;  RAM used: $1800-$1B7F ("reserved for function key software applications"
;  in the C128 Kernal source). $1B80-$1BFF belongs to the six-voice BASIC
;  in basic70/boot0.rom.
; =============================================================================

; ---- system addresses (C128 BASIC 7.0 / Kernal) ----------------------------
mmucr      = $FF00      ; MMU configuration register
CFG_SYS    = $00        ; Kernal + BASIC + RAM0 + I/O (normal BASIC map)
CFG_71     = $10        ; RAM0 + BASIC lo/hi + internal function ROM hi + I/O

index1     = $24        ; BASIC utility pointer (used by LIST for foreign tokens)
txtptr     = $3D        ; BASIC text pointer

esc_fn_vec = $02FC      ; foreign escape function vector
iesclk     = $030C      ; escape token crunch vector
iescpr     = $030E      ; escape token list vector
iescex     = $0310      ; escape token execute vector

chrget     = $0380
chrgot     = $0386
chkcls     = $7956      ; check for ')'
snerr      = $796C      ; ?SYNTAX ERROR
fcerr      = $7D28      ; ?ILLEGAL QUANTITY ERROR
sngflt     = $84D4      ; Y -> FAC (function result)
getbyt     = $87F4      ; evaluate byte expression -> X
conint     = $87F7      ; FAC -> byte in X
combyt     = $8809      ; check comma, evaluate byte -> X
optbyt     = $9E1E      ; optional ',byte': C=1 and X = value if present
chrout     = $FFD2

; BASIC 7.0 (318018/318019-04) routines and data used by the sound commands
comwrd     = $880F      ; check comma, word -> Y lo, A hi
getwrd     = $8812      ; word -> Y lo, A hi
optzer     = $9E1C      ; optional ',byte', default 0 -> X
optwrd     = $9E06      ; optional ',word': C=1 and Y lo, A hi if present
frmstr     = $877B      ; string expression: A = length, (index1) -> string in RAM 1
indfet     = $FF74
jsrfar     = $FF6E      ; Kernal JSRFAR: call fr_pchi/fr_pclo in bank fr_bank
fr_bank    = $02        ; JSRFAR parameters (also used by BASIC's SYS)
fr_pchi    = $03
fr_pclo    = $04
fr_s       = $05
fr_a       = $06
fr_x       = $07
fr_y       = $08      ; Kernal INDFET: A = zp pointer, X = bank, Y = index
play_pal   = $7EA6      ; X = note 0-11 -> A = pitch high byte (PAL/NTSC), sets pitch
b_scalen   = $6FF2      ; note A-G -> 0-11
b_scalel   = $6FF9      ; pitch low bytes (NTSC)
b_voltab   = $703C      ; PLAY U0-U9 -> SID volume
b_sbits    = $6CB3      ; bit masks 1,2,4,...; +4: waveform bits
atktab     = $123F      ; ENVELOPE tables (RAM, set by BASIC's ENVELOPE)
sustab     = $1249
wavtab     = $1253
pulslw     = $125D
pulshi     = $1267
tempo_rate = $1222      ; TEMPO
ntime      = $1229      ; current note length
octave     = $122B
pitch      = $122D      ; 2 bytes
BEATS      = 1152       ; whole note
jiffy      = $A2        ; low byte of the jiffy clock (TI)
cinv       = $0314      ; Kernal IRQ vector
system_vector = $0A00   ; Kernal warm start vector (RUN/STOP + RESTORE)

; BASIC 7.0 sprite routines and data (318018/318019-04)
movspr_cont = $6CC9     ; BASIC's MOVSPR after reading the sprite number
z_p_temp_1 = $77        ; sprite number 0-7 for MOVSPR
vic_save   = $11D6      ; BASIC's copy of $D000-$D010 (+17/+18: BUMP values)
sprite_data = $117E     ; BASIC's motion records, 11 bytes per sprite
irq_wrap_flag = $12FD   ; non-zero: BASIC's IRQ code does nothing
nosflt     = $84C9      ; Y low, A high -> FAC (unsigned)
chkcom     = $795C      ; check for ','
ierror     = $0300      ; BASIC error vector (error number in X)

; ---- SIDs -----------------------------------------------------------------------
sid        = $D400      ; voices 1-3
SID2       = $20        ; offset of the second SID: voices 4-6 at $D420

tk_on      = $91        ; BASIC token ON
tk_esc_cmd = $FE        ; escape prefix, statements
tk_off     = $24        ; second byte of OFF ($FE $24)

; ---- VIC-IIx ----------------------------------------------------------------
vic        = $D000
vicx_key   = $D03F      ; reads $FE while the extensions are unlocked
vicx_pal   = $D060
vicx_palen = $D070
vicx_ctrl  = $D074      ; bit 0 WIDE, bit 1 PTRSEP
vicx_ppage = $D075      ; sprite pointer page
cia2_pra   = $DD00      ; VIC bank (bits 1-0, inverted)

; ---- BASIC 7.1 tokens (second byte; > BASIC's own $26 / $0A ranges) -----------------
TK_PALETTE  = $40       ; $FE $40
TK_SPRITE   = $41       ; $FE $41  (replaces BASIC's own SPRITE when typed with BASIC 7.1)
TK_SPRPTR   = $42       ; $FE $42
TK_SOUND    = $43       ; $FE $43  (replaces BASIC's own SOUND/PLAY/VOL/FILTER
TK_PLAY     = $44       ; $FE $44   when typed with SID6 ON)
TK_VOL      = $45       ; $FE $45
TK_FILTER   = $46       ; $FE $46
TK_SID6     = $47       ; $FE $47
TK_MOVSPR   = $48       ; $FE $48  (replaces BASIC's own MOVSPR when typed with BASIC 7.1)
FN_RPALETTE = $40       ; $CE $40
FN_RSPRITE  = $41       ; $CE $41  (replace BASIC's RSPRITE, RSPPOS, BUMP)
FN_RSPPOS   = $42       ; $CE $42
FN_BUMP     = $43       ; $CE $43
CMD_FIRST   = $40
CMD_LAST    = $48
FN_FIRST    = $40
FN_LAST     = $43

; =============================================================================
;  ROM image: 32K. $8000 half is empty, code is in the $C000 half.
; =============================================================================
            .base $8000
            .org  $8000
            .fill $4000, $FF          ; internal function ROM low: unused

            .org  $C000
            jmp coldstart             ; $C000 cold start (called by PHOENIX)
            jmp warmstart             ; $C003 warm start (unused by the Kernal)
            .byte $07                 ; $C006 ID (not 1: start after BASIC init)
            .byte "CBM"               ; $C007 function ROM key

; -----------------------------------------------------------------------------
;  Cold start: runs in Kernal bank 4 (both function ROM halves, RAM0, I/O)
;  with interrupts disabled, after BASIC has initialised.
; -----------------------------------------------------------------------------
coldstart:
            ; copy the RAM part to $1800
            ldx #0
cs_copy:    lda ramimage,x
            sta $1800,x
            lda ramimage+$100,x
            sta $1900,x
            lda ramimage+$200,x
            sta $1A00,x
            cpx #$80                  ; last page only up to $1B7F
            bcs cs_copy2
            lda ramimage+$300,x
            sta $1B00,x
cs_copy2:   inx
            bne cs_copy

            ; chain into the BASIC escape hooks
            lda iesclk
            sta old_clk
            lda iesclk+1
            sta old_clk+1
            lda iescpr
            sta old_lst
            lda iescpr+1
            sta old_lst+1
            lda iescex
            sta old_exe
            lda iescex+1
            sta old_exe+1
            lda esc_fn_vec
            sta old_fn
            lda esc_fn_vec+1
            sta old_fn+1

            lda #<r_crunch
            sta iesclk
            lda #>r_crunch
            sta iesclk+1
            lda #<r_list
            sta iescpr
            lda #>r_list
            sta iescpr+1
            lda #<r_exec
            sta iescex
            lda #>r_exec
            sta iescex+1
            lda #<r_fn
            sta esc_fn_vec
            lda #>r_fn
            sta esc_fn_vec+1

            ; six-voice sound: IRQ and warm start hooks, both SIDs silent
            lda cinv
            sta old_irq
            lda cinv+1
            sta old_irq+1
            lda #<r_irq
            sta cinv
            lda #>r_irq
            sta cinv+1
            lda system_vector
            sta old_sysvec
            lda system_vector+1
            sta old_sysvec+1
            lda #<r_warm
            sta system_vector
            lda #>r_warm
            sta system_vector+1
            lda #1
            sta s6_on
            jsr snd_init
            jsr spr_stop

            ; unlock the VIC-IIx
            lda #$A5
            sta vicx_key
            lda #$96
            sta vicx_key

            ; sprites 9-16 and 17-24 start with the shapes of sprites 1-8
            ; (blocks 56-63 at $0E00, pointers after the default screen at $0400)
            ldx #7
cs_ptr:     txa
            clc
            adc #56
            sta $07F0,x
            sta $07E8,x
            dex
            bpl cs_ptr

            ; start-up line
            ldx #0
cs_msg:     lda banner,x
            beq cs_done
            stx tmpx
            jsr r_chrout
            ldx tmpx
            inx
            bne cs_msg
cs_done:
warmstart:  rts

banner:     .byte 13, "C128+ BASIC 7.1 - VIC-IIX EXTENSIONS", 13, 0

; -----------------------------------------------------------------------------
;  Calls into BASIC / Kernal (via SYSCALL in RAM)
; -----------------------------------------------------------------------------
s_chrget:   lda #<chrget
            ldx #>chrget
            jmp syscall_ax
s_chrgot:   lda #<chrgot
            ldx #>chrgot
            jmp syscall_ax
s_getbyt:   lda #<getbyt
            ldx #>getbyt
            jmp syscall_ax
s_combyt:   lda #<combyt
            ldx #>combyt
            jmp syscall_ax
s_conint:   lda #<conint
            ldx #>conint
            jmp syscall_ax
s_chkcls:   lda #<chkcls
            ldx #>chkcls
            jmp syscall_ax
s_snerr:    lda #<snerr
            ldx #>snerr
            jmp syscall_ax
s_fcerr:    lda #<fcerr
            ldx #>fcerr
            jmp syscall_ax
s_optbyt:   lda #<optbyt
            ldx #>optbyt
            jmp syscall_ax
s_optbx:    lda #<optbyt              ; as s_optbyt, but X (the default) passes through
            sta sysvec
            lda #>optbyt
            sta sysvec+1
            jmp syscall
s_chkcom:   lda #<chkcom
            ldx #>chkcom
            jmp syscall_ax
s_nosflt:   sta tmpa2                 ; Y low, A high -> FAC
            lda #<nosflt
            sta sysvec
            lda #>nosflt
            sta sysvec+1
            lda tmpa2
            jmp syscall
s_comwrd:   lda #<comwrd
            ldx #>comwrd
            jmp syscall_ax
s_getwrd:   lda #<getwrd
            ldx #>getwrd
            jmp syscall_ax
s_optzer:   lda #<optzer
            ldx #>optzer
            jmp syscall_ax
s_optwrd:   lda #<optwrd
            ldx #>optwrd
            jmp syscall_ax
s_frmstr:   lda #<frmstr
            ldx #>frmstr
            jmp syscall_ax
s_indin1:   lda #<indfet              ; A = (index1),Y in RAM 1, through the Kernal
            sta sysvec                ; (BASIC's own INDIN1_RAM1 returns in a map
            lda #>indfet              ;  without our RAM, so it can't be used here)
            sta sysvec+1
            lda #index1
            ldx #1                    ; bank 1
            jmp syscall
s_sngflt:   lda #<sngflt          ; value in Y
            ldx #>sngflt
syscall_ax: sta sysvec
            stx sysvec+1
            jmp syscall

; -----------------------------------------------------------------------------
;  Tokenizer: called for each character outside strings/REM/DATA.
;  In:  A = character, (txtptr) = text in the input buffer (RAM0)
;  Out: match:    C=0, A = second token, X = 0 (statement) / $FF (function),
;                 Y = index of the last keyword character (as BASIC's RESER)
;       no match: C=1, A unchanged
; -----------------------------------------------------------------------------
rom_crunch: sta tmpa
            ldx #0
cr_next:    lda kwtab,x
            beq cr_none               ; end of table
            ldy #0
cr_cmp:     lda kwtab,x
            and #$7F
            cmp (txtptr),y
            bne cr_skip
            lda kwtab,x
            bmi cr_match              ; last character matched
            inx
            iny
            bne cr_cmp
cr_skip:    lda kwtab,x               ; skip to the end of this keyword
            bmi cr_skip2
            inx
            bne cr_skip
cr_skip2:   inx                       ; past last char, token and type
            inx
            inx
            jmp cr_next
cr_match:   lda kwtab+1,x             ; second token byte
            cmp #TK_SOUND
            bcc cr_take
            cmp #TK_FILTER+1
            bcs cr_take
            lda s6_on                 ; SOUND/PLAY/VOL/FILTER: only with SID6 ON
            beq cr_none
            lda kwtab+1,x
cr_take:    sta tmpa
            lda kwtab+2,x             ; type
            tax
            lda tmpa
            clc
            rts
cr_none:    lda tmpa
            sec
            rts

;  keyword, last char | $80, second token byte, type (0 = statement, $FF = function)
kwtab:      .byte "RPALETT", 'E'+$80, FN_RPALETTE, $FF
            .byte "PALETT",  'E'+$80, TK_PALETTE,  $00
            .byte "SPRIT",   'E'+$80, TK_SPRITE,   $00
            .byte "SPRPT",   'R'+$80, TK_SPRPTR,   $00
            .byte "SOUN",    'D'+$80, TK_SOUND,    $00
            .byte "PLA",     'Y'+$80, TK_PLAY,     $00
            .byte "VO",      'L'+$80, TK_VOL,      $00
            .byte "FILTE",   'R'+$80, TK_FILTER,   $00
            .byte "SID",     '6'+$80, TK_SID6,     $00
            .byte "MOVSP",   'R'+$80, TK_MOVSPR,   $00
            .byte "RSPRIT",  'E'+$80, FN_RSPRITE,  $FF
            .byte "RSPPO",   'S'+$80, FN_RSPPOS,   $FF
            .byte "BUM",     'P'+$80, FN_BUMP,     $FF
            .byte 0

; -----------------------------------------------------------------------------
;  Statement dispatcher.  In: A = second token byte, txtptr on it.
;  Must leave txtptr on the statement terminator (':' or end of line).
; -----------------------------------------------------------------------------
rom_exec:   cmp #TK_PALETTE
            bne ex_1
            jmp do_palette
ex_1:       cmp #TK_SPRITE
            bne ex_2
            jmp do_sprite
ex_2:       cmp #TK_SPRPTR
            bne ex_3
            jmp do_sprptr
ex_3:       cmp #TK_SOUND
            bne ex_4
            jmp do_sound
ex_4:       cmp #TK_PLAY
            bne ex_5
            jmp do_play
ex_5:       cmp #TK_VOL
            bne ex_6
            jmp do_vol
ex_6:       cmp #TK_FILTER
            bne ex_7
            jmp do_filter
ex_7:       cmp #TK_SID6
            bne ex_8
            jmp do_sid6
ex_8:       cmp #TK_MOVSPR
            bne ex_bad
            jmp do_movspr
ex_bad:     jmp s_snerr

; the extensions must be unlocked before BASIC 7.1 touches $D040-$D0FF, otherwise
; the writes would land in the mirrored stock registers
chk_unlocked:
            lda vicx_key
            cmp #$FE
            bne cu_fc
            rts
cu_fc:      jmp s_fcerr

; -----------------------------------------------------------------------------
;  Function dispatcher. In: A = second token byte, FAC = first argument,
;  txtptr after the argument (on ')'). Out: FAC = result.
; -----------------------------------------------------------------------------
rom_fn:     cmp #FN_RPALETTE
            bne fn_1
            jmp do_rpalette
fn_1:       cmp #FN_RSPRITE
            bne fn_2
            jmp do_rsprite
fn_2:       cmp #FN_RSPPOS
            bne fn_3
            jmp do_rsppos
fn_3:       cmp #FN_BUMP
            bne ex_bad
            jmp do_bump

; -----------------------------------------------------------------------------
;  PALETTE c,hue,lum   PALETTE ON   PALETTE OFF   PALETTE RESET
; -----------------------------------------------------------------------------
do_palette: jsr chk_unlocked
            jsr s_chrget              ; first character after PALETTE
            bne pa_1
            jmp s_snerr               ; PALETTE alone
pa_1:       cmp #tk_on
            bne pa_2
            lda #1
            sta vicx_palen
            jmp s_chrget              ; past ON
pa_2:       cmp #tk_esc_cmd
            bne pa_3
            jsr s_chrget              ; second byte
            cmp #tk_off
            beq pa_off
            jmp s_snerr
pa_off:     lda #0
            sta vicx_palen
            jmp s_chrget              ; past OFF

pa_3:       cmp #'R'                  ; RESET?
            bne pa_num
            lda txtptr                ; remember the position, R may start a variable
            sta savtxt
            lda txtptr+1
            sta savtxt+1
            ldx #0
pa_rs:      stx tmpx
            jsr s_chrget
            ldx tmpx
            cmp resetrest,x
            bne pa_notrs
            inx
            cpx #4
            bne pa_rs
            jsr s_chrget              ; past RESET
            ldx #15
pa_rs2:     lda defpal,x
            sta vicx_pal,x
            dex
            bpl pa_rs2
            lda #0
            sta vicx_palen
            rts
pa_notrs:   lda savtxt                ; not RESET: back to the R
            sta txtptr
            lda savtxt+1
            sta txtptr+1
            jsr s_chrgot

pa_num:     jsr s_getbyt              ; entry number
            cpx #16
            bcs pa_fc
            stx tmpc
            jsr s_combyt              ; hue
            cpx #16
            bcs pa_fc
            txa
            asl a
            asl a
            asl a
            asl a
            sta tmph
            jsr s_combyt              ; luminance
            cpx #16
            bcs pa_fc
            txa
            ora tmph
            ldx tmpc
            sta vicx_pal,x
            rts
pa_fc:      jmp s_fcerr

resetrest:  .byte "ESET"

; same values as the VIC-IIx reset palette
defpal:     .byte $00,$0F,$14,$8B,$E6,$78,$B3,$4D,$26,$33,$18,$04,$07,$6D,$B8,$0A

; -----------------------------------------------------------------------------
;  RPALETTE(c) - hue * 16 + luminance of palette entry c
; -----------------------------------------------------------------------------
do_rpalette:
            jsr chk_unlocked
            jsr s_conint              ; argument -> X
            cpx #16
            bcs pa_fc
            lda vicx_pal,x
            sta tmpv
            jsr s_chkcls              ; ')'
            ldy tmpv
            jmp s_sngflt              ; Y -> FAC

; -----------------------------------------------------------------------------
;  SPRITE n [,e [,c [,p [,x [,y [,r]]]]]]   n = 1-24
;  Same parameters and behaviour as BASIC 7.0's SPRITE (e on/off, c colour
;  1-16, p background priority, x/y expansion, r multicolour).
; -----------------------------------------------------------------------------
do_sprite:  jsr spr_number            ; sprite 0-23 in spr_n, group in X
            txa
            asl a                     ; group * 6 = index into sprregs
            sta tmpc
            asl a
            adc tmpc
            sta spr_reg

            jsr s_optbyt              ; enable
            bcc sp_20
            ldy #0
            jsr spr_bit
sp_20:      jsr s_optbyt              ; colour 1-16
            bcc sp_30
            dex
            cpx #16
            bcs sp_fc
            stx tmpc
            ldy spr_reg
            lda sprregs+1,y           ; colour register of sprite 0 of the group
            clc
            adc spr_i
            tax
            lda tmpc
            sta vic,x
sp_30:      jsr s_optbyt              ; priority
            bcc sp_40
            ldy #2
            jsr spr_bit
sp_40:      jsr s_optbyt              ; x expansion
            bcc sp_50
            ldy #3
            jsr spr_bit
sp_50:      jsr s_optbyt              ; y expansion
            bcc sp_60
            ldy #4
            jsr spr_bit
sp_60:      jsr s_optbyt              ; multicolour
            bcc sp_70
            ldy #5
            jsr spr_bit
sp_70:      rts
sp_fc:      jmp s_fcerr

; set or clear the sprite's bit in a VIC register.
; In: X = 0 or 1, Y = field (0 enable, 2 priority, 3 x-exp, 4 y-exp, 5 multicolour)
spr_bit:    txa
            lsr a                     ; C = new bit value
            bne sp_fc                 ; only 0 or 1
            php
            tya
            clc
            adc spr_reg
            tay
            ldx sprregs,y             ; register (low byte, $D0xx)
            lda vic,x
            ora spr_mask
            plp
            bcs sb_1
            eor spr_mask
sb_1:       sta vic,x
            rts

; read the sprite number (1-24) at the current position.
; Out: spr_n = 0-23, spr_i = 0-7, spr_mask = bit, X = group (0-2)
spr_number: jsr s_chrget
            jsr s_getbyt
            dex
            cpx #24
            bcs sp_fc
            stx spr_n
            txa
            and #7
            sta spr_i
            tay
            lda bitmask,y
            sta spr_mask
            txa
            lsr a
            lsr a
            lsr a
            tax
            beq sn_ok                 ; sprites 1-8: stock registers
            jsr chk_unlocked
sn_ok:      rts

; per group: enable, colour of sprite 0, priority, x-exp, y-exp, multicolour
sprregs:    .byte $15, $27, $1B, $1D, $17, $1C     ; sprites 1-8   (stock)
            .byte $51, $58, $53, $55, $52, $54     ; sprites 9-16  ($D040 bank)
            .byte $91, $98, $93, $95, $92, $94     ; sprites 17-24 ($D080 bank)
bitmask:    .byte $01, $02, $04, $08, $10, $20, $40, $80

; -----------------------------------------------------------------------------
;  SPRPTR n,block - choose the 64-byte shape block (0-255) of sprite n (1-24)
;  The pointer is written where the VIC-IIx fetches it: after the screen
;  (screen + $3F8/$3F0/$3E8), at the end of the 2K map in wide mode, or in the
;  pointer page when PTRSEP is set. RAM bank 0 only.
; -----------------------------------------------------------------------------
do_sprptr:  jsr spr_number
            stx tmpc                  ; group
            jsr s_combyt
            stx spr_blk

            ; low byte: $F8 - 8 * group + sprite in group
            lda tmpc
            asl a
            asl a
            asl a
            sta tmph
            lda #$F8
            sec
            sbc tmph
            clc
            adc spr_i
            sta pokeaddr

            ; high byte within the VIC's 16K bank
            lda vicx_key
            cmp #$FE
            bne pp_screen             ; locked: always after the screen
            lda vicx_ctrl
            and #$02
            beq pp_wide
            lda vicx_ppage            ; PTRSEP: own page
            and #$3F
            jmp pp_bank
pp_wide:    lda vicx_ctrl
            and #$01
            beq pp_screen
            lda vic+$18               ; WIDE: (VM & $E) * 4 + 7  -> $x7F8
            lsr a
            lsr a
            and #$38
            ora #$07
            jmp pp_bank
pp_screen:  lda vic+$18               ; VM * 4 + 3  -> screen + $3F8
            lsr a
            lsr a
            and #$3C
            ora #$03
pp_bank:    sta tmph
            lda cia2_pra              ; VIC bank = 3 - (DD00 & 3)
            and #$03
            eor #$03
            lsr a                     ; bank * $40
            ror a
            ror a
            ora tmph
            sta pokeaddr+1
            lda spr_blk
            jmp r_poke0

; =============================================================================
;  Stage 6: six-voice sound. Voices 1-3 on the SID at $D400, voices 4-6 on the
;  SID at $D420 (the layout of the C65's BASIC 10). BASIC 7.1 runs its own
;  sound engine for all six voices (same algorithms as BASIC 7.0), driven from
;  the IRQ hook r_irq. ENVELOPE, TEMPO and the current note length and octave
;  are shared with BASIC.
; =============================================================================

offtab6:    .byte 0, 7, 14, SID2, SID2+7, SID2+14     ; SID register offset per voice
vbit6:      .byte 1, 2, 4, 1, 2, 4                     ; filter routing bit per voice
fofs6:      .byte 0, 0, 0, 5, 5, 5                     ; fil6 offset per voice
sofs6:      .byte 0, 0, 0, SID2, SID2, SID2            ; SID base offset per voice
p_notes:    .byte "WHQIS"                              ; whole ... sixteenth
p_mutabl:   .byte "VOTXUM"
p_rbits:    .byte $80, $40, $20, $10, $08              ; V O T X U

; -----------------------------------------------------------------------------
;  SID6 ON / SID6 OFF - take over SOUND, PLAY, VOL and FILTER when typed
; -----------------------------------------------------------------------------
do_sid6:    jsr s_chrget
            cmp #tk_on
            bne s6_1
            lda #1
            sta s6_on
            jmp s_chrget              ; past ON
s6_1:       cmp #tk_esc_cmd
            bne s6_bad
            jsr s_chrget
            cmp #tk_off
            bne s6_bad
            lda #0
            sta s6_on
            jmp s_chrget              ; past OFF
s6_bad:     jmp s_snerr

; -----------------------------------------------------------------------------
;  SOUND v, f, d [,[dir] [,[m] [,[s] [,[w] [,p] ]]]]     v = 1-6
; -----------------------------------------------------------------------------
do_sound:   jsr s_chrget
            jsr s_getbyt              ; voice
            dex
            cpx #6
            bcc so_1
so_fc:      jmp s_fcerr
so_1:       stx snd_v
            jsr s_comwrd              ; frequency
            sty t_max_lo
            sta t_max_hi
            sty t_freq_lo
            sta t_freq_hi
            jsr s_comwrd              ; duration in jiffies
            cmp #$80
            bcs so_fc
            sty t_time_lo
            sta t_time_hi
            jsr s_optzer              ; sweep direction 0 up, 1 down, 2 oscillate
            cpx #3
            bcs so_fc
            stx t_dir
            jsr s_optwrd              ; minimum frequency
            sty t_min_lo
            sta t_min_hi
            jsr s_optwrd              ; step
            sta tmph
            lda t_dir
            and #1
            beq so_up                 ; down: step as two's complement
            tya
            eor #$FF
            clc
            adc #1
            tay
            lda tmph
            eor #$FF
            adc #0
            sta tmph
so_up:      sty t_step_lo
            lda tmph
            sta t_step_hi
            ldx #2                    ; waveform, default square
            jsr s_optbx
            cpx #4
            bcs so_fc
            lda b_sbits+4,x
            ora #1                    ; gate
            sta t_wave
            jsr s_optwrd              ; pulse width
            bcs so_pw
            lda #8
            ldy #0
so_pw:      cmp #16
            bcs so_fc
            sty t_pw_lo
            sta t_pw_hi

            lda t_time_lo
            ora t_time_hi
            beq so_time               ; duration 0: stop the voice now

            ldx snd_v                 ; wait until PLAY and SOUND are done with it
            txa
            asl a
            tay
so_w1:      lda m_voices+1,y
            bpl so_w1
so_w2:      lda s_time_hi,x
            bpl so_w2

            ldy #0                    ; max, min, direction, step, frequency
so_cp:      lda t_max_lo,y
            sta s_max_lo,x
            txa
            clc
            adc #6
            tax
            iny
            cpy #9
            bne so_cp

            ldx snd_v
            ldy offtab6,x
            lda #$08                  ; gate off
            sta sid+4,y
            lda #0
            sta sid+5,y
            lda #$F0
            sta sid+6,y
            ldx #0                    ; frequency, pulse width, waveform + gate
so_sid:     lda t_freq_lo,x
            sta sid,y
            iny
            inx
            cpx #5
            bne so_sid

so_time:    ldx snd_v
            ldy t_time_lo
            lda t_time_hi
            sei
            sta s_time_hi,x
            tya
            sta s_time_lo,x
            cli
            rts

; -----------------------------------------------------------------------------
;  VOL a [,b]     a = SID 1, b = SID 2 (default: both a), 0-15
; -----------------------------------------------------------------------------
do_vol:     jsr s_chrget
            jsr s_getbyt
            cpx #16
            bcs vo_fc
            stx tmpc
            jsr s_optbx              ; X unchanged if there is no second value
            cpx #16
            bcs vo_fc
            stx tmpv
            ldx #0
            ldy #0
            lda tmpc
            jsr vo_set
            ldx #5
            ldy #SID2
            lda tmpv
vo_set:     sta tmph
            lda fil6+3,x              ; PLAY's record of type/volume
            and #$F0
            ora tmph
            sta fil6+3,x
            lda fil6+4,x
            and #$F0
            ora tmph
            sta fil6+4,x
            sta sid+24,y
            rts
vo_fc:      jmp s_fcerr

; -----------------------------------------------------------------------------
;  FILTER [freq] [,lp] [,bp] [,hp] [,res] - same as BASIC 7.0, for both SIDs.
;  Cut-off, resonance and type are shared; each SID keeps its own routing
;  (PLAY "Xn") and volume. Takes effect with PLAY "X1", as in BASIC.
; -----------------------------------------------------------------------------
do_filter:  jsr s_chrget
            pha
            ldy #3
fi_1:       lda fil6,y
            sta f_sav,y
            dey
            bpl fi_1
            pla
            cmp #','
            beq fi_20                 ; no frequency
            jsr s_getwrd
            cmp #8
            bcc fi_10
fi_fc0:     jmp s_fcerr               ; > 2047
fi_10:
            sty f_sav
            sty f_sav+1
            lsr a
            ror f_sav+1
            lsr a
            ror f_sav+1
            lsr a
            ror f_sav+1
fi_20:      lda #$10
            sta f_flg
fi_30:      jsr s_optbx              ; low pass, band pass, high pass on/off
            bcc fi_50
            cpx #1
            bcc fi_35
            beq fi_35
            jmp s_fcerr
fi_35:      lda f_sav+3
            ora f_flg
            bcs fi_40
            eor f_flg
fi_40:      sta f_sav+3
fi_50:      asl f_flg
            bpl fi_30
            jsr s_optbx              ; resonance
            bcc fi_70
            cpx #16
            bcs fi_fc0
            txa
            asl a
            asl a
            asl a
            asl a
            sta tmph
            lda f_sav+2
            and #$0F
            ora tmph
            sta f_sav+2
fi_70:      ldy #3
fi_80:      lda f_sav,y               ; SID 1
            sta fil6,y
            dey
            bpl fi_80
            lda fil6                  ; SID 2: same cut-off ...
            sta fil6+5
            lda fil6+1
            sta fil6+6
            lda fil6+2                ; ... resonance, own routing
            and #$F0
            sta tmph
            lda fil6+7
            and #$0F
            ora tmph
            sta fil6+7
            lda fil6+3                ; ... filter type, own volume
            and #$F0
            sta tmph
            lda fil6+8
            and #$0F
            ora tmph
            sta fil6+8
            rts
fi_fc:      jmp s_fcerr

; -----------------------------------------------------------------------------
;  PLAY "string"   V1-V6, O, T, U, X, M, notes, lengths, R, ., #, $
; -----------------------------------------------------------------------------
do_play:    jsr s_chrget
            jsr s_frmstr              ; A = length, (index1) -> string
            sta p_len
            jsr p_clrflags            ; returns A = 0
            sta p_pos
pl_loop:    ldy p_pos
            cpy p_len
            beq pl_done
            jsr s_indin1
            jsr p_char
            inc p_pos
            bne pl_loop
pl_done:    rts

p_char:     cmp #' '
            bne pc_1
            rts
pc_1:       cmp #'A'
            bcc pc_2
            cmp #'H'
            bcs pc_2
            jmp p_note
pc_2:       ldx #4
pc_3:       cmp p_notes,x
            bne pc_4
            jmp p_length
pc_4:       dex
            bpl pc_3
            cmp #'R'
            bne pc_5
            jmp p_rest
pc_5:       cmp #'.'
            bne pc_6
            sta p_dnote
            rts
pc_6:       ldx #5
pc_7:       cmp p_mutabl,x
            bne pc_8
            jmp p_command
pc_8:       dex
            bpl pc_7
            cmp #'#'
            bne pc_9
            lda #1
            sta p_sharp
            rts
pc_9:       cmp #'$'
            bne pc_10
            lda #$FF
            sta p_sharp
            rts
pc_10:      sec
            sbc #'0'
            cmp #10
            bcc pc_11
            jmp p_bad
pc_11:      asl p_flag                ; which command is waiting for its digit?
            bcs p_setvoice
            asl p_flag
            bcs p_setoct
            asl p_flag
            bcs p_setenv
            asl p_flag
            bcc p_setvol
            jmp p_setfilter

p_bad:      jsr p_clrflag
            jmp s_fcerr

p_setvoice: tax
            dex
            cpx #6
            bcs p_bad
            stx p_voice
            jmp p_clrflag
p_setoct:   cmp #7
            bcs p_bad
            sta octave
            jmp p_clrflag
p_setenv:   tax
            jsr p_env
            jmp p_clrflag

; envelope X (0-9) for voice p_voice
p_env:      ldy p_voice
            lda wavtab,x
            sta m_wave,y
            lda offtab6,y
            tay
            lda atktab,x
            sta sid+5,y
            lda sustab,x
            sta sid+6,y
            lda pulslw,x
            sta sid+2,y
            lda pulshi,x
            sta sid+3,y
            rts

; U0-U9: volume of the current voice's SID
p_setvol:   tay
            ldx p_voice
            lda fofs6,x
            tax
            lda fil6+3,x
            and #$F0
            ora b_voltab,y
            sta fil6+3,x
            lda fil6+4,x
            and #$F0
            ora b_voltab,y
            pha
            ldy p_voice
            lda sofs6,y
            tay
            pla
            sta sid+24,y
            jmp p_clrflag

; X0/X1: current voice through its SID's filter
p_setfilter:
            cmp #2
            bcs p_bad
            lsr a                     ; C = on
            php
            ldy p_voice
            tya
            asl a
            tax
pf_1:       lda m_voices+1,x          ; wait while the voice plays
            bpl pf_1
            ldx fofs6,y
            lda vbit6,y
            ora fil6+2,x
            plp
            bcs pf_2
            eor vbit6,y
pf_2:       sta fil6+2,x
            lda fil6+3,x
            sta fil6+4,x
            lda sofs6,y
            tay
            lda fil6,x
            sta sid+21,y
            lda fil6+1,x
            sta sid+22,y
            lda fil6+2,x
            sta sid+23,y
            lda fil6+3,x
            sta sid+24,y
p_clrflag:  lda #0
            sta p_flag
            rts

p_length:   ldy #<BEATS
            sty ntime
            ldy #>BEATS
            sty ntime+1
pn_l1:      dex
            bmi pn_l2
            lsr ntime+1
            ror ntime
            jmp pn_l1
pn_l2:      rts

p_command:  cmp #'M'
            beq p_measure
            lda p_rbits,x
            sta p_flag
            rts
p_measure:  ldy #11                   ; wait until all six voices are done
pm_1:       lda m_voices,y
            bpl pm_1
            dey
            dey
            bpl pm_1
            rts

p_note:     sec
            sbc #'A'
            tax
            lda b_scalen,x            ; note 0-11
            tax
            lda #6
            sec
            sbc octave
            tay
            txa
            clc
            adc p_sharp
            bpl pn_1
            lda #11                   ; C flat
            iny
pn_1:       cmp #12
            bcc pn_2
            lda #0                    ; B sharp
            dey
pn_2:       tax
            lda b_scalel,x
            sta pitch
            jsr play_pal              ; A = high byte (PAL/NTSC), may set pitch
pn_3:       dey
            bmi pn_4
            lsr a
            ror pitch
            jmp pn_3
pn_4:       sta pitch+1
            lda #0                    ; note
            beq p_rest2
p_rest:     lda #$FF                  ; rest
p_rest2:    pha
            ldx p_voice
            txa
            asl a
            tay
pr_1:       lda m_voices+1,y          ; wait for the previous note
            bpl pr_1
            lda ntime
            sta m_voices,y
            lda ntime+1
            sta m_voices+1,y
            lda p_dnote
            beq pr_2
            lda ntime+1               ; dotted: 1.5 x length
            lsr a
            pha
            lda ntime
            ror a
            clc
            adc m_voices,y
            sta m_voices,y
            pla
            adc m_voices+1,y
            sta m_voices+1,y
pr_2:       pla
            bmi p_clrflags
            ldy offtab6,x
            lda pitch
            sta sid,y
            lda pitch+1
            sta sid+1,y
            lda #$08                  ; restart the envelope
            sta sid+4,y
            lda m_wave,x              ; waveform + gate
            sta sid+4,y
p_clrflags: lda #0
            sta p_sharp
            sta p_dnote
            rts

; -----------------------------------------------------------------------------
;  Initialise: all six voices silent, both volumes 15, piano envelope.
;  Called at start-up and after RUN/STOP + RESTORE.
; -----------------------------------------------------------------------------
snd_init:   lda #0
            ldy #5
si_1:       ldx offtab6,y
            sta sid+4,x               ; gates off
            dey
            bpl si_1
            ldx #9
si_2:       sta fil6,x
            dex
            bpl si_2
            sta p_flag
            sta p_voice
            jsr p_clrflags
            lda #$0F
            sta fil6+3
            sta fil6+4
            sta fil6+8
            sta fil6+9
            sta sid+24
            sta sid+SID2+24
            lda #$FF
            ldy #5
si_3:       sta s_time_hi,y
            dey
            bpl si_3
            ldy #11
si_4:       sta m_voices,y
            dey
            bpl si_4
            lda #5
            sta p_voice
si_5:       ldx #0                    ; envelope 0 (piano)
            jsr p_env
            dec p_voice
            bpl si_5
            inc p_voice
            rts

; -----------------------------------------------------------------------------
;  Once per jiffy (from r_irq): PLAY note counters and SOUND sweeps/durations.
;  Same algorithm as BASIC 7.0's IRQ, for six voices.
; -----------------------------------------------------------------------------
snd_irq:    ldx #0
mi_1:       lda m_voices+1,x
            bmi mi_2                  ; voice not playing
            lda m_voices,x
            sec
            sbc tempo_rate
            sta m_voices,x
            bcs mi_2
            lda m_voices+1,x
            sbc #0
            sta m_voices+1,x
            bcs mi_2
            txa                       ; note over: gate off
            lsr a
            tay
            lda m_wave,y
            and #$FE
            pha
            lda offtab6,y
            tay
            pla
            sta sid+4,y
mi_2:       inx
            inx
            cpx #12
            bne mi_1

            ldy #5
sq_1:       lda s_time_hi,y           ; active if bit 7 clear
            bpl sq_3
sq_2:       dey
            bpl sq_1
            rts
sq_3:       clc                       ; frequency += step
            lda s_freq_lo,y
            adc s_step_lo,y
            sta s_freq_lo,y
            lda s_freq_hi,y
            adc s_step_hi,y
            sta s_freq_hi,y
            lda s_dir,y
            tax
            and #1
            beq sq_up
            bcc sq_4                  ; down: underflow
            sec
            lda s_freq_lo,y
            sbc s_min_lo,y
            lda s_freq_hi,y
            sbc s_min_hi,y
            bcs sq_set                ; still above the minimum
sq_4:       cpx #2
            bcc sq_5
            jsr sq_neg                ; oscillate: turn round, go up
            lda #%10
            sta s_dir,y
            bne sq_min
sq_5:       lda s_max_lo,y            ; down: restart at the maximum
            sta s_freq_lo,y
            lda s_max_hi,y
            sta s_freq_hi,y
            jmp sq_set
sq_up:      bcs sq_6                  ; overflow
            lda s_freq_hi,y
            cmp s_max_hi,y
            bcc sq_set
            bne sq_6
            lda s_freq_lo,y
            cmp s_max_lo,y
            bcc sq_set
            beq sq_set
sq_6:       cpx #2
            bcc sq_min
            jsr sq_neg                ; oscillate: turn round, go down
            lda #%11
            sta s_dir,y
            bne sq_5
sq_min:     lda s_min_lo,y            ; up: restart at the minimum
            sta s_freq_lo,y
            lda s_min_hi,y
            sta s_freq_hi,y
sq_set:     ldx offtab6,y
            lda s_freq_lo,y
            sta sid,x
            lda s_freq_hi,y
            sta sid+1,x
            lda s_time_lo,y           ; duration - 1
            bne sq_7
            lda s_time_hi,y
            sec
            sbc #1
            sta s_time_hi,y
sq_7:       lda s_time_lo,y
            sec
            sbc #1
            sta s_time_lo,y
            lda s_time_hi,y
            bpl sq_8
            lda #$08                  ; time is up: gate off
            ldx offtab6,y
            sta sid+4,x
sq_8:       jmp sq_2

sq_neg:     lda s_step_lo,y
            eor #$FF
            clc
            adc #1
            sta s_step_lo,y
            lda s_step_hi,y
            eor #$FF
            adc #0
            sta s_step_hi,y
            rts

; =============================================================================
;  Stage 4: MOVSPR, RSPRITE(), RSPPOS(), BUMP() for sprites 1-24.
;  Sprites 1-8 use BASIC 7.0's own data (vic_save, sprite_data). For sprites
;  9-24, BASIC 7.1 keeps the same 11-byte motion record per sprite (m_data)
;  and moves them in its IRQ hook with BASIC's algorithm. MOVSPR for 9-24
;  lets BASIC's own MOVSPR code do the parsing and maths: the sprite's
;  position and motion record are swapped into the BASIC slot of the sprite
;  that shares its hardware slot (n-1 AND 7), BASIC's interrupt is held off,
;  and afterwards everything is swapped back.
; =============================================================================

m_off:      .byte 0, 11, 22, 33, 44, 55, 66, 77, 88, 99, 110, 121, 132, 143, 154, 165

; -----------------------------------------------------------------------------
;  MOVSPR n, ...    n = 1-24, all forms of BASIC 7.0's MOVSPR
; -----------------------------------------------------------------------------
do_movspr:  jsr s_chrget
            jsr s_getbyt              ; sprite number
            dex
            cpx #24
            bcc mv_1
mv_fc:      jmp s_fcerr
mv_1:       cpx #8
            bcs mv_ext
            stx z_p_temp_1            ; sprites 1-8: BASIC's own MOVSPR
            lda #<movspr_cont
            ldx #>movspr_cont
            jmp syscall_ax

mv_ext:     stx mv_n
            jsr chk_unlocked
            lda mv_n
            and #7
            sta mv_k                  ; BASIC slot that shares the hardware slot
            tay
            lda bitmask,y
            sta mv_bit
            lda mv_n
            sec
            sbc #8
            sta mv_mi                 ; 0-15: index into m_data
            lda mv_n
            and #$18                  ; 8-15 -> $40, 16-23 -> $80
            asl a
            asl a
            asl a
            sta mv_base
            lda mv_k
            asl a
            clc
            adc mv_base
            sta mv_reg                ; X register offset (Y is +1)

            sei
            inc irq_wrap_flag         ; hold off BASIC's interrupt (sprite moves)
            jsr mv_swapin
            lda ierror                ; on an error: swap back, then BASIC's handler
            sta old_ierror
            lda ierror+1
            sta old_ierror+1
            lda #<r_moverr
            sta ierror
            lda #>r_moverr
            sta ierror+1
            lda mv_k
            sta z_p_temp_1
            lda #<movspr_cont         ; BASIC parses the rest and does the maths
            ldx #>movspr_cont
            jsr syscall_ax
            sei
            jsr mv_swapout
            cli
            rts

; put sprite mv_n's position and motion record into BASIC slot mv_k
mv_swapin:  lda mv_k                  ; save BASIC's slot
            asl a
            tay
            lda vic_save,y
            sta mv_save
            lda vic_save+1,y
            sta mv_save+1
            lda vic_save+16
            sta mv_save+2
            ldx mv_k
            ldy m_off,x
            ldx #0
ms_1:       lda sprite_data,y
            sta mv_save+3,x
            iny
            inx
            cpx #11
            bne ms_1

            lda mv_k                  ; position of sprite n
            asl a
            tay
            ldx mv_reg
            lda vic,x
            sta vic_save,y
            lda vic+1,x
            sta vic_save+1,y
            lda vic_save+16
            ora mv_bit
            eor mv_bit
            sta mv_tmp
            ldx mv_base
            lda vic+$10,x
            and mv_bit
            ora mv_tmp
            sta vic_save+16

            ldx mv_mi                 ; motion record of sprite n
            lda m_off,x
            tax
            ldy mv_k
            lda m_off,y
            tay
            lda #11
            sta mv_tmp
ms_2:       lda m_data,x
            sta sprite_data,y
            inx
            iny
            dec mv_tmp
            bne ms_2
            lda #1
            sta mv_active
            rts

; take sprite mv_n's new state out of BASIC slot mv_k, restore the slot,
; the error vector and BASIC's interrupt
mv_swapout: lda mv_active
            bne mo_0
            rts
mo_0:       lda mv_k
            asl a
            tay
            ldx mv_reg
            lda vic_save,y
            sta vic,x
            lda vic_save+1,y
            sta vic+1,x
            ldx mv_base
            lda vic+$10,x
            ora mv_bit
            eor mv_bit
            sta mv_tmp
            lda vic_save+16
            and mv_bit
            ora mv_tmp
            sta vic+$10,x

            ldy mv_mi
            lda m_off,y
            tay
            ldx mv_k
            lda m_off,x
            tax
            lda #11
            sta mv_tmp
mo_1:       lda sprite_data,x
            sta m_data,y
            inx
            iny
            dec mv_tmp
            bne mo_1

            lda mv_k                  ; BASIC's slot back
            asl a
            tay
            lda mv_save
            sta vic_save,y
            lda mv_save+1
            sta vic_save+1,y
            lda mv_save+2
            sta vic_save+16
            ldx mv_k
            ldy m_off,x
            ldx #0
mo_2:       lda mv_save+3,x
            sta sprite_data,y
            iny
            inx
            cpx #11
            bne mo_2

            lda old_ierror
            sta ierror
            lda old_ierror+1
            sta ierror+1
            dec irq_wrap_flag
            lda #0
            sta mv_active
            rts

; -----------------------------------------------------------------------------
;  RSPPOS(n, a)   n = 1-24; a = 0 X position, 1 Y position, 2 speed
; -----------------------------------------------------------------------------
do_rsppos:  jsr s_conint              ; sprite number (pre-evaluated)
            dex
            cpx #24
            bcs rp_fc
            stx fn_n
            jsr s_chkcom
            jsr s_getbyt
            stx fn_a
            jsr s_chkcls
            ldx fn_a
            cpx #3
            bcs rp_fc
            ldx fn_n
            txa
            and #7
            tay
            lda bitmask,y
            sta fn_bit
            cpx #8
            bcs rp_ext
            lda mv_active             ; sprite 1-8 whose slot holds a sprite
            beq rp_basic              ; being moved by MOVSPR right now?
            cpx mv_k
            bne rp_basic
            lda mv_save               ; ... then its own values are saved here
            sta fn_x
            lda mv_save+1
            sta fn_y
            lda mv_save+2
            sta fn_msb
            lda mv_save+3
            sta fn_spd
            jmp rp_out
rp_basic:   txa                       ; sprites 1-8: BASIC's copies
            asl a
            tay
            sei
            lda vic_save,y
            sta fn_x
            lda vic_save+1,y
            sta fn_y
            lda vic_save+16
            sta fn_msb
            cli
            ldy m_off,x
            lda sprite_data,y
            sta fn_spd
            jmp rp_out
rp_fc:      jmp s_fcerr
rp_ext:     jsr chk_unlocked          ; sprites 9-24: the registers
            txa
            and #$18
            asl a
            asl a
            asl a
            sta fn_base
            txa
            and #7
            asl a
            clc
            adc fn_base
            tay
            sei
            lda vic,y
            sta fn_x
            lda vic+1,y
            sta fn_y
            ldy fn_base
            lda vic+$10,y
            sta fn_msb
            cli
            txa
            sec
            sbc #8
            tay
            lda m_off,y
            tay
            lda m_data,y
            sta fn_spd
rp_out:     lda fn_a
            beq rp_x
            cmp #1
            beq rp_y
            ldy fn_spd                ; speed
            jmp s_sngflt
rp_y:       ldy fn_y
            jmp s_sngflt
rp_x:       lda fn_msb
            and fn_bit
            beq rp_x1
            lda #1
rp_x1:      ldy fn_x
            jmp s_nosflt              ; Y low, A high

; -----------------------------------------------------------------------------
;  RSPRITE(n, a)   n = 1-24; a = 0 on, 1 colour, 2 priority, 3 x-expand,
;                  4 y-expand, 5 multicolour
; -----------------------------------------------------------------------------
do_rsprite: jsr s_conint
            dex
            cpx #24
            bcc rs_n
rs_fc:      jmp s_fcerr
rs_n:
            stx fn_n
            jsr s_chkcom
            jsr s_getbyt
            stx fn_a
            jsr s_chkcls
            ldx fn_a
            cpx #6
            bcs rs_fc
            lda fn_n
            cmp #8
            bcc rs_1
            jsr chk_unlocked
rs_1:       lda fn_n
            and #7
            sta fn_bit                ; sprite within its group (0-7)
            lda fn_n
            lsr a
            lsr a
            lsr a                     ; group 0-2
            sta fn_base
            asl a                     ; group * 6 -> sprregs
            adc fn_base
            asl a
            adc fn_a
            tay
            lda sprregs,y             ; register of this attribute
            ldx fn_a
            cpx #1
            bne rs_bit
            clc                       ; colour: register + sprite, 1-16
            adc fn_bit
            tax
            lda vic,x
            and #$0F
            tay
            iny
            jmp s_sngflt
rs_bit:     tax
            ldy fn_bit
            lda bitmask,y
            and vic,x
            beq rs_0
            lda #1
rs_0:       tay
            jmp s_sngflt

; -----------------------------------------------------------------------------
;  BUMP(n)   1/2: sprites 1-8 (BASIC 7.0), 3/4: sprites 9-16, 5/6: sprites
;  17-24; odd = sprite-sprite, even = sprite-background. Bit k = k-th sprite
;  of the group. Reading resets the value.
; -----------------------------------------------------------------------------
do_bump:    jsr s_chkcls
            jsr s_conint
            dex
            cpx #6
            bcc bp_n
            jmp s_fcerr
bp_n:
            cpx #2
            bcs bp_ext
            sei                       ; sprites 1-8: collected by BASIC
            ldy vic_save+17,x
            lda #0
            sta vic_save+17,x
            cli
            jmp s_sngflt
bp_ext:     sei                       ; sprites 9-24: collected by r_irq
            ldy col9-2,x
            lda #0
            sta col9-2,x
            cli
            jmp s_sngflt

; -----------------------------------------------------------------------------
;  Once per jiffy (from r_irq): move sprites 9-24 that have a speed set,
;  with BASIC 7.0's algorithm (see BASIC's IRQ code).
; -----------------------------------------------------------------------------
spr_irq:    lda vicx_key
            cmp #$FE
            bne sm_rts
            ldy #15
sm_next:    sty sm_i
            tya
            and #7
            tax
            lda bitmask,x
            sta sm_bit
            tya
            and #8                    ; 0-7 -> $40, 8-15 -> $80
            asl a
            asl a
            asl a
            clc
            adc #$40
            sta sm_base
            tax
            lda vic+$11,x             ; enabled?
            and sm_bit
            beq sm_skip
            ldx sm_i
            lda m_off,x
            tax
            lda m_data,x              ; speed
            beq sm_skip
            sta m_data+1,x            ; step counter
            lda sm_i
            and #7
            asl a
            adc sm_base
            tay                       ; X register offset
sm_loop:    lda m_data+2,x            ; angle sign
            sec
            sbc #1                    ; cosine for Y
            inx
            inx
            iny
            jsr sm_sub                ; Y position
            dex
            dex
            dey
            lda m_data+2,x
            jsr sm_sub                ; X position
            bcc sm_nc
            sty sm_y                  ; X wrapped: flip bit 8
            ldy sm_base
            lda vic+$10,y
            eor sm_bit
            sta vic+$10,y
            ldy sm_y
sm_nc:      dec m_data+1,x
            bne sm_loop
sm_skip:    ldy sm_i
            dey
            bpl sm_next
sm_rts:     rts

sm_sub:     pha
            clc
            lda m_data+3,x
            adc m_data+7,x
            sta m_data+7,x
            lda m_data+4,x
            adc m_data+8,x
            sta m_data+8,x
            pla
            bcc sm_s3                 ; no step this time
            lsr a
            lsr a                     ; C = direction
            lda vic,y
            bcs sm_s1
            adc #1
            jmp sm_s2
sm_s1:      sbc #1
            cmp #$FF                  ; C = 1 on underflow
sm_s2:      sta vic,y
sm_s3:      rts

; stop sprites 9-24 (start-up, RUN/STOP + RESTORE)
spr_stop:   lda #0
            ldx #175
ss_1:       sta m_data,x
            dex
            bne ss_1
            sta m_data
            ldx #3
ss_2:       sta col9,x
            dex
            bpl ss_2
            sta mv_active
            rts

; jiffy tick: sound, then sprite movement
tick:       jsr snd_irq
            jmp spr_irq

; =============================================================================
;  RAM part, copied to $1800 at start-up (max. 1K)
; =============================================================================
code_end:
            .assert code_end <= $D000, "code runs into the I/O area at $D000"

; The RAM part is stored at $E000 ($D000-$DFFF is hidden by I/O).
            .org $E000
ramimage:
            .rorg $1800

; SYSCALL: call (sysvec) in the normal BASIC memory map (bank 15) through the
; Kernal's JSRFAR, then switch back to the map that was active before.
; JSRFAR's return code lives in common RAM, so this also works for BASIC
; routines that return with RAM 1 switched in (FRMSTR, for example), where
; this RAM at $1800 would be invisible. A/X/Y pass through in both
; directions, flags are returned from the called routine.
syscall:    sta tmpa
            php
            pla
            sta fr_s                  ; flags for the call
            lda mmucr
            pha
            lda #CFG_SYS
            sta mmucr
            lda #15                   ; bank 15: Kernal, BASIC, RAM 0, I/O
            sta fr_bank
            lda sysvec+1
            sta fr_pchi
            lda sysvec
            sta fr_pclo
            lda tmpa
            sta fr_a
            stx fr_x
            sty fr_y
            jsr jsrfar
            pla
            sta mmucr
            ldx fr_x
            ldy fr_y
            lda fr_s
            pha
            lda fr_a
            plp
            rts

; character out through the Kernal (used during start-up)
r_chrout:   sta tmpa
            lda #<chrout
            sta sysvec
            lda #>chrout
            sta sysvec+1
            lda tmpa
            jmp syscall

; store A at pokeaddr in RAM bank 0, even under ROM or I/O
; (pokeaddr is the operand of the STA below)
r_poke0:    ldx mmucr
            stx savcfg2
            ldx #$3F                  ; RAM 0 only
            stx mmucr
r_pokesta:  sta $FFFF
            ldx savcfg2
            stx mmucr
            rts
pokeaddr = r_pokesta+1

; --- tokenizer hook ------------------------------------------------------------
r_crunch:   bcc rc_pass               ; already claimed by someone else
            pha
            lda mmucr
            sta savcfg
            lda #CFG_71
            sta mmucr
            pla
            jsr rom_crunch
            php
            pha
            lda savcfg
            sta mmucr
            pla
            plp
rc_pass:    jmp (old_clk)

; --- LIST hook: X = 0 statement / $FF function, A = second token -------------
r_list:     bcc rl_pass
            cpx #0
            bne rl_fn
            cmp #CMD_FIRST
            bcc rl_pass
            cmp #CMD_LAST+1
            bcs rl_pass
            sbc #CMD_FIRST-1          ; C=0 here: subtract CMD_FIRST
            tay
            lda cmdname_lo,y
            sta index1
            lda cmdname_hi,y
            sta index1+1
            clc                       ; claimed
            jmp (old_lst)
rl_fn:      cmp #FN_FIRST
            bcc rl_pass
            cmp #FN_LAST+1
            bcs rl_pass
            sbc #FN_FIRST-1
            tay
            lda fnname_lo,y
            sta index1
            lda fnname_hi,y
            sta index1+1
            clc
rl_pass:    jmp (old_lst)

; --- statement hook: A = second token, C = 1 -----------------------------------
r_exec:     bcc re_pass
            cmp #CMD_FIRST
            bcc re_pass
            cmp #CMD_LAST+1
            bcs re_pass
            tax
            lda mmucr
            pha
            lda #CFG_71
            sta mmucr
            txa
            jsr rom_exec
            pla
            sta mmucr
            rts                       ; back to BASIC's statement loop
re_pass:    sec
            jmp (old_exe)

; --- function hook: A = second token, C = 1, FAC = argument --------------------
r_fn:       bcc rf_pass
            cmp #FN_FIRST
            bcc rf_pass
            cmp #FN_LAST+1
            bcs rf_pass
            tax
            lda mmucr
            pha
            lda #CFG_71
            sta mmucr
            txa
            jsr rom_fn
            pla
            sta mmucr
            clc                       ; claimed, result in FAC
            rts
rf_pass:    sec
            jmp (old_fn)

; --- keyword names for LIST (must be in RAM 0) ---------------------------------
cmdname_lo: .byte <nm_palette, <nm_sprite, <nm_sprptr, <nm_sound, <nm_play, <nm_vol, <nm_filter, <nm_sid6, <nm_movspr
cmdname_hi: .byte >nm_palette, >nm_sprite, >nm_sprptr, >nm_sound, >nm_play, >nm_vol, >nm_filter, >nm_sid6, >nm_movspr
fnname_lo:  .byte <nm_rpalette, <nm_rsprite, <nm_rsppos, <nm_bump
fnname_hi:  .byte >nm_rpalette, >nm_rsprite, >nm_rsppos, >nm_bump
nm_palette: .byte "PALETT", 'E'+$80
nm_rpalette: .byte "RPALETT", 'E'+$80
nm_sprite:  .byte "SPRIT", 'E'+$80
nm_sprptr:  .byte "SPRPT", 'R'+$80
nm_sound:   .byte "SOUN", 'D'+$80
nm_play:    .byte "PLA", 'Y'+$80
nm_vol:     .byte "VO", 'L'+$80
nm_filter:  .byte "FILTE", 'R'+$80
nm_sid6:    .byte "SID", '6'+$80
nm_movspr:  .byte "MOVSP", 'R'+$80
nm_rsprite: .byte "RSPRIT", 'E'+$80
nm_rsppos:  .byte "RSPPO", 'S'+$80
nm_bump:    .byte "BUM", 'P'+$80

; --- six-voice sound: IRQ hook ---------------------------------------------------
; Runs before the Kernal's IRQ handler (normal memory map). The music is
; advanced once per jiffy clock tick, so it keeps BASIC's 60/50 Hz rate even
; when the screen editor uses extra raster interrupts for split screens.
r_irq:      lda vicx_key              ; collisions of sprites 9-24: collect them
            cmp #$FE                  ; before BASIC reads $D01E/$D01F, which
            bne ri_tick               ; clears all 24 bits
            lda $D056
            ora col9
            sta col9
            lda $D057
            ora col9+1
            sta col9+1
            lda $D096
            ora col9+2
            sta col9+2
            lda $D097
            ora col9+3
            sta col9+3
ri_tick:    lda jiffy
            cmp lastjif
            beq ri_out
            sta lastjif
            lda irqbusy
            bne ri_out
            inc irqbusy
            lda mmucr
            pha
            lda #CFG_71
            sta mmucr
            jsr tick
            pla
            sta mmucr
            dec irqbusy
ri_out:     jmp (old_irq)

; --- RUN/STOP + RESTORE: the Kernal resets the IRQ vector, then warm starts ---------
r_warm:     sei
            lda cinv
            sta old_irq
            lda cinv+1
            sta old_irq+1
            lda #<r_irq
            sta cinv
            lda #>r_irq
            sta cinv+1
            lda #0
            sta irqbusy
            lda #CFG_71
            sta mmucr
            jsr snd_init
            jsr spr_stop
            lda #CFG_SYS
            sta mmucr
            jmp (old_sysvec)

; --- error during MOVSPR for sprites 9-24: undo the swap, then BASIC's handler ---
r_moverr:   stx mv_errx
            php
            sei
            lda mmucr
            pha
            lda #CFG_71
            sta mmucr
            jsr mv_swapout            ; also puts BASIC's error vector back
            pla
            sta mmucr
            plp
            ldx mv_errx
            jmp (ierror)

; --- variables -----------------------------------------------------------------
; Vectors used with JMP (ind) must not start at $xxFF (the 6502 would read
; the high byte from $xx00), so they start on an even address.
            .fill * & 1, 0
old_clk:    .word 0
old_lst:    .word 0
old_exe:    .word 0
old_fn:     .word 0
sysvec:     .word 0
savtxt:     .word 0
savcfg:     .byte 0
tmpa:       .byte 0
tmpp:       .byte 0
tmpx:       .byte 0
tmpc:       .byte 0
tmph:       .byte 0
tmpv:       .byte 0
savcfg2:    .byte 0
spr_n:      .byte 0
spr_i:      .byte 0
spr_mask:   .byte 0
spr_reg:    .byte 0
spr_blk:    .byte 0

; six-voice sound
            .fill * & 1, 0
old_irq:    .word 0
old_sysvec: .word 0
lastjif:    .byte 0
irqbusy:    .byte 0
s6_on:      .byte 0                   ; SID6 ON/OFF: keywords taken over when typed
snd_v:      .byte 0
p_len:      .byte 0
p_pos:      .byte 0
p_flag:     .byte 0
p_sharp:    .byte 0
p_dnote:    .byte 0
p_voice:    .byte 0                   ; PLAY's current voice 0-5
f_flg:      .byte 0
f_sav:      .byte 0, 0, 0, 0
; SOUND parameters, in this order (see do_sound)
t_max_lo:   .byte 0
t_max_hi:   .byte 0
t_min_lo:   .byte 0
t_min_hi:   .byte 0
t_dir:      .byte 0
t_step_lo:  .byte 0
t_step_hi:  .byte 0
t_freq_lo:  .byte 0
t_freq_hi:  .byte 0
t_pw_lo:    .byte 0
t_pw_hi:    .byte 0
t_wave:     .byte 0
t_time_lo:  .byte 0
t_time_hi:  .byte 0
; per voice, 6 each; s_max_lo..s_freq_hi must stay in this order
s_max_lo:   .fill 6, 0
s_max_hi:   .fill 6, 0
s_min_lo:   .fill 6, 0
s_min_hi:   .fill 6, 0
s_dir:      .fill 6, 0
s_step_lo:  .fill 6, 0
s_step_hi:  .fill 6, 0
s_freq_lo:  .fill 6, 0
s_freq_hi:  .fill 6, 0
s_time_lo:  .fill 6, 0
s_time_hi:  .fill 6, $FF
m_voices:   .fill 12, $FF             ; PLAY note counters, 2 per voice
m_wave:     .fill 6, 0                ; PLAY waveform per voice
; sprites 9-24 (stage 4)
m_data:     .fill 176, 0              ; motion records, 11 bytes per sprite (as BASIC)
mv_save:    .fill 14, 0               ; BASIC slot saved during MOVSPR 9-24
mv_n:       .byte 0
mv_k:       .byte 0
mv_bit:     .byte 0
mv_mi:      .byte 0
mv_base:    .byte 0
mv_reg:     .byte 0
mv_tmp:     .byte 0
mv_active:  .byte 0
mv_errx:    .byte 0
old_ierror: .word 0
col9:       .fill 4, 0                ; BUMP 3-6: collisions of sprites 9-24
fn_n:       .byte 0
fn_a:       .byte 0
fn_bit:     .byte 0
fn_base:    .byte 0
fn_x:       .byte 0
fn_y:       .byte 0
fn_msb:     .byte 0
fn_spd:     .byte 0
sm_i:       .byte 0
sm_bit:     .byte 0
sm_base:    .byte 0
sm_y:       .byte 0
tmpa2:      .byte 0
fil6:       .fill 10, 0               ; filter/volume, 5 bytes per SID:
                                      ; +0/+1 cut-off, +2 resonance/routing,
                                      ; +3 type/volume, +4 current type/volume
ram_end:
            .assert (old_clk & $FF) != $FF, "vector old_clk at $xxFF"
            .assert (old_lst & $FF) != $FF, "vector old_lst at $xxFF"
            .assert (old_exe & $FF) != $FF, "vector old_exe at $xxFF"
            .assert (old_fn & $FF) != $FF, "vector old_fn at $xxFF"
            .assert (sysvec & $FF) != $FF, "vector sysvec at $xxFF"
            .assert (old_irq & $FF) != $FF, "vector old_irq at $xxFF"
            .assert (old_sysvec & $FF) != $FF, "vector old_sysvec at $xxFF"
            .assert ram_end <= $1B80, "RAM part overlaps the six-voice sound tables at $1B80"
            .rend
            .assert * < $FF05, "RAM image runs into the interrupt code at $FF05"

; =============================================================================
;  Interrupt code, byte-identical to the Kernal at $FF05-$FF41.
;  While BASIC 7.1 is mapped in, the CPU vectors come from this ROM. The entry code
;  switches to the system map part-way through, after which the CPU continues
;  in the Kernal's copy at the same addresses; the Kernal's exit code (prend)
;  switches back to our map part-way through and continues here. So this
;  block must match the Kernal exactly.
; =============================================================================
            .org $FF05
v_nmi:      sei
            pha
            txa
            pha
            tya
            pha
            lda mmucr
            pha
            lda #CFG_SYS
            sta mmucr
            jmp ($0318)
v_irq:      pha
            txa
            pha
            tya
            pha
            lda mmucr
            pha
            lda #CFG_SYS
            sta mmucr
            tsx
            lda $0105,x
            and #$10
            beq v_irq2
            jmp ($0316)
v_irq2:     jmp ($0314)
v_prend:    pla                       ; $FF33: Kernal interrupt exit
            sta mmucr
            pla
            tay
            pla
            tax
            pla
            rti
v_reset:    lda #CFG_SYS              ; $FF3D: after the store the Kernal's own
            sta mmucr                 ; reset code continues ('jmp start')
            jmp ($FFFC)
            .assert v_irq == $FF17, "irq entry must be at $FF17 as in the Kernal"
            .assert v_prend == $FF33, "prend must be at $FF33 as in the Kernal"
            .assert v_reset == $FF3D, "reset must be at $FF3D as in the Kernal"

            .org $FFFA
            .word v_nmi, v_reset, v_irq
