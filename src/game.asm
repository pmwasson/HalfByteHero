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

    jsr     initMachine

    lda     #0                  ; level 0 is the title page
    jsr     startLevel

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
; Order per page: input, move objects, player update, object touches, scroll to the player,
; background, then draw the player on top.
;-----------------------------------------------------------------------------

.proc   gameLoop

loop:
    ; Draw page 1 (page 2 is showing)
    jsr     readInput
    jsr     moveObjects
    jsr     playerUpdate
    jsr     checkObjects
    jsr     updateScrollOffset
    jsr     drawScreen1
    jsr     drawPlayer
    jsr     waitVBL
    sta     LOWSCR              ; show page 1
    lda     #$04                ; draw page 2 next
    sta     screenPage

    ; Draw page 2 (page 1 is showing)
    jsr     readInput
    jsr     moveObjects
    jsr     playerUpdate
    jsr     checkObjects
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
; initMachine
;
; Detect IIe / IIc / IIgs (sets machineType) and set up for waitVBL
;   IIgs: slow to 1MHz (paddle taps are cycle counted) and turn on
;         text page 2 shadowing (needed for low-res page 2)
;   IIc:  enable the VBL interrupt so RDVBLBAR latches it. CPU
;         interrupts are masked so it is never actually taken.
;-----------------------------------------------------------------------------

.proc   initMachine

    ; ID routine clears carry on a IIgs, is an RTS on 8-bit machines
    sec
    jsr     IDROUTINE
    bcs     notGS

    lda     #MACHINE_IIGS
    sta     machineType

    lda     CYAREG
    and     #%01111111          ; bit 7 = 0 for 1MHz
    sta     CYAREG

    lda     SHADOW
    and     #%11011111          ; bit 5 = 0 to shadow text page 2
    sta     SHADOW
    rts

notGS:
    lda     ROMID_FBC0
    bne     done                ; IIe (machineType defaults to MACHINE_IIE)

    lda     #MACHINE_IIC
    sta     machineType

    sei                         ; latch the VBL interrupt, never take it
    sta     IOUDISOFF           ; enable access to IOU
    sta     ENVBL               ; enable VBL interrupt
    sta     IOUDISON            ; disable access to IOU
    bit     PTRIG               ; clear any pending VBL flag

done:
    rts

.endproc

;-----------------------------------------------------------------------------
; waitVBL
;
; Wait for the start of vertical blank
;   IIe:  RDVBLBAR bit 7 is 0 during vertical blank
;   IIgs: RDVBLBAR bit 7 is 1 during vertical blank (inverted)
;   IIc:  RDVBLBAR bit 7 is set by the VBL interrupt and cleared by
;         reading PTRIG ($C070), which drawScreen1/2 do every frame
;         when they start the paddle timer
;-----------------------------------------------------------------------------

.proc   waitVBL

    lda     machineType
    beq     iie
    cmp     #MACHINE_IIGS
    beq     iigs

iic:
    lda     RDVBLBAR
    bpl     iic                 ; wait for VBL interrupt flag
    rts

iie:
    lda     RDVBLBAR
    bpl     iie                 ; in blank, wait for it to end
iieBlank:
    lda     RDVBLBAR
    bmi     iieBlank            ; drawing, wait for blank to start
    rts

iigs:
    lda     RDVBLBAR
    bmi     iigs                ; in blank, wait for it to end
iigsBlank:
    lda     RDVBLBAR
    bpl     iigsBlank           ; drawing, wait for blank to start
    rts

.endproc

;-----------------------------------------------------------------------------
; readInput
;
; Copy inputState to inputPrev, then read the new held state
;   Jump        = button 0 (or open-apple)
;   Left/right  = joystick X axis, sampled during the last drawScreen
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
    ldx     paddleTaps          ; 0 = left, 1 = middle, 2 = right
    lda     inputState
    ora     paddleInput,x
    sta     inputState
    rts

.endproc

;-----------------------------------------------------------------------------
; paddleTap
;
; Called from drawScreen1/2 at pass PADDLE_TAP_1 and PADDLE_TAP_2 (in X)
; Counts how many taps the paddle 0 timer is still running, then sets
; tapCompare to the next tap (or 40 to finish the loop)
; Preserves X and Y, clobbers A
;
; The paddle timer runs about 11 cycles per paddle unit (0..255), so
; tap 1 at ~1/3 (paddle 85, ~935 cycles) and tap 2 at ~2/3 (paddle 170,
; ~1870 cycles). Each drawScreen pass is 235 cycles:
;   tap 1 = 935 / 235 = 4 passes, tap 2 = 1870 / 235 = 8 passes
;-----------------------------------------------------------------------------

.proc   paddleTap

    lda     GC0                 ; bit 7 set while timer still running
    bpl     timerDone
    inc     paddleTaps
timerDone:

    lda     #40                 ; after tap 2, finish the loop
    cpx     #PADDLE_TAP_1
    bne     setCompare
    lda     #PADDLE_TAP_2       ; after tap 1, go to tap 2
setCompare:
    sta     tapCompare
    rts

.endproc

;-----------------------------------------------------------------------------
; drawScreen1 - Copy low res graphic buffer onto screen1
;               with an offset of Y into the buffer.
;               Y range 0..127, wraps at the end of the buffer
;               Also samples paddle 0 into paddleTaps (see paddleTap)
;
; This can be used to simulate horizontal scrolling
;-----------------------------------------------------------------------------

.proc   drawScreen1

    ; Pass in offset in Y, range 0 .. 127
    ldx     #0

    ; Start paddle timer, sampled at passes PADDLE_TAP_1 and PADDLE_TAP_2
    stx     paddleTaps
    lda     #PADDLE_TAP_1
    sta     tapCompare
    bit     GCRESET             ; read (also clears IIc VBL flag)

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
    cpx     tapCompare          ; next tap, or 40 when done
    beq     tap
    jmp     loop

tap:
    cpx     #40
    beq     done
    jsr     paddleTap
    jmp     loop

done:
    rts
.endproc

;-----------------------------------------------------------------------------
; drawScreen2 - Copy low res graphic buffer onto screen2
;               with an offset of Y into the buffer.
;               Y range 0..127, wraps at the end of the buffer
;               Also samples paddle 0 into paddleTaps (see paddleTap)
;
; Same as drawScreen1, but for page 2 (double buffering)
;-----------------------------------------------------------------------------

.proc   drawScreen2

    ; Pass in offset in Y, range 0 .. 127
    ldx     #0

    ; Start paddle timer, sampled at passes PADDLE_TAP_1 and PADDLE_TAP_2
    stx     paddleTaps
    lda     #PADDLE_TAP_1
    sta     tapCompare
    bit     GCRESET             ; read (also clears IIc VBL flag)

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
    cpx     tapCompare          ; next tap, or 40 when done
    beq     tap
    jmp     loop

tap:
    cpx     #40
    beq     done
    jsr     paddleTap
    jmp     loop

done:
    rts
.endproc


;-----------------------------------------------------------------------------
; drawPlayer
;
; Draw a single pixel at PLAYER_SCREEN_X, playerYHi
; in COLOR_PLAYER (Y even = top pixel, Y odd = bottom pixel)
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
    ; (white is all 1 bits, so ORA alone sets it and keeps the other pixel)
    lda     (screenPtr0),y
    ora     #COLOR_PLAYER
    sta     (screenPtr0),y
    rts

odd:
    ; Odd Y = bottom pixel of the cell = high nibble
    lda     (screenPtr0),y
    ora     #COLOR_PLAYER << 4
    sta     (screenPtr0),y
    rts

.endproc

;-----------------------------------------------------------------------------
; isSolid
;
; Read the pixel at level column X, row Y in the background buffer
; Returns the pixel color (0..15) in A, carry set if it isn't
; levelBgColor (solid)
; Column wraps at LEVEL_WIDTH
; Rows >= PLAYFIELD_HEIGHT (including $FF) return levelBgColor / carry clear
; Preserves X and Y
; Uses mapPtr0/1 for indexing to background
;
; Reads the buffer, not the screen, so it doesn't depend on what has
; been drawn (and never sees the player's own pixel)
;-----------------------------------------------------------------------------

.proc   isSolid

    cpy     #PLAYFIELD_HEIGHT
    bcc     inRange
    lda     levelBgColor
    clc                         ; carry clear = open
    rts

inRange:
    sty     isSolidRow
    jsr     setMapPtr

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
    lsr
    lsr
    lsr
    lsr

test:
    ldy     isSolidRow          ; restore Y
    cmp     levelBgColor
    beq     open
    sec                         ; carry set = solid
    rts
open:
    clc                         ; carry clear = open
    rts

.endproc

;-----------------------------------------------------------------------------
; setMapPtr
;
; Point mapPtr0/1 at the start of the text row holding pixel row Y
; in background
; Rows are $80 bytes and background is page aligned, so
; page = Y/4, offset = $80 if text row is odd
; Preserves X and Y, clobbers A
;-----------------------------------------------------------------------------

.proc   setMapPtr

    lda     #0
    sta     mapPtr0
    tya
    lsr
    lsr                         ; A = Y/4, carry = text row odd
    ror     mapPtr0             ; $80 if odd, carry now 0
    adc     #>background
    sta     mapPtr1
    rts

.endproc

;-----------------------------------------------------------------------------
; setPixel
;
; Set the pixel at level column X, row Y in the background buffer
; to color A (0..15)
; Column wraps at LEVEL_WIDTH
; Preserves X and Y
; Uses mapPtr0/1 for indexing to background
;-----------------------------------------------------------------------------

.proc   setPixel

    sta     pixelColor
    sty     pixelRow
    jsr     setMapPtr

    txa
    and     #LEVEL_WIDTH-1      ; wrap around the level
    tay
    lda     pixelRow
    lsr                         ; carry = odd row
    bcs     odd

    ; Even Y = top pixel of the cell = low nibble
    lda     (mapPtr0),y
    and     #$F0                ; keep bottom pixel
    ora     pixelColor
    sta     (mapPtr0),y
    ldy     pixelRow
    rts

odd:
    ; Odd Y = bottom pixel of the cell = high nibble
    lda     pixelColor
    asl
    asl
    asl
    asl
    sta     pixelColor
    lda     (mapPtr0),y
    and     #$0F                ; keep top pixel
    ora     pixelColor
    sta     (mapPtr0),y
    ldy     pixelRow
    rts

.endproc

;-----------------------------------------------------------------------------
; playerIsSolid
;
; isSolid for the player: same inputs and outputs, but also counts
; spike hits in playerHitSpike (checked at the end of playerUpdate)
;-----------------------------------------------------------------------------

.proc   playerIsSolid

    jsr     isSolid
    bcc     done                ; open
    cmp     levelSpikeColor
    bne     solid
    inc     playerHitSpike      ; doesn't change A or carry
solid:
    sec
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; Player movement and table driven jump
;
; Call playerInit once, then playerUpdate once per game tick (60 ticks/sec)
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

MACHINE_IIE         = 0         ; machineType values
MACHINE_IIC         = 1
MACHINE_IIGS        = 2
PADDLE_TAP_1        = 4         ; drawScreen pass to sample paddle (~1/3)
PADDLE_TAP_2        = 8         ; drawScreen pass to sample paddle (~2/3)
PLAYER_SCREEN_X     = 20        ; middle of the screen

LEVEL_WIDTH         = 128       ; background buffer width (power of 2)
PLAYFIELD_HEIGHT    = 48        ; full screen low-res

COLOR_PLAYER        = $F        ; white (must be $F: drawPlayer only ORs it)

OBJ_NONE            = 0         ; objType values (empty slot)
OBJ_HPLAT           = 1         ; horizontal moving platform
OBJ_VPLAT           = 2         ; vertical moving platform
OBJ_CHECKPOINT      = 3         ; checkpoint column (new respawn point)

PLAT_TICKS          = 12        ; ticks per move (5 cells/sec)

INPUT_LEFT          = %00000001 ; inputState bits (held, not presses)
INPUT_RIGHT         = %00000010
INPUT_JUMP          = %00000100

FLAG_GROUND         = %10000000 ; standing on something (test with BIT/BMI)
FLAG_RISING         = %01000000 ; early in jump, release can cut it

ACCEL               = $06       ; ~8 ticks to top speed (133ms)
DECEL               = $04       ; ~11 ticks to stop (183ms)
MAX_VX              = $2B       ; 0.17 cells/tick (5 cells/sec)

JUMP_LEN            = 35        ; entries in jumpVelLo/Hi
CUT_IDX             = 11        ; early release skips here (first VY >= -0.2)
FALL_IDX            = 19        ; first falling entry: walk-offs, head bumps
COYOTE_TICKS        = 6         ; grace period to jump after walking off ledge
BUFFER_TICKS        = 8         ; how early a press before landing counts
NOT_JUMPING         = $FF       ; playerJumpIdx value while grounded
TERMINAL_VY         = $0080     ; +0.5 rows/tick

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
; Touching a spike (moving into, landing on, standing on or bumping into
; one) during the tick calls onSpikeDeath at the end
;-----------------------------------------------------------------------------

.proc   playerUpdate

    jsr     playerUpdateVX
    jsr     playerMoveX
    jsr     playerCheckWalkOff
    jsr     playerHandleJump
    jsr     playerStepY

    ; Spike touched this tick (including being pushed by a platform)?
    lda     playerHitSpike
    beq     done
    lda     #0
    sta     playerHitSpike
    jmp     onSpikeDeath        ; tail call
done:
    rts

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
    jsr     playerIsSolid
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
    jsr     playerIsSolid
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
; While airborne, add this tick's table velocity (or TERMINAL_VY past the end)
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
    jmp     haveVY
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
    jsr     playerIsSolid
    bcs     land
    jsr     commit
    lda     playerYHi
    cmp     #PLAYFIELD_HEIGHT
    bcc     done
    jmp     advanceLevel        ; tail call (fell off the bottom)

    ; Entering the row above
up:
    cmp     #$FF                ; above row 0: top of screen is a ceiling
    beq     bump
    tay
    ldx     playerXHi
    jsr     playerIsSolid
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
; Level objects
;
; objCount entries in the obj* tables (one table per field, 16 entries
; each in every level so levels can overlay). objType selects what the
; fields mean:
;
;   OBJ_HPLAT  horizontal moving platform
;       objX, objY      left edge column, row
;       objWidth        width in pixels
;       objColor        color (0..15)
;       objMin, objMax  left edge column path limits
;       objDir          1 = right, $FF = left
;
;   OBJ_VPLAT  vertical moving platform
;       objX, objY      left edge column, row
;       objWidth        width in pixels
;       objColor        color (0..15)
;       objMin, objMax  row path limits (top, bottom)
;       objDir          1 = down, $FF = up
;
;   OBJ_CHECKPOINT  1 pixel wide column standing on the ground
;       objX            column
;       objY            base row (where the player respawns)
;       objMin          top row
;       objColor        color (0..15)
;       Touching it (beside it or on top, see checkObjects) makes the
;       base the new respawn point, erases it and calls checkpointReached.
;       Its type is then set to OBJ_NONE.
;
; Objects are drawn into the background buffer, so isSolid and drawScreen
; see them with no extra work. Platforms are 1 pixel high strips. They move 1
; pixel every PLAT_TICKS ticks, turning around at each end of the path.
;
; Paths must only cross empty (levelBgColor) pixels, since moving erases
; to levelBgColor, and must not wrap past column 127.
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; initObjects
;
; Draw every object (type not OBJ_NONE) at its starting position in
; objColor: checkpoints as a column, everything else as an objWidth strip
;-----------------------------------------------------------------------------

.proc   initObjects

    lda     #PLAT_TICKS
    sta     platTimer

    ldx     objCount
loop:
    dex
    bmi     done
    stx     objIndex
    lda     objType,x
    beq     next                ; OBJ_NONE: empty slot
    cmp     #OBJ_CHECKPOINT
    beq     column
    lda     objColor,x
    jsr     drawObjRow
    jmp     next
column:
    lda     objColor,x
    jsr     drawObjColumn
next:
    ldx     objIndex
    jmp     loop
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; moveObjects
;
; Call once per tick, before playerUpdate
;-----------------------------------------------------------------------------

.proc   moveObjects

    dec     platTimer
    bne     done
    lda     #PLAT_TICKS
    sta     platTimer

    ldx     objCount
loop:
    dex
    bmi     done
    stx     objIndex
    lda     objType,x
    cmp     #OBJ_HPLAT
    bne     notHPlat
    jsr     moveHPlat
    jmp     next
notHPlat:
    cmp     #OBJ_VPLAT
    bne     next
    jsr     moveVPlat
next:
    ldx     objIndex
    jmp     loop
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; moveHPlat
;
; Move platform X (= objIndex) one column, carrying a rider and pushing
; the player if the leading edge moves into them (crushed if no room)
;-----------------------------------------------------------------------------

.proc   moveHPlat

    ; Turn around at the ends of the path
    lda     objX,x
    ldy     objDir,x
    bmi     checkLeft
    cmp     objMax,x
    bcc     rider
    lda     #$FF                ; at right end, go left
    sta     objDir,x
    jmp     rider
checkLeft:
    cmp     objMin,x
    beq     turnRight
    bcs     rider
turnRight:
    lda     #1                  ; at left end, go right
    sta     objDir,x

rider:
    jsr     checkRider

    ; Find the leading (new) and trailing (old) columns and move
    lda     objDir,x
    bmi     moveLeft

    lda     objX,x              ; moving right
    sta     platTrail           ; old left edge
    clc
    adc     objWidth,x
    and     #LEVEL_WIDTH-1
    sta     platLead            ; one past old right edge
    lda     objX,x
    clc
    adc     #1
    sta     objX,x
    jmp     push

moveLeft:
    lda     objX,x
    sec
    sbc     #1
    and     #LEVEL_WIDTH-1
    sta     objX,x
    sta     platLead            ; one before old left edge
    clc
    adc     objWidth,x
    and     #LEVEL_WIDTH-1
    sta     platTrail           ; old right edge

    ; Push the player if the leading edge moves into their cell
push:
    lda     objY,x
    cmp     playerYHi
    bne     draw
    lda     platLead
    cmp     playerXHi
    bne     draw
    lda     objDir,x
    jsr     movePlayerX
    bcc     draw
    jsr     onCrushDeath        ; no room to push

    ; Erase the trailing pixel, draw the leading pixel
draw:
    ldx     objIndex
    lda     objColor,x
    sta     platColor
    ldy     objY,x
    ldx     platTrail
    lda     levelBgColor
    jsr     setPixel
    ldx     platLead
    lda     platColor
    jsr     setPixel

    ; Carry the rider
    lda     platRider
    beq     done
    ldx     objIndex
    lda     objDir,x
    jmp     movePlayerX         ; tail call (blocked = scraped off)
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; moveVPlat
;
; Move platform X (= objIndex) one row
;   Up:   anything in the new row (a rider, or an airborne player the
;         platform rises into) is pushed up first, crushed if no room.
;         A pushed airborne player lands on it as they fall.
;   Down: a player in the new row (under it) is pushed down first,
;         crushed if no room. The platform is redrawn before the rider
;         follows, so the rider stays grounded.
;-----------------------------------------------------------------------------

.proc   moveVPlat

    ; Turn around at the ends of the path
    lda     objY,x
    ldy     objDir,x
    bmi     checkTop
    cmp     objMax,x
    bcc     move
    lda     #$FF                ; at bottom, go up
    sta     objDir,x
    jmp     move
checkTop:
    cmp     objMin,x
    beq     turnDown
    bcs     move
turnDown:
    lda     #1                  ; at top, go down
    sta     objDir,x

move:
    lda     objDir,x
    bmi     moveUp

    ; Moving down
    jsr     checkRider          ; before the platform moves
    lda     objY,x
    clc
    adc     #1
    jsr     playerInSpan        ; player under the new row?
    bcc     downDraw
    lda     #1
    jsr     movePlayerY
    bcc     downDraw
    jsr     onCrushDeath        ; no room to push
downDraw:
    ldx     objIndex
    lda     levelBgColor
    jsr     drawObjRow          ; erase old row
    inc     objY,x
    lda     objColor,x
    jsr     drawObjRow          ; draw new row
    lda     platRider
    beq     done
    lda     #1
    jmp     movePlayerY         ; tail call

    ; Moving up
moveUp:
    lda     objY,x
    sec
    sbc     #1
    jsr     playerInSpan        ; player in the new row?
    bcc     upDraw
    lda     #$FF
    jsr     movePlayerY
    bcc     upDraw
    jsr     onCrushDeath        ; no room to push
upDraw:
    ldx     objIndex
    lda     levelBgColor
    jsr     drawObjRow          ; erase old row
    dec     objY,x
    lda     objColor,x
    jsr     drawObjRow          ; draw new row
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; checkRider
;
; Set platRider non-zero if the player is grounded on top of object X
; Preserves X
;-----------------------------------------------------------------------------

.proc   checkRider

    lda     #0
    sta     platRider
    bit     playerFlags
    bpl     done                ; airborne
    ldy     objY,x
    dey
    tya                         ; row above the platform
    jsr     playerInSpan
    bcc     done
    inc     platRider
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; playerInSpan
;
; Carry set if the player is in row A and within the width of object X
; Preserves X
;-----------------------------------------------------------------------------

.proc   playerInSpan

    cmp     playerYHi
    bne     outside
    lda     playerXHi
    sec
    sbc     objX,x              ; column within the object
    and     #LEVEL_WIDTH-1
    cmp     objWidth,x          ; carry clear if inside
    bcs     outside
    sec
    rts
outside:
    clc
    rts

.endproc

;-----------------------------------------------------------------------------
; drawObjRow
;
; Draw object X's row (objWidth pixels at objX, objY) in color A
; Returns with X = objIndex
;-----------------------------------------------------------------------------

.proc   drawObjRow

    sta     platColor
    lda     objWidth,x
    sta     platPixels
    ldy     objY,x
    lda     objX,x
    tax
loop:
    lda     platColor
    jsr     setPixel
    inx
    dec     platPixels
    bne     loop
    ldx     objIndex
    rts

.endproc

;-----------------------------------------------------------------------------
; drawObjColumn
;
; Draw object X's column (objX, rows objMin..objY) in color A
; Returns with X = objIndex
;-----------------------------------------------------------------------------

.proc   drawObjColumn

    sta     platColor
    ldy     objMin,x
    lda     objX,x
    tax
loop:
    lda     platColor
    jsr     setPixel
    tya
    ldx     objIndex
    cmp     objY,x
    beq     done                ; base drawn
    iny
    lda     objX,x
    tax
    jmp     loop
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; checkObjects
;
; Call once per tick, after playerUpdate
; A checkpoint is touched when the player is in the column beside it
; (or its own column) from 1 row above its top down to its base. The
; column is solid, so walking into it or landing on it counts.
;-----------------------------------------------------------------------------

.proc   checkObjects

    ldx     objCount
loop:
    dex
    bmi     done
    lda     objType,x
    cmp     #OBJ_CHECKPOINT
    bne     loop

    lda     playerXHi           ; within 1 column of objX?
    sec
    sbc     objX,x
    clc
    adc     #1                  ; -1..1 -> 0..2
    and     #LEVEL_WIDTH-1
    cmp     #3
    bcs     loop
    ldy     playerYHi           ; playerYHi + 1 >= objMin?
    iny
    tya
    cmp     objMin,x
    bcc     loop
    lda     objY,x              ; playerYHi <= objY?
    cmp     playerYHi
    bcc     loop

    stx     objIndex
    jsr     reachCheckpoint
    ldx     objIndex
    jmp     loop
done:
    rts

.endproc

;-----------------------------------------------------------------------------
; reachCheckpoint
;
; Make checkpoint X (= objIndex) the respawn point, erase it and remove it
;-----------------------------------------------------------------------------

.proc   reachCheckpoint

    lda     objX,x
    sta     playerStartX
    lda     objY,x
    sta     playerStartY
    lda     levelBgColor
    jsr     drawObjColumn       ; erase
    lda     #OBJ_NONE
    sta     objType,x
    jmp     checkpointReached   ; tail call

.endproc

;-----------------------------------------------------------------------------
; movePlayerX
;
; Move the player one column in direction A (1 or $FF) if the cell is
; open. Returns carry set if blocked. Spikes count (playerIsSolid).
;-----------------------------------------------------------------------------

.proc   movePlayerX

    clc
    adc     playerXHi
    and     #LEVEL_WIDTH-1
    tax
    ldy     playerYHi
    jsr     playerIsSolid
    bcs     blocked
    stx     playerXHi
blocked:
    rts

.endproc

;-----------------------------------------------------------------------------
; movePlayerY
;
; Move the player one row in direction A (1 = down, $FF = up) if the
; cell is open. Returns carry set if blocked. Spikes count, and the top
; and bottom of the playfield count as blocked.
;-----------------------------------------------------------------------------

.proc   movePlayerY

    clc
    adc     playerYHi
    cmp     #PLAYFIELD_HEIGHT   ; off the top ($FF) or bottom?
    bcs     blocked             ; (carry set)
    tay
    ldx     playerXHi
    jsr     playerIsSolid
    bcs     blocked
    sty     playerYHi
blocked:
    rts

.endproc

;-----------------------------------------------------------------------------
; Levels
;
; The game runs on the active level (levelData..levelDataEnd: the level
; colors, start, obj* tables and background). Stored levels have the same
; layout and size, so starting a level copies a stored one over it. This
; also undoes anything the last level changed (moved platforms, erased
; checkpoints).
;
; Level 0 is the title page, the game levels start at 1. Falling off the
; bottom of the screen advances to the next level (advanceLevel).
;-----------------------------------------------------------------------------

;-----------------------------------------------------------------------------
; startLevel
;
; Make stored level A the active level, draw its objects and put the
; player at its start
;-----------------------------------------------------------------------------

.proc   startLevel

    sta     currentLevel
    jsr     copyLevel
    jsr     initObjects
    ldx     levelStartX         ; respawn here until a checkpoint is reached
    stx     playerStartX
    ldy     levelStartY
    sty     playerStartY
    jmp     playerInit          ; tail call

.endproc

;-----------------------------------------------------------------------------
; copyLevel
;
; Copy stored level A (0..LEVEL_COUNT-1) over the active level
; Levels are page aligned and LEVEL_PAGES pages long
; Uses mapPtr0/1 (source) and screenPtr0/1 (destination)
;-----------------------------------------------------------------------------

.proc   copyLevel

    tax
    lda     levelPage,x
    sta     mapPtr1
    lda     #>levelData
    sta     screenPtr1
    ldy     #0
    sty     mapPtr0
    sty     screenPtr0
    ldx     #LEVEL_PAGES
loop:
    lda     (mapPtr0),y
    sta     (screenPtr0),y
    iny
    bne     loop
    inc     mapPtr1             ; next page
    inc     screenPtr1
    dex
    bne     loop
    rts

.endproc

;-----------------------------------------------------------------------------
; Player event hooks (sound, stats, etc)
;
; May clobber A, X and Y
; onLanded, onHeadBump and advanceLevel are tail called from playerStepY,
; onSpikeDeath is tail called from playerUpdate,
; checkpointReached is tail called from reachCheckpoint
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

.proc   advanceLevel
    ; Fell off the bottom of the screen: start the next level
    ; (after the last level, back to level 0)
    ; Must not leave playerYHi >= PLAYFIELD_HEIGHT for drawPlayer
    ldx     currentLevel
    inx
    cpx     #LEVEL_COUNT
    bcc     start
    ldx     #0
start:
    txa
    jmp     startLevel          ; tail call
.endproc

.proc   onSpikeDeath
    jmp     respawnPlayer       ; tail call
.endproc

.proc   onCrushDeath
    jmp     respawnPlayer       ; tail call
.endproc

.proc   respawnPlayer
    ; Back to the level start or the last checkpoint reached
    ; TODO: lose a life
    ldx     playerStartX
    ldy     playerStartY
    jmp     playerInit          ; tail call
.endproc

.proc   checkpointReached
    ; Called after a checkpoint is erased and playerStartX/Y updated
    rts
.endproc

;-----------------------------------------------------------------------------
; Global Data
;-----------------------------------------------------------------------------

machineType:    .byte   MACHINE_IIE     ; set by initMachine
screenPage:     .byte   $00     ; Either $00 or $04 to add to line page
scrollOffset:   .byte   0       ; buffer column at left edge, 0..127

inputState:     .byte   0       ; INPUT_* bits held this tick
inputPrev:      .byte   0       ; INPUT_* bits held last tick

paddleTaps:     .byte   1       ; taps paddle 0 was still running (0..2)
tapCompare:     .byte   0       ; drawScreen pass for next paddle tap
paddleInput:    .byte   INPUT_LEFT, 0, INPUT_RIGHT  ; indexed by paddleTaps

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
playerHitSpike: .byte   0       ; non-zero if a spike was touched this tick
playerStartX:   .byte   0       ; respawn column (level start or checkpoint)
playerStartY:   .byte   0       ; respawn row

currentLevel:   .byte   0       ; stored level that is active (0 = title)

isSolidRow:     .byte   0       ; isSolid saves Y here
pixelColor:     .byte   0       ; setPixel color (shifted for odd rows)
pixelRow:       .byte   0       ; setPixel saves Y here

platTimer:      .byte   0       ; ticks until the next platform move
objIndex:       .byte   0       ; object being processed
platPixels:     .byte   0       ; pixels left to draw (drawObjRow)
platColor:      .byte   0       ; color being drawn (drawObjRow)
platLead:       .byte   0       ; column being drawn (moveHPlat)
platTrail:      .byte   0       ; column being erased (moveHPlat)
platRider:      .byte   0       ; non-zero if the player rides this one

; Jump table B (60 ticks/sec): Y velocity per tick, signed 8.8 (rows/tick)
; Same arc as the 30Hz table: per tick velocity halved, gravity quartered.
; Generated from: v0 = -0.5, rise gravity $001A/4 while VY < 0,
; fall gravity $0026/4 while VY >= 0, clamped at +0.5.
; Per tick: VY += g, clamp, Y += VY. Simulated exactly, then each entry
; rounded to 8.8.
; Full jump = 35 ticks, peaks 5 rows up, lands on the start row.
; Regenerate from new constants to re-tune; don't hand edit.

;                   tick: 0   1   2   3   4   5   6   7   8   9  10  11
jumpVelLo:      .byte   $86,$8D,$94,$9A,$A0,$A7,$AE,$B4,$BA,$C1,$C8,$CE
;                   tick: 12 13  14  15  16  17  18  19  20  21  22  23
                .byte   $D4,$DB,$E2,$E8,$EE,$F5,$FC,$02,$0C,$15,$1E,$28
;                   tick: 24 25  26  27  28  29  30  31  32  33  34
                .byte   $32,$3B,$44,$4E,$58,$61,$6A,$74,$7E,$80,$80
jumpVelHi:      .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
                .byte   $FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$00,$00,$00,$00
                .byte   $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
jumpVelEnd:

.assert jumpVelHi - jumpVelLo = JUMP_LEN, error, "jumpVelLo length != JUMP_LEN"
.assert jumpVelEnd - jumpVelHi = JUMP_LEN, error, "jumpVelHi length != JUMP_LEN"


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

;-----------------------------------------------------------------------------
; Level Data
;-----------------------------------------------------------------------------

; Each generated level file starts with .align 256 and is the same size
; (levelData..levelDataEnd). See "Levels" above.

; Active level: global labels (levelBgColor, objX, background, ...) used by
; the game. Starts as a copy of level 0; startLevel copies over it.
.include "level0.asm"

LEVEL_PAGES = (levelDataEnd - levelData) / 256
.assert <levelData = 0, error, "levelData must be page aligned"
.assert (levelDataEnd - levelData) .mod 256 = 0, error, "level size must be whole pages"

; Stored levels: each in its own scope so the labels don't clash
; (e.g. level1Data::levelData)

.proc level0Data
.include "level0.asm"
.endproc

.proc level1Data
.include "level1.asm"
.endproc

; Start page of each stored level, indexed by level number
levelPage:
    .byte   >level0Data::levelData
    .byte   >level1Data::levelData
LEVEL_COUNT = * - levelPage