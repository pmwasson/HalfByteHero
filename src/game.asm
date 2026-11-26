;-----------------------------------------------------------------------------
; Paul Wasson - 2026
;-----------------------------------------------------------------------------

.include "defines.asm"
.include "macros.asm"

.segment "CODE"
.org    $2000

;-----------------------------------------------------------------------------
; main
;
; Turn on full screen low-res and start the game loop
;-----------------------------------------------------------------------------

.proc   main

    ldx     #PLAYER_START_X
    ldy     #PLAYER_START_Y
    jsr     playerInit

    ; Fill page 2 first so the first frame shown isn't garbage
    jsr     updateScrollOffset
    jsr     drawScreen2

    ; Full screen low-res, showing page 2 while page 1 is drawn
    sta     LORES
    sta     MIXCLR
    sta     HISCR
    sta     TXTCLR

    lda     #$00                ; draw page 1 first
    sta     screenPage
    jmp     gameLoop

.endproc

;-----------------------------------------------------------------------------
; gameLoop
;
; Draw a full frame on the hidden page, wait for vsync, then show it
; and switch to drawing the other page. Loops forever.
;
; Order per page: input, player update, scroll to the player, background,
; then draw the player on top.
;-----------------------------------------------------------------------------

.proc   gameLoop

loop:
    ; Draw page 1 (page 2 is showing)
    jsr     readInput
    jsr     playerUpdate
    jsr     updateScrollOffset
    jsr     drawScreen1
    jsr     drawPlayer
    jsr     waitVBL
    sta     LOWSCR              ; show page 1
    lda     #$04                ; draw page 2 next
    sta     screenPage

    ; Draw page 2 (page 1 is showing)
    jsr     readInput
    jsr     playerUpdate
    jsr     updateScrollOffset
    jsr     drawScreen2
    jsr     drawPlayer
    jsr     waitVBL
    sta     HISCR               ; show page 2
    lda     #$00                ; draw page 1 next
    sta     screenPage

    jmp     loop

.endproc

;-----------------------------------------------------------------------------
; updateScrollOffset
;
; Scroll so the player (playerXHi) is at screen column PLAYER_SCREEN_X
; Sets scrollOffset and returns it in Y for drawScreen1/2
;-----------------------------------------------------------------------------

.proc   updateScrollOffset

    lda     playerXHi
    sec
    sbc     #PLAYER_SCREEN_X
    and     #LEVEL_WIDTH-1      ; wrap around the level
    sta     scrollOffset
    tay
    rts

.endproc

;-----------------------------------------------------------------------------
; waitVBL
;
; Wait for the start of vertical blank FRAMES_PER_TICK times
; (Apple IIe: RDVBLBAR bit 7 is 0 during vertical blank)
;-----------------------------------------------------------------------------

.proc   waitVBL

    ldx     #FRAMES_PER_TICK

frame:
waitDisplay:
    lda     RDVBLBAR
    bpl     waitDisplay         ; in blank, wait for it to end
waitBlank:
    lda     RDVBLBAR
    bmi     waitBlank           ; drawing, wait for blank to start
    dex
    bne     frame
    rts

.endproc

;-----------------------------------------------------------------------------
; readInput
;
; Copy inputState to inputPrev, then read the new held state
;   Jump        = button 0 (or open-apple)
;   Left/right  = joystick X axis
;-----------------------------------------------------------------------------

.proc   readInput

    lda     inputState
    sta     inputPrev
    lda     #0
    sta     inputState

    lda     BUTTON0
    bpl     checkStick
    lda     #INPUT_JUMP
    sta     inputState

checkStick:
    ldx     #0
    jsr     PREAD               ; Y = paddle 0 (0..255)
    cpy     #STICK_LEFT
    bcs     notLeft
    lda     inputState
    ora     #INPUT_LEFT
    sta     inputState
    rts

notLeft:
    cpy     #STICK_RIGHT
    bcc     done
    lda     inputState
    ora     #INPUT_RIGHT
    sta     inputState
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; drawScreen1 - Copy low res graphic buffer onto screen1
;               with an offset of Y into the buffer.
;               Y range 0..127, wraps at the end of the buffer
;
; This can be used to simulate horizontal scrolling
;-----------------------------------------------------------------------------

.proc   drawScreen1

    ; Pass in offset in Y, range 0 .. 127
    ldx     #0

loop:
    lda     background+$000,y
    sta     $0400,x
    lda     background+$080,y
    sta     $0480,x
    lda     background+$100,y
    sta     $0500,x
    lda     background+$180,y
    sta     $0580,x
    lda     background+$200,y
    sta     $0600,x
    lda     background+$280,y
    sta     $0680,x
    lda     background+$300,y
    sta     $0700,x
    lda     background+$380,y
    sta     $0780,x
    lda     background+$400,y
    sta     $0428,x
    lda     background+$480,y
    sta     $04A8,x
    lda     background+$500,y
    sta     $0528,x
    lda     background+$580,y
    sta     $05A8,x
    lda     background+$600,y
    sta     $0628,x
    lda     background+$680,y
    sta     $06A8,x
    lda     background+$700,y
    sta     $0728,x
    lda     background+$780,y
    sta     $07A8,x
    lda     background+$800,y
    sta     $0450,x
    lda     background+$880,y
    sta     $04D0,x
    lda     background+$900,y
    sta     $0550,x
    lda     background+$980,y
    sta     $05D0,x
    lda     background+$A00,y
    sta     $0650,x
    lda     background+$A80,y
    sta     $06D0,x
    lda     background+$B00,y
    sta     $0750,x
    lda     background+$B80,y
    sta     $07D0,x

    iny
    tya
    and     #LEVEL_WIDTH-1      ; wrap around the level
    tay
    inx
    cpx     #40
    beq     done
    jmp     loop
done:
    rts
.endproc

;-----------------------------------------------------------------------------
; drawScreen2 - Copy low res graphic buffer onto screen2
;               with an offset of Y into the buffer.
;               Y range 0..127, wraps at the end of the buffer
;
; Same as drawScreen1, but for page 2 (double buffering)
;-----------------------------------------------------------------------------

.proc   drawScreen2

    ; Pass in offset in Y, range 0 .. 127
    ldx     #0

loop:
    lda     background+$000,y
    sta     $0800,x
    lda     background+$080,y
    sta     $0880,x
    lda     background+$100,y
    sta     $0900,x
    lda     background+$180,y
    sta     $0980,x
    lda     background+$200,y
    sta     $0A00,x
    lda     background+$280,y
    sta     $0A80,x
    lda     background+$300,y
    sta     $0B00,x
    lda     background+$380,y
    sta     $0B80,x
    lda     background+$400,y
    sta     $0828,x
    lda     background+$480,y
    sta     $08A8,x
    lda     background+$500,y
    sta     $0928,x
    lda     background+$580,y
    sta     $09A8,x
    lda     background+$600,y
    sta     $0A28,x
    lda     background+$680,y
    sta     $0AA8,x
    lda     background+$700,y
    sta     $0B28,x
    lda     background+$780,y
    sta     $0BA8,x
    lda     background+$800,y
    sta     $0850,x
    lda     background+$880,y
    sta     $08D0,x
    lda     background+$900,y
    sta     $0950,x
    lda     background+$980,y
    sta     $09D0,x
    lda     background+$A00,y
    sta     $0A50,x
    lda     background+$A80,y
    sta     $0AD0,x
    lda     background+$B00,y
    sta     $0B50,x
    lda     background+$B80,y
    sta     $0BD0,x

    iny
    tya
    and     #LEVEL_WIDTH-1      ; wrap around the level
    tay
    inx
    cpx     #40
    beq     done
    jmp     loop
done:
    rts
.endproc


;-----------------------------------------------------------------------------
; drawPlayer
;
; Draw a single pixel at PLAYER_SCREEN_X, playerYHi
; using playerColorTop / Bottom (Y even = top pixel, Y odd = bottom pixel)
; Can draw to either page based on screenPage value ($00 or $04)
; Uses screenPtr0/1 for indexing to screen
;-----------------------------------------------------------------------------

.proc   drawPlayer

    ; Set screenPtr to start of text row (Y/2) on the selected page
    lda     playerYHi
    lsr
    tax
    lda     lineOffset,x
    sta     screenPtr0
    lda     linePage,x
    clc
    adc     screenPage
    sta     screenPtr1

    ldy     #PLAYER_SCREEN_X    ; screen scrolls so player is always here

    lda     playerYHi
    and     #1
    bne     odd

    ; Even Y = top pixel of the cell = low nibble
    lda     (screenPtr0),y
    and     #$F0                ; keep bottom pixel
    ora     playerColorTop
    sta     (screenPtr0),y
    rts

odd:
    ; Odd Y = bottom pixel of the cell = high nibble
    lda     (screenPtr0),y
    and     #$0F                ; keep top pixel
    ora     playerColorBottom
    sta     (screenPtr0),y
    rts

.endproc

;-----------------------------------------------------------------------------
; isSolid
;
; Read the pixel at level column X, row Y in the background buffer
; Returns carry set if the pixel is non-zero (solid)
; Column wraps at LEVEL_WIDTH
; Rows >= PLAYFIELD_HEIGHT (including $FF) return carry clear
; Preserves X and Y, clobbers A
; Uses mapPtr0/1 for indexing to background
;
; Reads the buffer, not the screen, so it doesn't depend on what has
; been drawn (and never sees the player's own pixel)
;-----------------------------------------------------------------------------

.proc   isSolid

    cpy     #PLAYFIELD_HEIGHT
    bcc     inRange
    clc                         ; carry clear = open
    rts

inRange:
    sty     isSolidRow

    ; Set mapPtr to start of text row (Y/2) in background
    ; Rows are $80 bytes and background is page aligned, so
    ; page = Y/4, offset = $80 if text row is odd
    lda     #0
    sta     mapPtr0
    tya
    lsr
    lsr                         ; A = Y/4, carry = text row odd
    ror     mapPtr0             ; $80 if odd, carry now 0
    adc     #>background
    sta     mapPtr1

    txa
    and     #LEVEL_WIDTH-1      ; wrap around the level
    tay
    lda     isSolidRow
    lsr                         ; carry = odd row
    lda     (mapPtr0),y
    bcs     odd

    ; Even Y = top pixel of the cell = low nibble
    and     #$0F
    jmp     test

odd:
    ; Odd Y = bottom pixel of the cell = high nibble
    and     #$F0

test:
    cmp     #1                  ; carry set if non-zero
    ldy     isSolidRow          ; restore Y (carry unchanged)
    rts

.endproc

;-----------------------------------------------------------------------------
; Player movement and table driven jump
;
; Call playerInit once, then playerUpdate once per game tick (30 ticks/sec)
; after inputState / inputPrev have been updated.
;
; Position is 8.8 fixed point:
;   X = playerXHi (level column 0..127), playerXLo (subpixel)
;   Y = playerYHi (row 0..47),           playerYLo (subpixel, 0 when grounded)
;
; The screen scrolls so the player is always drawn at PLAYER_SCREEN_X;
; playerXHi is the player's column in the (wrapping) level.
;
; Velocity never exceeds 1 cell per tick so only the neighboring cell
; needs to be checked for collision.
;-----------------------------------------------------------------------------

FRAMES_PER_TICK     = 2         ; 60Hz / 2 = 30 ticks/sec (jump table rate)
STICK_LEFT          = $40       ; paddle below this = left
STICK_RIGHT         = $C0       ; paddle at or above this = right
PLAYER_START_X      = 2         ; level column
PLAYER_START_Y      = 43        ; standing on the ground (row 44)
PLAYER_SCREEN_X     = 20        ; middle of the screen

LEVEL_WIDTH         = 128       ; background buffer width (power of 2)
PLAYFIELD_HEIGHT    = 48        ; full screen low-res

INPUT_LEFT          = %00000001 ; inputState bits (held, not presses)
INPUT_RIGHT         = %00000010
INPUT_JUMP          = %00000100

FLAG_GROUND         = %10000000 ; standing on something (test with BIT/BMI)
FLAG_RISING         = %01000000 ; early in jump, release can cut it

ACCEL               = $16       ; ~4 ticks to top speed
DECEL               = $10       ; ~6 ticks to stop
MAX_VX              = $55       ; 0.33 cells/tick

JUMP_LEN            = 18        ; entries in jumpVelLo/Hi
CUT_IDX             = 5         ; early release skips to this index
FALL_IDX            = 9         ; first falling entry: walk-offs, head bumps
COYOTE_TICKS        = 3         ; grace period to jump after walking off ledge
BUFFER_TICKS        = 4         ; how early a press before landing counts
NOT_JUMPING         = $FF       ; playerJumpIdx value while grounded
TERMINAL_VY         = $0100     ; +1.0 rows/tick

;-----------------------------------------------------------------------------
; playerInit
;
; Place the player standing at column X, row Y
; Caller must make sure (X, Y+1) is solid
;-----------------------------------------------------------------------------

.proc   playerInit

    stx     playerXHi
    sty     playerYHi
    lda     #0
    sta     playerXLo
    sta     playerYLo
    sta     playerVX
    sta     playerVYLo
    sta     playerVYHi
    sta     playerCoyote
    sta     playerJumpBuffer
    lda     #FLAG_GROUND
    sta     playerFlags
    lda     #NOT_JUMPING
    sta     playerJumpIdx
    rts

.endproc

;-----------------------------------------------------------------------------
; playerUpdate
;
; Run one game tick
;-----------------------------------------------------------------------------

.proc   playerUpdate

    jsr     playerUpdateVX
    jsr     playerMoveX
    jsr     playerCheckWalkOff
    jsr     playerHandleJump
    jmp     playerStepY         ; tail call

.endproc

;-----------------------------------------------------------------------------
; playerUpdateVX
;
; Accelerate toward the held direction, or slow down
; Both directions held counts as none
;-----------------------------------------------------------------------------

.proc   playerUpdateVX

    lda     inputState
    and     #INPUT_LEFT|INPUT_RIGHT
    cmp     #INPUT_RIGHT
    beq     right
    cmp     #INPUT_LEFT
    beq     left

    ; No direction: decelerate toward 0
    lda     playerVX
    beq     done
    bmi     decNeg
    sec
    sbc     #DECEL
    bpl     store               ; still >= 0
    lda     #0
    beq     store               ; always
decNeg:
    clc
    adc     #DECEL
    bmi     store               ; still < 0
    lda     #0
    beq     store               ; always

right:
    lda     playerVX
    bmi     rightTurn           ; moving left: turn around faster
    clc
    adc     #ACCEL
    cmp     #MAX_VX+1
    bcc     store
    lda     #MAX_VX
    bne     store               ; always
rightTurn:
    clc
    adc     #ACCEL+DECEL
    jmp     store

left:
    lda     playerVX
    beq     leftGo              ; from standstill
    bpl     leftTurn            ; moving right: turn around faster
leftGo:
    sec
    sbc     #ACCEL
    cmp     #<(-MAX_VX)         ; $AB: clamp at -MAX_VX
    bcs     store
    lda     #<(-MAX_VX)
    bne     store               ; always
leftTurn:
    sec
    sbc     #ACCEL+DECEL

store:
    sta     playerVX
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; playerMoveX
;
; Add playerVX to 8.8 X. When the column would change, check the new
; cell at the current row; if blocked, stop at the edge of the current
; column. The column wraps around the level.
; Uses tempZP / temp2ZP for the new X
;-----------------------------------------------------------------------------

.proc   playerMoveX

    lda     playerVX
    beq     done
    clc
    adc     playerXLo
    sta     tempZP
    lda     playerVX            ; sign extend VX into high byte
    and     #$80                ; (LDA/AND/BEQ leave carry alone)
    beq     pos
    lda     #$FF
pos:
    adc     playerXHi
    and     #LEVEL_WIDTH-1      ; wrap around the level
    sta     temp2ZP
    cmp     playerXHi
    beq     commit              ; same column, nothing to check

    tax
    ldy     playerYHi
    jsr     isSolid
    bcs     blocked

commit:
    lda     tempZP
    sta     playerXLo
    lda     temp2ZP
    sta     playerXHi
done:
    rts

blocked:
    lda     playerVX
    bmi     hitLeft
    lda     #$FF                ; right edge of current column
    bne     setLo               ; always
hitLeft:
    lda     #$00                ; left edge of current column
setLo:
    sta     playerXLo
    lda     #0
    sta     playerVX
    rts

.endproc

;-----------------------------------------------------------------------------
; playerCheckWalkOff
;
; Grounded but nothing below: start falling from the top of the arc
; and open the coyote window
;-----------------------------------------------------------------------------

.proc   playerCheckWalkOff

    bit     playerFlags
    bpl     done                ; already airborne
    ldx     playerXHi
    ldy     playerYHi
    iny
    jsr     isSolid
    bcs     done
    lda     playerFlags
    and     #<~FLAG_GROUND
    sta     playerFlags
    lda     #FALL_IDX
    sta     playerJumpIdx
    lda     #COYOTE_TICKS
    sta     playerCoyote
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; playerHandleJump
;
; Buffer a new press, start a jump if allowed, tick down the timers,
; and cut the jump on early release
;-----------------------------------------------------------------------------

.proc   playerHandleJump

    ; New press this tick? -> buffer it
    lda     inputState
    and     #INPUT_JUMP
    beq     noPress
    lda     inputPrev
    and     #INPUT_JUMP
    bne     noPress
    lda     #BUFFER_TICKS
    sta     playerJumpBuffer
noPress:

    ; Start a jump if buffered and (grounded or coyote)
    lda     playerJumpBuffer
    beq     timers
    bit     playerFlags
    bmi     start
    lda     playerCoyote
    beq     timers
start:
    lda     #0
    sta     playerJumpIdx
    sta     playerCoyote
    sta     playerJumpBuffer
    lda     playerFlags
    and     #<~FLAG_GROUND
    ora     #FLAG_RISING
    sta     playerFlags
    jsr     onJumpStart

timers:
    lda     playerJumpBuffer
    beq     coyote
    dec     playerJumpBuffer
coyote:
    lda     playerCoyote
    beq     cut
    dec     playerCoyote

    ; Variable height: released while rising -> skip to CUT_IDX
cut:
    lda     playerFlags
    and     #FLAG_RISING
    beq     done
    lda     playerJumpIdx
    cmp     #CUT_IDX
    bcs     endRise             ; past the cut point, nothing to cut
    lda     inputState
    and     #INPUT_JUMP
    bne     done                ; still held
    lda     #CUT_IDX
    sta     playerJumpIdx
endRise:
    lda     playerFlags
    and     #<~FLAG_RISING
    sta     playerFlags
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; playerStepY
;
; While airborne, add this tick's table velocity (or +1.0 past the end)
; to 8.8 Y. When the row would change, check the new cell:
; below -> land, above -> head bump
; Uses tempZP / temp2ZP for the new Y
;-----------------------------------------------------------------------------

.proc   playerStepY

    bit     playerFlags
    bmi     done                ; grounded
    ldx     playerJumpIdx
    cpx     #JUMP_LEN
    bcc     table
    lda     #<TERMINAL_VY       ; past the end: terminal velocity
    ldy     #>TERMINAL_VY
    bne     haveVY              ; always (Y = 1)
table:
    inc     playerJumpIdx
    lda     jumpVelLo,x
    ldy     jumpVelHi,x
haveVY:
    sta     playerVYLo
    sty     playerVYHi
    clc                         ; new Y = Y + VY
    adc     playerYLo
    sta     tempZP
    tya
    adc     playerYHi
    sta     temp2ZP
    cmp     playerYHi
    beq     commit              ; same row, nothing to check
    bit     playerVYHi          ; N = moving up (A still = new row)
    bmi     up

    ; Entering the row below
    tay
    ldx     playerXHi
    jsr     isSolid
    bcs     land
    jsr     commit
    lda     playerYHi
    cmp     #PLAYFIELD_HEIGHT
    bcc     done
    jmp     onPitDeath          ; tail call

    ; Entering the row above
up:
    cmp     #$FF                ; above row 0: top of screen is a ceiling
    beq     bump
    tay
    ldx     playerXHi
    jsr     isSolid
    bcs     bump

commit:
    lda     tempZP
    sta     playerYLo
    lda     temp2ZP
    sta     playerYHi
done:
    rts

land:                           ; stay in this row, snap subpixel
    lda     #0
    sta     playerYLo
    sta     playerVYLo
    sta     playerVYHi
    lda     playerFlags
    ora     #FLAG_GROUND
    and     #<~FLAG_RISING
    sta     playerFlags
    lda     #NOT_JUMPING
    sta     playerJumpIdx
    jmp     onLanded            ; tail call

bump:                           ; stay in this row at its top edge
    lda     #0
    sta     playerYLo
    lda     #FALL_IDX           ; continue from the top of the arc
    sta     playerJumpIdx
    lda     playerFlags
    and     #<~FLAG_RISING
    sta     playerFlags
    jmp     onHeadBump          ; tail call

.endproc

;-----------------------------------------------------------------------------
; Player event hooks (sound, stats, etc)
;
; May clobber A, X and Y
; onLanded, onHeadBump and onPitDeath are tail called, so they return
; straight to playerUpdate's caller
;-----------------------------------------------------------------------------

.proc   onJumpStart
    rts
.endproc

.proc   onLanded
    rts
.endproc

.proc   onHeadBump
    rts
.endproc

.proc   onPitDeath
    ; Respawn (must not leave playerYHi >= PLAYFIELD_HEIGHT for drawPlayer)
    ; TODO: lose a life
    ldx     #PLAYER_START_X
    ldy     #PLAYER_START_Y
    jmp     playerInit          ; tail call
.endproc

;-----------------------------------------------------------------------------
; Data
;-----------------------------------------------------------------------------

screenPage:     .byte   $00     ; Either $00 or $04 to add to line page
scrollOffset:   .byte   0       ; buffer column at left edge, 0..127

inputState:     .byte   0       ; INPUT_* bits held this tick
inputPrev:      .byte   0       ; INPUT_* bits held last tick

playerXHi:      .byte   20      ; level column 0..127 (drives scrolling)
playerXLo:      .byte   0       ; subpixel (1/256 cell)
playerYHi:      .byte   20      ; row 0..47
playerYLo:      .byte   0       ; subpixel (1/256 row), 0 when grounded
playerVX:       .byte   0       ; signed, 1/256 cell per tick (-$55..$55)
playerVYLo:     .byte   0       ; last Y velocity applied, signed 8.8
playerVYHi:     .byte   0       ;   (informational, 0 when grounded)
playerFlags:    .byte   FLAG_GROUND     ; FLAG_GROUND | FLAG_RISING
playerJumpIdx:  .byte   NOT_JUMPING     ; next jumpVel entry
playerCoyote:   .byte   0       ; ticks left to jump after walking off ledge
playerJumpBuffer:   .byte   0   ; ticks left on a buffered jump press

isSolidRow:     .byte   0       ; isSolid saves Y here

playerColorTop:     .byte   $0F     ; top pixel (low nibble)
playerColorBottom:  .byte   $F0     ; bottom pixel (high nibble)

; Jump table B: Y velocity per tick, signed 8.8 (rows/tick)
; Generated from: v0 = -1.0, rise gravity $001A while VY < 0,
; fall gravity $0026 while VY >= 0, clamped at +1.0.
; Per tick: VY += g, clamp, Y += VY.
; Full jump = 18 ticks, peaks 5 rows up, lands on the start row.
; Regenerate from new constants to re-tune; don't hand edit.

;                   tick: 0   1   2   3   4   5   6   7   8
jumpVelLo:      .byte   $1A,$34,$4E,$68,$82,$9C,$B6,$D0,$EA
;                   tick: 9  10  11  12  13  14  15  16  17
                .byte   $04,$2A,$50,$76,$9C,$C2,$E8,$00,$00
jumpVelHi:      .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
                .byte   $00,$00,$00,$00,$00,$00,$00,$01,$01

.align  256
; Example level: 128 x 48 pixels, 24 text rows of $80 bytes
; Each byte = top pixel (low nibble) + bottom pixel (high nibble)
; Columns 127 and 0 line up so the level wraps
background:
    ; text row 0 (pixel rows 0, 1)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 1 (pixel rows 2, 3)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 2 (pixel rows 4, 5)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 3 (pixel rows 6, 7)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 4 (pixel rows 8, 9)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 5 (pixel rows 10, 11)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 6 (pixel rows 12, 13)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 7 (pixel rows 14, 15)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 8 (pixel rows 16, 17)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 9 (pixel rows 18, 19)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 10 (pixel rows 20, 21)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 11 (pixel rows 22, 23)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$D0,$D0,$D0
    .byte   $D0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 12 (pixel rows 24, 25)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 13 (pixel rows 26, 27)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$90,$90,$90,$90,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 14 (pixel rows 28, 29)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$D0,$D0,$D0,$D0,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 15 (pixel rows 30, 31)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$90
    .byte   $90,$90,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 16 (pixel rows 32, 33)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 17 (pixel rows 34, 35)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$90,$90,$90,$90,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$09,$09,$09,$09,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 18 (pixel rows 36, 37)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 19 (pixel rows 38, 39)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$90
    .byte   $90,$90,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$01,$01
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$90,$90,$90,$90,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 20 (pixel rows 40, 41)
    .byte   $00,$00,$00,$00,$00,$09,$09,$09,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$03,$03,$03,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$99,$99,$00,$00,$03,$03,$03,$03,$03
    .byte   $00,$00,$01,$01,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 21 (pixel rows 42, 43)
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$90,$90,$00,$00,$99,$99
    .byte   $00,$00,$00,$00,$00,$00,$00,$99,$99,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $88,$88,$88,$88,$88,$88,$88,$88,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
    ; text row 22 (pixel rows 44, 45)
    .byte   $8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$00,$00,$00,$8C,$8C,$8C
    .byte   $8C,$8C,$8C,$8C,$8C,$00,$00,$00,$00,$8C,$8C,$8C,$8C,$8C,$8C,$8C
    .byte   $00,$00,$00,$00,$00,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C
    .byte   $00,$00,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C
    .byte   $00,$00,$00,$00,$00,$00,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C
    .byte   $88,$88,$88,$88,$88,$88,$88,$88,$00,$00,$00,$00,$8C,$8C,$8C,$8C
    .byte   $8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C,$8C
    .byte   $8C,$8C,$8C,$8C,$8C,$8C,$00,$00,$00,$8C,$8C,$8C,$8C,$8C,$8C,$8C
    ; text row 23 (pixel rows 46, 47)
    .byte   $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$00,$00,$00,$88,$88,$88
    .byte   $88,$88,$88,$88,$88,$00,$00,$00,$00,$88,$88,$88,$88,$88,$88,$88
    .byte   $00,$00,$00,$00,$00,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
    .byte   $00,$00,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
    .byte   $00,$00,$00,$00,$00,$00,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
    .byte   $88,$88,$88,$88,$88,$88,$88,$88,$00,$00,$00,$00,$88,$88,$88,$88
    .byte   $88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88,$88
    .byte   $88,$88,$88,$88,$88,$88,$00,$00,$00,$88,$88,$88,$88,$88,$88,$88

;-----------------------------------------------------------------------------
; Lookup Tables
;-----------------------------------------------------------------------------
.align 256

lineOffset:
    .byte   <$0400      ; 0
    .byte   <$0480      ; 1
    .byte   <$0500      ; 2
    .byte   <$0580      ; 3
    .byte   <$0600      ; 4
    .byte   <$0680      ; 5
    .byte   <$0700      ; 6
    .byte   <$0780      ; 7
    .byte   <$0428      ; 8
    .byte   <$04A8      ; 9
    .byte   <$0528      ; 10
    .byte   <$05A8      ; 11
    .byte   <$0628      ; 12
    .byte   <$06A8      ; 13
    .byte   <$0728      ; 14
    .byte   <$07A8      ; 15
    .byte   <$0450      ; 16
    .byte   <$04D0      ; 17
    .byte   <$0550      ; 18
    .byte   <$05D0      ; 19
    .byte   <$0650      ; 20
    .byte   <$06D0      ; 21
    .byte   <$0750      ; 22
    .byte   <$07D0      ; 23

linePage:
    .byte   >$0400      ; 0
    .byte   >$0480      ; 1
    .byte   >$0500      ; 2
    .byte   >$0580      ; 3
    .byte   >$0600      ; 4
    .byte   >$0680      ; 5
    .byte   >$0700      ; 6
    .byte   >$0780      ; 7
    .byte   >$0428      ; 8
    .byte   >$04A8      ; 9
    .byte   >$0528      ; 10
    .byte   >$05A8      ; 11
    .byte   >$0628      ; 12
    .byte   >$06A8      ; 13
    .byte   >$0728      ; 14
    .byte   >$07A8      ; 15
    .byte   >$0450      ; 16
    .byte   >$04D0      ; 17
    .byte   >$0550      ; 18
    .byte   >$05D0      ; 19
    .byte   >$0650      ; 20
    .byte   >$06D0      ; 21
    .byte   >$0750      ; 22
    .byte   >$07D0      ; 23
