;-----------------------------------------------------------------------------
; Paul Wasson - 2021
;-----------------------------------------------------------------------------
; Macros
;-----------------------------------------------------------------------------

; 16-bit data
;-----------------------------------------------------------------------------

.macro  Set16 dst,src
    lda     src
    sta     dst
    lda     src+1
    sta     dst+1
.endmacro

.macro  SetImm16 mem,val
    lda     #<val
    sta     mem
    lda     #>val
    sta     mem+1
.endmacro

.macro  AddImm16 mem,val
    lda     mem
    clc
    adc     #<val
    sta     mem
    lda     mem+1
    adc     #>val
    sta     mem+1
.endmacro

.macro  Add8to16 mem,val
    lda     mem
    clc
    adc     val
    sta     mem
    lda     mem+1
    adc     #0
    sta     mem+1
.endmacro

; Strings
;-----------------------------------------------------------------------------

; Add 0 to the end of a string
.macro  String s
    .byte   s
    .byte   0
.endmacro

; Prepend the string length
.macro  StringLen s
    .byte   .strlen(s)
    .byte   s
.endmacro

; Add CR + 0 to the end of a string
.macro  StringCR s
    .byte   s
    .byte   13,0
.endmacro

; Add CR to the end of a string
.macro  StringCont s
    .byte   s
    .byte   13
.endmacro

.macro  MapText s
        .repeat .strlen(s), I
        .byte   .strat(s, I) - $20
        .endrep
.endmacro

.macro  MapString s
        .repeat .strlen(s), I
        .byte   .strat(s, I) + $20
        .endrep
.endmacro

.macro  byteRep b,num
        .repeat num
        .byte   b
        .endrep
.endmacro

.macro  base4Byte db3,db2,db1,db0
        .byte   (db3*64+db2*16+db1*4+db0)
.endmacro
