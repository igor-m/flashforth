;**********************************************************************
;                                                                     *
;    Filename:      FlashForth.asm                                    *
;    Date:          16.11.2011                                        *
;    File Version:  3.8alfa                                           *
;    Copyright:     Mikael Nordman                                    *
;    Author:        Mikael Nordman                                    *
;                                                                     * 
;**********************************************************************
; FlashForth is a standalone Forth system for microcontrollers that
; can flash their own flash memory.
;
; Copyright (C) 2011  Mikael Nordman

; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License version 3 as 
; published by the Free Software Foundation.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;
; Modified versions of FlashForth must be clearly marked as such, 
; in the name of this file, and in the identification
; displayed when FlashForth starts.
;**********************************************************************


.include "m128def.inc"
;.include "m328pdef.inc"
; Macros

  .def zero = r2
  .def t7 = r3
  .def upl = r4
  .def uph = r5

  .def t4  = r6
  .def t5  = r7
  .def t6  = r8
  .def wflags  = r9

  .def ibasel=r10
  .def ibaseh=r11
  .def iaddrl=r12
  .def iaddrh=r13

  .def t0 = r16
  .def t1 = r17
  .def t2 = r18
  .def t3 = r19

  .def pl = r20
  .def ph = r21

  .def FLAGS1 = r22
  .def FLAGS2 = r23
  .def tosl = r24
  .def tosh = r25
;  xl = r26
;  xh = r27
;  yl = r28  ; StackPointer Ylo
;  yh = r29  ; StackPointer Yhi
;  zl = r30
;  zh = r31

.macro poptos 
    ld tosl, Y+
    ld tosh, Y+
.endmacro

.macro pushtos
    st -Y, tosh
    st -Y, tosl
.endmacro

.macro in_
.if (@1 < $40)
  in @0,@1
.else
  lds @0,@1
.endif
.endmacro

.macro out_
.if (@0 < $40)
  out @0,@1
.else
  sts @0,@1
.endif
.endmacro

.macro sbi_
.if (@0 < $40)
  sbi @0,@1
.else
  in_ @2,@0
  ori @2,exp2(@1)
  out_ @0,@2
.endif
.endmacro

.macro cbi_
.if (@0 < $40)
  cbi @0,@1
.else
  in_ @2,@0
  andi @2,~(exp2(@1))
  out_ @0,@2
.endif
.endmacro



.macro fdw
  .dw (@0<<1)
.endmacro

; Symbol naming compatilibity
#if 0
#ifndef SPMEN
.def    SPMEN=SELFPRGEN
#endif
#ifndef EEWE
.def    EEWE=EEPE
#endif
#ifndef EEMWE
.def    EEMWE=EEMPE
#endif
#endif


; Configuration data
#define FC_TYPE_SW
#define clock 16000000  ; 16 MHz 
#define baud  38400
#define ubrr0val (clock/16/baud) - 1
#define ms_value -(clock/1000)
#define IDLE_MODE
;..............................................................................
;Program Specific Constants (literals used in code)
;..............................................................................
; Flash page size
.equ PAGESIZEB=PAGESIZE*2    ; Page size in bytes 
.equ flashPageMask=0x00      ; One byte, no mask needed on 8 bit processor



; Forth word header flags
.equ NFA= 0x80      ; Name field mask
.equ IMMED= 0x40    ; Immediate mask
.equ INLINE= 0x20   ; Inline mask
.equ COMPILE= 0x10  ; Compile only mask
.equ NFAmask= 0xf       ; Name field length mask

; FLAGS2
.equ fLOAD=   2           ; 256 mS Load sample available
.equ fFC=     1           ; 0=Flow Control, 1 = no Flow Control                       
.equ ixoff=   0

; FLAGS1
.equ noclear= 6     ; dont clear optimisation flags 
.equ idup=    5     ; Use dupzeroequal instead of zeroequal
.equ izeroeq= 4     ; Use brne instead of breq if zeroequal
.equ istream= 3
.equ fLOCK=   2
.equ fTAILC=  1
.equ idirty=  0

;;; For Flow Control
.equ XON=   0x11
.equ XOFF=  0x13

.equ CR_=0x0d
.equ LF_=0x0a
.equ BS_=0x08

;;; Memory mapping prefixes
.equ PRAM    = 0x0000  ; 4 Kbytes of ram
.equ PEEPROM = 0x1000  ; 4 Kbytes of eeprom
.equ PFLASH  = 0x2000  ; 56 Kbytes of flash
.equ SFLASH  = 0x9000  ; Start if addressable physical flash on atmega128
.equ PKERNEL = 0xe000  ; Kernel base offset
.equ RAMPZV  = 1

;;; Sizes of the serial RX and TX character queues
.equ rbuf0_size= 4
.equ tbuf0_size= 0
.equ rbuf1_size= 64
.equ tbuf1_size= 0

;;; USER AREA for the OPERATOR task
.equ uaddsize=     0          ; No additional user variables 
.equ ursize=       48         ; 24 cells ret stack size 
.equ ussize=       48         ; 24 cells parameter stack
.equ utibsize=     82         ; 82 character Terminal Input buffer

;;; User variables and area
.equ us0=          -32         ; Start of parameter stack
.equ ur0=          -30         ; Start of ret stack
.equ uemit=        -28         ; User EMIT vector
.equ ukey=         -26         ; User KEY vector
.equ ukeyq=        -24         ; User KEY? vector
.equ ulink=        -22         ; Task link
.equ ubase=        -20         ; Number Base
.equ utib=         -18         ; TIB address
.equ utask=        -16         ; Task area pointer
.equ ustatus=      -14
.equ uflg=         -13
.equ ursave=       -12         ; Saved ret stack pointer
.equ ussave=       -10         ; Saved parameter stack pointer
.equ upsave=       -8
.equ usource=      -6          ; Two cells
.equ utoin=        -2          ; Input stream
.equ uhp=           0          ; Hold pointer


;;; Variables in EEPROM
.equ eeprom=       PEEPROM
.equ dp_start=     eeprom + 0x0000 ; TURNKEY
.equ dp_flash=     eeprom + 0x0002 ; FLASH dictionary pointer
.equ dp_eeprom=    eeprom + 0x0004 ; EEPROM dictionary pointer
.equ dp_ram=       eeprom + 0x0006 ; RAM dictionary pointer
.equ latest=       eeprom + 0x0008 ; Pointer to latest dictionary word
.equ prompt=       eeprom + 0x000a ; Deferred prompt
.equ ehere=        eeprom + 0x000c



;****************************************************
.dseg
ibuf:       .byte PAGESIZEB
ivec:       .byte INT_VECTORS_SIZE

rxqueue0:
rbuf0_wr:    .byte 1
rbuf0_rd:    .byte 1
rbuf0_lv:    .byte 1
rbuf0:       .byte rbuf0_size

rxqueue1:
rbuf1_wr:    .byte 1
rbuf1_rd:    .byte 1
rbuf1_lv:    .byte 1
rbuf1:       .byte rbuf1_size

ms_count:   .byte 2
dpSTART:    .byte 2
dpFLASH:    .byte 2 ; DP's and LATEST in RAM
dpEEPROM:   .byte 2
dpRAM:      .byte 2
dpLATEST:   .byte 2


status:     .byte 1 ; Idle status of all tasks
cse:        .byte 1 ; Current data section 0=flash, 1=eeprom, 2=ram
state:      .byte 1 ; Compilation state
uvars:      .byte   (-us0)
up0:        .byte   2
urbuf:      .byte   ursize
usbuf:      .byte   ussize
utibbuf:    .byte   utibsize
dpdata:     .byte   2


.cseg
.org LARGEBOOTSTART
RESET_:     jmp  WARM_
.org LARGEBOOTSTART + INT0addr
            rcall FF_ISR
.org LARGEBOOTSTART + INT1addr
            rcall FF_ISR
.org LARGEBOOTSTART + INT2addr
            rcall FF_ISR
.org LARGEBOOTSTART + INT3addr
            rcall FF_ISR
.org LARGEBOOTSTART + INT4addr
            rcall FF_ISR
.org LARGEBOOTSTART + INT5addr
            rcall FF_ISR
.org LARGEBOOTSTART + INT6addr
            rcall FF_ISR
.org LARGEBOOTSTART + INT7addr
            rcall FF_ISR
.org LARGEBOOTSTART + OC2addr
            rcall FF_ISR
.org LARGEBOOTSTART + OVF2addr
            rcall FF_ISR
.org LARGEBOOTSTART + ICP1addr
            rcall FF_ISR
.org LARGEBOOTSTART + OC1Aaddr
            rcall FF_ISR
.org LARGEBOOTSTART + OC1Baddr
            rcall FF_ISR
.org LARGEBOOTSTART + OVF1addr
            rcall FF_ISR
.org LARGEBOOTSTART + OC0addr
            rcall FF_ISR
.org LARGEBOOTSTART + OVF0addr
            rcall FF_ISR
.org LARGEBOOTSTART + SPIaddr
            rcall FF_ISR
.org LARGEBOOTSTART + URXC0addr
            rjmp RX0_ISR
.org LARGEBOOTSTART + UDRE0addr
            rcall FF_ISR
.org LARGEBOOTSTART + UTXC0addr
            rcall FF_ISR
.org LARGEBOOTSTART + ADCCaddr
            rcall FF_ISR
.org LARGEBOOTSTART + ERDYaddr
            rcall FF_ISR
.org LARGEBOOTSTART + ACIaddr
            rcall FF_ISR
.org LARGEBOOTSTART + OC1Caddr
            rcall FF_ISR
.org LARGEBOOTSTART + ICP3addr
            rcall FF_ISR
.org LARGEBOOTSTART + OC3Aaddr
            rcall FF_ISR
.org LARGEBOOTSTART + OC3Baddr
            rcall FF_ISR
.org LARGEBOOTSTART + OC3Caddr
            rcall FF_ISR
.org LARGEBOOTSTART + OVF3addr
            rjmp TIMER3_ISR
.org LARGEBOOTSTART + URXC1addr
            rjmp RX1_ISR
.org LARGEBOOTSTART + UDRE1addr
            rcall FF_ISR
.org LARGEBOOTSTART + UTXC1addr
            rcall FF_ISR
.org LARGEBOOTSTART + TWIaddr
            rcall FF_ISR
.org LARGEBOOTSTART + SPMRaddr
            rcall FF_ISR



FF_ISR1:
        st      -y, xh
        in_     xh, SREG
        st      -y, xl
        pop     xh
        pop     xl
        push    zl
        push    zh
        lsl     xl
        rol     xh
        adiw    xl, (ivec&0x3f)
        ldi     xh, 1
        ld      zl, x+
        ld      zh, x+
        ijmp    ;(z)
FF_ISR:
        pop     zero
        pop     zero
        clr     zero        
        reti

TIMER3_ISR:
        push    xl
        in_     xl, SREG
        push    xl
        push    xh
        ldi     xl, low(ms_value)
        ldi     xh, high(ms_value)
        out_    TCNT3H, xh
        out_    TCNT3L, xl
        lds     xl, ms_count
        lds     xh, ms_count+1
        adiw    xl, 1
        sts     ms_count, xl
        sts     ms_count+1, xh
ISR_RETI1:
        pop     xh
        pop     xl
        out_    SREG, xl
        pop     xl
        reti

RX0_ISR:
        push    xl
        in_     xl, SREG
        push    xl
        push    xh
        push    zl
        push    zh

        ldi     zl, low(rbuf0)
        ldi     zh, high(rbuf0)
        lds     xl, rbuf0_wr
        add     zl, xl
        adc     zh, zero
        lds     xh, UDR0
        st      z, xh
        inc     xl
        andi    xl, (rbuf0_size-1)
        sts     rbuf0_wr, xl
        lds     xl, rbuf0_lv
        inc     xl
        sts     rbuf0_lv, xl
        cpi     xl, 2
        brmi    RX0_ISR_SKIP_XOFF
        rcall   XXOFF_TX0       
RX0_ISR_SKIP_XOFF:
        pop     zh
        pop     zl
        rjmp    ISR_RETI1
TX0_ISR:

RX1_ISR:
        push    xl
        in_     xl, SREG
        push    xl
        push    xh
        push    zl
        push    zh

        ldi     zl, low(rbuf1)
        ldi     zh, high(rbuf1)
        lds     xl, rbuf1_wr
        add     zl, xl
        adc     zh, zero
        lds     xh, UDR1
        st      z, xh
        inc     xl
        andi    xl, (rbuf1_size-1)
        sts     rbuf1_wr, xl
        lds     xl, rbuf1_lv
        inc     xl
        sts     rbuf1_lv, xl
        cpi     xl, 2
        brmi    RX1_ISR_SKIP_XOFF
        rcall   XXOFF_TX1       
RX1_ISR_SKIP_XOFF:
        pop     zh
        pop     zl
        rjmp    ISR_RETI1
TX1_ISR:

;;; *************************************************
;;; WARM user area data
.equ warmlitsize= 22
WARMLIT:
        .dw      0x0200                ; cse, state
        .dw      usbuf+ussize-4        ; S0
        .dw      urbuf+ursize-2        ; R0
        fdw      TX1_
        fdw      RX1_
        fdw      RX1Q
        .dw      up0                   ; Task link
        .dw      0x0010                ; BASE
        .dw      utibbuf               ; TIB
        fdw      OPERATOR_AREA         ; TASK
        .dw      0                     ; ustatus & uflg
;;; *************************************************
;;; *************************************
;;; EMPTY dictionary data
.equ coldlitsize=12
;.section user_eedata
COLDLIT:
STARTV: .dw      0
DPC:    .dw      PFLASH
DPE:    .dw      ehere
DPD:    .dw      dpdata
LW:     fdw      lastword
STAT:   fdw      DOTSTATUS

; EXIT --   Compile a return
;        variable link
        .dw     0
EXIT_L:
        .db     NFA|4,"exit",0
EXIT:
        pop     t0
        pop     t0
        ret

; idle
        fdw(EXIT_L)
IDLE_L:
        .db     NFA|4,"idle",0
IDLE:
#ifdef IDLE_MODE
        rcall   IDLE_HELP
        breq    IDLE1
        lds     t0, status 
        dec     t0
        sts     status, t0
#endif
IDLE1:
        ret
        
; busy
        fdw(IDLE_L)
BUSY_L:
        .db     NFA|4,"busy",0
BUSY:
#ifdef IDLE_MODE
        rcall   IDLE_HELP
        brne    BUSY1
        lds     t0, status
        inc     t0
        sts     status, t0
BUSY1:
#endif
        ret


#ifdef IDLE_MODE
IDLE_HELP:
        movw    xl, upl
        sbiw    xl, -ustatus 
        ld      t0, x
        cpi     t0, 0
        ret
#endif
        
; busy
        fdw(BUSY_L)
LOAD_L:
        .db     NFA|4,"load",0
LOAD:
        call    CELL
        ret
        
; [i   --    Save registers for the Forth interrupt context
        fdw(LOAD_L)
LI_L:
        .db     NFA|INLINE|COMPILE|2,"[i",0
        ret

; i]   --    Restore registers for the Forth interrupt context
        fdw(LI_L)
IR_L:
        .db     NFA|INLINE|COMPILE|2,"i]",0
        ret


;***************************************************
; TX0   c --    output character to UART 0
        fdw(IR_L)
TX0_L:
        .db     NFA|3,"tx0"
TX0_:
        rcall   PAUSE
        in_     t0, UCSR0A
        sbrs    t0, UDRE0
        rjmp    TX0_
        out_    UDR0, tosl
        poptos
        ret
;***************************************************
; RX0    -- c    get character from the UART 0 buffer
        fdw(TX0_L)
RX0_L:
        .db     NFA|3,"rx0"
RX0_:
        rcall   PAUSE
        rcall   RX0Q
        call    ZEROSENSE
        breq    RX0_
#if 0
        pushtos
        in_     tosl, UDR0
        clr     tosh
        ret
#else
        pushtos
        ldi     zl, low(rbuf0)
        ldi     zh, high(rbuf0)
        lds     xl, rbuf0_rd
        add     zl, xl
        adc     zh, zero
        ld      tosl, z
        clr     tosh
        cli
        inc     xl
        andi    xl, (rbuf0_size-1)
        sts     rbuf1_rd, xl
        lds     xl, rbuf0_lv
        dec     xl
        sts     rbuf0_lv, xl
        sei
        ret
#endif
;***************************************************
; RX0?  -- n    return the number of characters in queue
        fdw     RX0_L
RX0Q_L:
        .db     NFA|4,"rx0?",0
RX0Q:
#if 0
        in_     t0, UCSR0A
        sbrs    t0, RXC0
        jmp     FALSE_
        jmp     TRUE_
#else
        lds     xl, rbuf0_lv
        cpse    xl, zero
        jmp     TRUE_
        rcall   XXON_TX0
        jmp     FALSE_

XXON_TX0:
        sbrs    FLAGS2, ixoff
        ret     
XXON_TX0_1:
        in_     t0, UCSR0A
        sbrs    t0, UDRE0
        rjmp    XXON_TX0_1
        ldi     t0, XON
        out_    UDR0, t0
        cbr     FLAGS2, (1<<ixoff)
        ret

XXOFF_TX0:
        sbrc    FLAGS2, ixoff
        ret     
XXOFF_TX0_1:
        in_     t0, UCSR0A
        sbrs    t0, UDRE0
        rjmp    XXOFF_TX0_1
        ldi     t0, XOFF
        out_    UDR0, t0
        sbr     FLAGS2, (1<<ixoff)
        ret
#endif

;***************************************************
; TX1   c --    output character to UART 1
        fdw(RX0Q_L)
TX1_L:
        .db     NFA|3,"tx1"
TX1_:
        rcall   PAUSE
        in_     t0, UCSR1A
        sbrs    t0, UDRE1
        rjmp    TX1_
        out_    UDR1, tosl
        poptos
        ret
;***************************************************
; RX1    -- c    get character from the serial line
        fdw(TX1_L)
RX1_L:
        .db     NFA|3,"rx1"
RX1_:
        rcall   PAUSE
        rcall   RX1Q
        call    ZEROSENSE
        breq    RX1_
#if 0
        pushtos
        in_     tosl, UDR1
        clr     tosh
        ret
#else
        pushtos
        ldi     zl, low(rbuf1)
        ldi     zh, high(rbuf1)
        lds     xl, rbuf1_rd
        add     zl, xl
        adc     zh, zero
        ld      tosl, z
        clr     tosh
        cli
        inc     xl
        andi    xl, (rbuf1_size-1)
        sts     rbuf1_rd, xl
        lds     xl, rbuf1_lv
        dec     xl
        sts     rbuf1_lv, xl
        sei
        ret
#endif
;***************************************************
; RX1?  -- n    return the number of characters in queue
        fdw     RX1_L
RX1Q_L:
        .db     NFA|4,"rx1?",0
RX1Q:
#if 0
        in_     t0, UCSR1A
        sbrs    t0, RXC1
        jmp     FALSE_
        jmp     TRUE_
#else
        lds     xl, rbuf1_lv
        cpse    xl, zero
        jmp     TRUE_
        rcall   XXON_TX1
        jmp     FALSE_

XXON_TX1:
        sbrs    FLAGS2, ixoff
        ret
XXON_TX1_1:
        cbr     FLAGS2, (1<<ixoff)
        ldi     t1, XON
        rjmp    TX1_SEND

XXOFF_TX1:
        sbrc    FLAGS2, ixoff
        ret     
XXOFF_TX1_1:
        sbr     FLAGS2, (1<<ixoff)
        ldi     t1, XOFF
TX1_SEND:
        in_     t0, UCSR1A
        sbrs    t0, UDRE1
        rjmp    TX1_SEND
        out_    UDR1, t1
        ret
#endif
;***************************************************
; ?UERR -- f    print message and ABORT if UART framing or overrun error occured
;       dw      link
;link   set     $
        .db     NFA|1,"~"
QUERR:
#if 0
        btfsc   RCSTA, FERR, A
        bra     QUERR1
        btfsc   RCSTA, OERR, A
        bra     QUERR1
        return
QUERR1: movlw   '~'         ; Framing or overrun error
QUERR3: rcall   asmemit
        bcf     RCSTA, CREN, A
        bsf     RCSTA, CREN, A
        goto    ABORT         ;    goto    ABORT
#endif
;*******************************************************
umstar0:
        movw t0, tosl
        poptos
        mul tosl,t0
        movw zl, r0
        clr t2
        clr t3
        mul tosh, t0
        add zh, r0
        adc t2, r1
        adc t3, zero
        mul tosl, t1
        add zh, r0
        adc t2, r1
        adc t3, zero
        mul tosh, t1
        add t2, r0
        adc t3, r1
        movw tosl, zl
        pushtos
        movw tosl, t2
        ret

;***********************************************************
; unsigned 32/16 -> 16/16 division
umslashmod0:
        movw t4, tosl

        ld t3, Y+
        ld t6, Y+
  
        ld t1, Y+
        ld t2, Y+

; unsigned 32/16 -> 16/16 division
        ; set loop counter
        ldi t0,$10 ;6

umslashmod1:
        ; shift left, saving high bit
        clr t7
        lsl t1
        rol t2
        rol t3
        rol t6
        rol t7

        ; try subtracting divisor
        cp  t3, t4
        cpc t6, t5
        cpc t7,zero

        brcs umslashmod2

        ; dividend is large enough
        ; do the subtraction for real
        ; and set lowest bit
        inc t1
        sub t3, t4
        sbc t6, t5

umslashmod2:
        dec  t0
        brne umslashmod1 ;16=17=272

umslashmod3:
        ; put remainder on stack
        st -Y,t6
        st -Y,t3

        ; put quotient on stack
        mov tosl, t1
        mov tosh, t2     ; 6 + 272 + 6 =284 cycles
        ret
; *******************************************************************
; Coded for max 256 byte pagesize !
;if (ibaselo != (iaddrlo&(~(PAGESIZEB-1))))(ibasehi != iaddrhi)
;   if (idirty)
;       writebuffer_to_imem
;   endif
;   fillbuffer_from_imem
;   ibaselo = iaddrlo&(~(PAGESIZEB-1))
;   ibasehi = iaddrhi
;endif
IUPDATEBUF:
        mov     t0, iaddrl
        andi    t0, ~(PAGESIZEB-1)
        cpse    t0, ibasel
        rjmp    IFILL_BUFFER
        cpse    iaddrh, ibaseh
        rjmp    IFILL_BUFFER
        ret

IFILL_BUFFER:
        rcall   XXOFF_TX1_1
        rcall   IFLUSH
        mov     t0, iaddrl
        andi    t0, ~(PAGESIZEB-1)
        mov     ibasel, t0
        mov     ibaseh, iaddrh
IFILL_BUFFER_1:
        ldi     t0, PAGESIZEB&(PAGESIZEB-1)
        movw    zl, ibasel
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
IFILL_BUFFER_2:
        elpm    t1, z+
        st      x+, t1
        dec     t0
        brne    IFILL_BUFFER_2
        ret

IWRITE_BUFFER:
        mov     zl, ibasel
        mov     zh, ibaseh
        ldi     t1, (1<<PGERS) | (1<<SPMEN) ; Page erase
        rcall   DO_SPM
        ldi     t1, (1<<RWWSRE) | (1<<SPMEN); re-enable the RWW section
        rcall   DO_SPM

        ; transfer data from RAM to Flash page buffer
        ldi     t0, low(PAGESIZEB);init loop variable
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
IWRITE_BUFFER1:
        ld      r0, x+
        ld      r1, x+
        ldi     t1, (1<<SPMEN)
        rcall   DO_SPM
        adiw    zl, 2
        subi    t0, 2
        brne    IWRITE_BUFFER1

        ; execute page write
        subi    zl, low(PAGESIZEB) ;restore pointer
        sbci    zh, high(PAGESIZEB)
        ldi     t1, (1<<PGWRT) | (1<<SPMEN)
        rcall   DO_SPM
        ; re-enable the RWW section
        ldi     t1, (1<<RWWSRE) | (1<<SPMEN)
        rcall   DO_SPM
#if 0
        ; read back and check, optional
        ldi     t0, low(PAGESIZEB);init loop variable
        subi    xl, low(PAGESIZEB) ;restore pointer
        sbci    xh, high(PAGESIZEB)
IWRITE_BUFFER2:
        elpm    r0, z+
        ld      r1, x+
        cpse    r0, r1
        jmp     VERIFY_ERROR     ; What to do here ?? reset ?
        subi    t0, 1
        brne    IWRITE_BUFFER2
#endif
        clr     ibaseh
        cbr     FLAGS1, (1<<idirty)
        ; ret to RWW section
        ; verify that RWW section is safe to read
IWRITE_BUFFER3:
        lds     t7, SPMCSR
        sbrs    t7, RWWSB ; If RWWSB is set, the RWW section is not ready yet
        ret
        ; re-enable the RWW section
        ldi     t1, (1<<RWWSRE) | (1<<SPMEN)
        rcall   DO_SPM
        rjmp    IWRITE_BUFFER3

DO_SPM:
        lds     t7, SPMCSR
        sbrc    t7, SPMEN
        rjmp    DO_SPM       ; Wait for previous write to complete
        in      t7, SREG
        cli
        sts     SPMCSR, t1
        spm
        out     SREG, t7
        ret

;***************************************************
NEQUALSFETCH:
        rcall   CFETCHPP
        rcall   ROT
        rcall   CFETCHPP
        jmp     ROT
;***************************************************
; N=    c-addr nfa -- n   string:name cmp
;             n=0: s1==s2, n=ffff: s1!=s2
; N= is specificly used for finding dictionary entries
; It can also be used for comparing strings shorter than 16 characters,
; but the first string must be in ram and the second in program memory.
        fdw     RX1Q_L
NEQUAL_L:
        .db     NFA|2,"n=",0
NEQUAL:
        rcall   NEQUALSFETCH
        andi    tosl, 0xf
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    NEQUAL5
        rcall   ONEMINUS
        rcall   CFETCHPP
        rcall   TOR
        rjmp    NEQUAL4
NEQUAL2:
        rcall   NEQUALSFETCH
        rcall   NOTEQUAL
        rcall   ZEROSENSE
        breq    NEQUAL3
        call    TRUE_
        call    LEAVE
        rjmp    NEQUAL4
NEQUAL3:
        rcall   RFETCH
        rcall   ZEROSENSE
        brne    NEQUAL4
        call    FALSE_
NEQUAL4:
        call    XNEXT
        brcc    NEQUAL2
        pop     t1
        pop     t0
        rjmp    NEQUAL6
NEQUAL5:
        call    TRUE_
NEQUAL6:
        rcall   NIP
        jmp     NIP

; SKIP   c-addr u c -- c-addr' u'
;                          skip matching chars
; u (count) must be smaller than 256
        fdw     NEQUAL_L
SKIP_L:
        .db     NFA|4,"skip",0
SKIP:

        rcall   TOR
SKIP1:
        rcall   DUP
        rcall   ZEROSENSE
        breq    SKIP2
        rcall   OVER
        rcall   CFETCH
        rcall   RFETCH
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    SKIP2
        rcall   ONE
        rcall   SLASHSTRING
        rjmp    SKIP1
SKIP2:
        pop     t0
        pop     t0
        ret


; SCAN   c-addr u c -- c-addr' u'
;                          find matching chars


        fdw     SKIP_L
SCAN_L:
        .db     NFA|4,"scan",0
SCAN:
        rcall   STORE_P_TO_R
        rcall   TOR
        rjmp    SCAN3
SCAN1:
        rcall   CFETCHPP
        call    FETCH_P
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    SCAN3
        rcall   ONEMINUS
        rjmp    SCAN4
SCAN3:
        call    XNEXT
        brcc    SCAN1
SCAN4:
        rcall   RFROM
        rcall   ONEPLUS
        rcall   R_TO_P
        ret

; ei  ( -- )    Enable interrupts
        fdw     SCAN_L
EI_L:
        .db     NFA|INLINE|2,"ei",0
        sei
        ret
        
; di  ( -- )    Disable interrupts
        fdw     EI_L
DI_L:
        .db     NFA|INLINE|2,"di",0
        cli
        ret
        
; ;i  ( -- )    End definition of user interrupt routine
        fdw     DI_L
IRQ_SEMI_L:
        .db     NFA|IMMED|2,";i",0
IRQ_SEMI:
        rcall   DOLIT
        .dw     0x9518      ; reti
        rcall   ICOMMA
        jmp     LEFTBRACKET


; int!  ( addr n  --  )   store interrupt vector
        fdw     DI_L
IRQ_V_L:
        .db     NFA|4,"int!",0
        ; FIXME
        ret

; DOLITERAL  x --           compile DOLITeral x as native code
        fdw     IRQ_V_L
LITERAL_L:
        .db     NFA|IMMED|7,"literal"
LITERAL:
        rcall   DOLIT
        .dw     0x939a          ; st      -Y, tosh
;        pushtos
;        ldi     tosl, 0x9a      ; savettos
;        ldi     tosh, 0x93      ; savettos
        rcall   ICOMMA
        rcall   DOLIT
        .dw     0x938a          ; st      -Y, tosl
;        pushtos
;        ldi     tosl, 0x8a      ; savettos
;        ldi     tosh, 0x93      ; savettos
        rcall   ICOMMA
        rcall   DUP
        mov     tosh, tosl
        swap    tosh
        andi    tosh, 0xf
        andi    tosl, 0xf
        ori     tosh, 0xe0
        ori     tosl, 0x80
        rcall   ICOMMA
        mov     tosl, tosh
        swap    tosh
        andi    tosh, 0xf
        andi    tosl, 0xf
        ori     tosh, 0xe0
        ori     tosl, 0x90
        jmp     ICOMMA

#if 0
LITERALruntime:
        st      -Y, tosh    ; 0x939a
        st      -Y, tosl    ; 0x938a
        ldi     tosl, 0x12  ; 0xe1r2 r=8 (r24)
        ldi     tosh, 0x34  ; 0xe3r4 r=9 (r25)
#endif

;*****************************************************************
ISTORE:
        rcall   LOCKEDQ
        movw    iaddrl, tosl
        rcall   IUPDATEBUF
        poptos
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        mov     t0, iaddrl
        andi    t0, (PAGESIZEB-1)
        add     xl, t0
        st      x+, tosl
        st      x+, tosh
        poptos
        sbr     FLAGS1, (1<<idirty)
        ret

        fdw     LITERAL_L
STORE_L:
        .db     NFA|1, "!"
STORE:
        cpi     tosh, high(PEEPROM)
        brlo    STORE_RAM
        cpi     tosh, high(PFLASH)
        brlo    ESTORE
        rjmp    ISTORE
STORE_RAM:
        movw    zl, tosl
        poptos
        std     Z+1, tosh
        std     Z+0, tosl
        poptos
        ret

ESTORE:
        rcall   LOCKEDQ
        sbic    eecr, eewe
        rjmp    ESTORE
        out     eearl, tosl
        out     eearh, tosh
        poptos
        out     eedr, tosl
        sbi     eecr, eemwe
        sbi     eecr, eewe

ESTORE1:
        sbic    eecr, eewe
        rjmp    ESTORE1

        in      tosl, eearl
        inc     tosl
        out     eearl, tosl

        out     eedr, tosh
        sbi     eecr, eemwe
        sbi     eecr, eewe

        poptos
        ret
LOCKEDQ:
        sbrs    FLAGS1, fLOCK
        ret
        call    DOTS
        rcall   XSQUOTE
        .db     3,"AD?"
        rcall   TYPE
        rjmp    STARTQ2        ; goto    ABORT
        
;***********************************************************
IFETCH:
        movw    z, tosl
        cpse    zh, ibaseh
        rjmp    IIFETCH
        mov     t0, zh
        andi    t0, ~(PAGESIZEB-1)
        cp      t0, ibasel
        brne    IIFETCH
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        andi    zl, (PAGESIZEB-1)
        add     xl, zl
        ld      tosl, x+
        ld      tosh, x+
        ret
IIFETCH:
        ;subi    zh, high(PFLASH)
        elpm    tosl, z+     ; Fetch from Flash directly
        elpm    tosh, z+
        ldi     t0, RAMPZV
        out_    RAMPZ, t0
        ret
                
        fdw     STORE_L
FETCH_L:
        .db     NFA|1, "@"
FETCH:
        cpi     tosh, high(PEEPROM)
        brlo    FETCH_RAM
        cpi     tosh, high(PFLASH)
        brlo    EFETCH
        rjmp    IFETCH
FETCH_RAM:
        movw    zl, tosl
        ld      tosl, z+
        ld      tosh, z+
        ret

EFETCH:
        sbic    eecr, eewe
        rjmp    EFETCH
        out     eearl, tosl
        out     eearh, tosh
        sbi     eecr, eere
        in      tosl, eedr
        in      tosh, eearl
        inc     tosh
        out     eearl, tosh
        sbi     eecr, eere
        in      tosh, eedr
        ret

ICFETCH:
        movw    z, tosl
        cpse    zh, ibaseh
        rjmp    IICFETCH
        mov     t0, zh
        andi    t0, ~(PAGESIZEB-1)
        cp      t0, ibasel
        brne    IICFETCH
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        andi    zl, (PAGESIZEB-1)
        add     xl, zl
        ld      tosl, x+
        clr     tosh
        ret
IICFETCH:
        ;subi    zh, high(PFLASH)
        elpm    tosl, z+     ; Fetch from Flash directly
        clr     tosh
        ldi     t0, RAMPZV
        out_    RAMPZ, t0
        ret

        fdw     FETCH_L
CFETCH_L:
        .db     NFA|2, "c@",0
CFETCH:
        cpi     tosh, high(PEEPROM)
        brlo    CFETCH_RAM
        cpi     tosh, high(PFLASH)
        brlo    ECFETCH
        rjmp    ICFETCH
CFETCH_RAM:
        movw    zl, tosl
        ld      tosl, z+
        clr     tosh
        ret
ECFETCH:
        sbic    eecr, eewe
        rjmp    ECFETCH
        out     eearl, tosl
        out     eearh, tosh
        sbi     eecr, eere
        in      tosl, eedr
        clr     tosh
        ret

ICSTORE:
        rcall   LOCKEDQ
        movw    iaddrl, tosl
        rcall   IUPDATEBUF
        poptos
        ldi     xl, low(ibuf)
        ldi     xh, high(ibuf)
        mov     t0, iaddrl
        andi    t0, (PAGESIZEB-1)
        add     xl, t0
        st      x+, tosl
        poptos
        sbr     FLAGS1, (1<<idirty)
        ret

        fdw     CFETCH_L
CSTORE_L:
        .db     NFA|2, "c!",0
CSTORE:
        cpi     tosh, high(PEEPROM)
        brlo    CSTORE_RAM
        cpi     tosh, high(PFLASH)
        brlo    ECSTORE
        rjmp    ICSTORE
CSTORE_RAM:
        movw zl, tosl
        poptos
        std Z+0, tosl
        poptos
        ret

ECSTORE:
        rcall   LOCKEDQ
        sbic    eecr, eewe
        rjmp    ECSTORE
        out     eearl, tosl
        out     eearh, tosh
        poptos
        out     eedr, tosl
        sbi     eecr, eemwe
        sbi     eecr, eewe
        poptos
        ret

;;; Disable writes to flash and eeprom
        fdw     CSTORE_L
FLOCK_L:
        .db     NFA|3,"fl-"
        sbr     FLAGS1, (1<<fLOCK)
        ret

;;; Enable writes to flash and eeprom
        fdw     FLOCK_L
FUNLOCK_L:
        .db     NFA|3,"fl+"
        cbr     FLAGS1, (1<<fLOCK)
        ret

;;; Enable flow control
        fdw     FUNLOCK_L
FCON_L:
        .db     NFA|3,"u1+"
        cbr     FLAGS2, (1<<fFC)
        ret

;;; Disable flow control
        fdw     FCON_L
FCOFF_L:
        .db     NFA|3,"u1-"
        sbr     FLAGS2, (1<<fFC)
        ret

;;; Clear watchdog timer
        fdw     FCOFF_L
CWD_L:
        .db     NFA|INLINE|3,"cwd"
        wdr
        ret

        fdw     CWD_L
VALUE_L:
        .db     NFA|5,"value"
VALUE:
        call    CREATE
        rcall   COMMA
        call    XDOES
VALUE_DOES:
        rcall   DODOES
        jmp     FETCH

        fdw     VALUE_L
DEFER_L:
        .db     NFA|5,"defer"
DEFER:
        call    CREATE
        rcall   DOLIT
        fdw     ABORT
        rcall   COMMA
        call    XDOES
DEFER_DOES:
        rcall   DODOES
        jmp     FEXECUTE

        fdw     DEFER_L
IS_L:
        .db     NFA|2,"is",0
IS:
        call    TICK
        rcall   TWOPLUS
        rcall   TWOPLUS
        rcall   FETCH
        call    STATE_
        rcall   ZEROSENSE
        breq    IS1
        rcall   LITERAL
        rcall   DOLIT
        fdw     STORE
        rcall   COMMAXT
        rjmp    IS2
IS1:
        rcall   STORE
IS2:
        ret

        fdw     IS_L
TO_L:
        .db     NFA|2,"to",0
TO:
        jmp     IS

        fdw     TO_L
TURNKEY_L:
        .db     NFA|7,"turnkey"
TURNKEY:
        call    VALUE_DOES      ; Must be call for IS to work.
        .dw     dpSTART


;;; *******************************************************
; PAUSE  --     switch task
        fdw     TURNKEY_L
PAUSE_L:
        .db     NFA|5,"pause"
PAUSE:
        lds     t0, status
        cpi     t0, 0
        brne    PAUSE1
        sleep               ; IDLE mode
PAUSE1:
        cli
        push    tosl
        push    tosh
        movw    zl, upl
        sbiw    zl, -ursave
        in      t0, spl
        st      z+, t0
        in      t0, sph
        st      z+, t0
        st      z+, yl
        st      z+, yh
        st      z+, pl
        st      z+, ph
        sbiw    zl, (usource-ulink)
        ld      xl, z+
        ld      xh, z+
        movw    upl, xl
        sbiw    xl, -ursave
        ld      t0, x+
        out     spl, t0
        ld      t0, x+
        out     sph, t0
        pop     tosh
        pop     tosl
        ld      yl, x+
        ld      yh, x+
        ld      pl, x+
        ld      ph, x+
        sei
        ret


        fdw     PAUSE_L
IFLUSH_L:
        .db     NFA|6,"iflush",0
IFLUSH:
        sbrc    FLAGS1, idirty
        rjmp    IWRITE_BUFFER
        ret

; *********************************************
; Bit masking 8 bits, only for ram addresses !
; : mset ( mask addr -- )
;   dup >r c@ swap or r> c!
; ;
        fdw     IFLUSH_L
MSET_L:
        .db     NFA|4,"mset",0
MSET:
        movw    zl, tosl
        poptos
        ld      t0, z
        or      t0, tosl
        st      z, t0
        poptos
        ret
        
; : mclr  ( mask addr -- )
;  dup >r c@ swap invert and r> c!
; ;
        fdw     MSET_L
MCLR_L:
        .db     NFA|4,"mclr",0
MCLR_:
        movw    zl, tosl
        poptos
        ld      t0, z
        com     tosl
        and     t0, tosl
        st      z, t0
        poptos
        ret

; : mtst ( mask addr -- flag )
;   c@ and 
; ;
        fdw     MCLR_L
MTST_L:
        .db     NFA|4,"mtst",0
MTST:
        rcall   CFETCH
        jmp     AND_

        fdw     MTST_L
FCY_L:
        .db     NFA|3,"Fcy"
        rcall   DOCREATE
        .dw     clock / 1000

        fdw     FCY_L
OPERATOR_L:
        .db     NFA|8,"operator",0
OPERATOR:
        rcall   DOCREATE
        fdw     OPERATOR_AREA
OPERATOR_AREA:
        .dw     up0
        .db     uaddsize, ursize
        .db     ussize, utibsize

        fdw     OPERATOR_L
ICOMMA_L:
        .db     NFA|2, "i,",0
ICOMMA:
        call    IHERE
        rcall   STORE
        rcall   CELL
        jmp     IALLOT


;   IHERE ! 1 CHARS IALLOT ;
        fdw     ICOMMA_L
ICCOMMA_L:
        .db     NFA|3,"ic,"
ICCOMMA:
        rcall   IHERE_P
        rcall   CSTORE
        rcall   ONE
        jmp     IALLOT

;   LSHIFT      x1 u -- x2
        fdw     ICCOMMA_L
LSHIFT_L:
        .db     NFA|6,"lshift",0
LSHIFT:
        movw    zl, tosl
        poptos
LSHIFT1:
        sbiw    zl, 1
        brmi    LSHIFT2
        lsl     tosl
        rol     tosh
        rjmp    LSHIFT1
LSHIFT2:
        ret

;   RSHIFT      x1 u -- x2
        fdw     LSHIFT_L
RSHIFT_L:
        .db     NFA|6,"rshift",0
RSHIFT:
        movw    zl, tosl
        poptos
RSHIFT1:
        sbiw    zl, 1
        brmi    RSHIFT2
        lsr     tosh
        ror     tosl
        rjmp    RSHIFT1
RSHIFT2:
        ret

;*******************************************************
; Assembler
;*******************************************************
; FIXME
;*******************************************************
        

        fdw     RSHIFT_L
EMPTY_L:
        .db     NFA|5,"empty"
EMPTY:
        rcall   DOLIT
        fdw     COLDLIT
        rcall   DOLIT
        .dw     dp_start
        rcall   DOLIT
        .dw     coldlitsize
        call    CMOVE
        jmp     DP_TO_RAM
        
;*******************************************************
        fdw     EMPTY_L
WARM_L:
        .db     NFA|4,"warm",0
WARM_:
; Zero memory
        clr     xl
        clr     xh
        ldi     yl, 25
        ldi     yh, 0
WARM_1:
        st      x+, yh
        subi    yl, 1
        brne    WARM_1
        clr     xl
        ldi     xh, 0x01
WARM_2:
        st      x+, t0
        cpi     xh, 0x4
        brne    WARM_2
; Init Stack pointer
        ldi     yl, low(usbuf+ussize-4)
        ldi     yh, high(usbuf+ussize-4)

; Init Return stack pointer
        ldi     t0, low(urbuf+ursize-2)
        ldi     t1, high(urbuf+ursize-2)
        out     spl, t0
        out     sph, t1
; Init user pointer
        ldi     t0, low(up0)
        ldi     t1, high(up0)
        movw    upl, t0
; Set RAMPZ for correct flash addressing
        ldi     t0, RAMPZV
        out_    RAMPZ, t0
; init warm literals
        rcall   DOLIT
        fdw     WARMLIT
        rcall   DOLIT
        .dw     cse
        rcall   DOLIT
        .dw     warmlitsize
        call    CMOVE
; init cold data to eeprom
        rcall   DOLIT
        .dw     dp_start
        rcall   FETCH
        rcall   TRUE_
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    WARM_3  
        rcall   EMPTY
WARM_3:
; Move interrupts to boot flash section
        ldi     t0, (1<<IVCE)
        out_    MCUCR, r16
        ldi     t0, (1<<IVSEL)
        out_    MCUCR, r16

; Init ms timer
        ldi     t0, 1
        out_    TCCR3B, t0
        ldi     t0, (1<<TOIE3)
        out_    ETIMSK, t0
; Init UART
        ; Set baud rate
        ldi     t0, 0
        out_    UBRR1H, t0
        ldi     t0, ubrr0val
        out_    UBRR1L, t0
        ; Enable receiver and transmitter, rx1 interrupts
        ldi     t0, (1<<RXEN1)|(1<<TXEN1)|(1<<RXCIE1)
        out_    UCSR1B,t0
        ; Set frame format: 8data, 1stop bit
        ldi     t0, (1<<USBS1)|(3<<UCSZ10)
        out_    UCSR1C,t0
        ; Init rx1 interrupts

        call    DP_TO_RAM
        sei
        rcall   XXON_TX1_1
        rcall   VER
; Turnkey ?
        rcall   TURNKEY
        rcall   ZEROSENSE
        breq    STARTQ2
        rcall   XSQUOTE
        .db     3,"ESC"
        rcall   TYPE
        rcall   DOLIT
        .dw     0x800
        call    MS
        rcall   KEYQ
        rcall   ZEROSENSE
        breq    STARTQ1
        rcall   KEY
        rcall   DOLIT
        .dw     0x1b
        rcall   EQUAL
        rcall   ZEROSENSE
        brne    STARTQ2
STARTQ1:
        call    TURNKEY
        rcall   EXECUTE
STARTQ2:
        jmp     ABORT
;*******************************************************
        fdw     WARM_L
VER_L:
        .db     NFA|3,"ver"
VER:
        rcall   XSQUOTE
         ;        1234567890123456789012345678901234567890
        .db 19,"FlashForth Atmega",0xd,0xa
        jmp     TYPE

;;; Check parameter stack pointer
        .db     NFA|3,"sp?"
check_sp:
        rcall   SPFETCH
        call    R0_
        rcall   FETCH
        call    S0
        rcall   FETCH
        rcall   ONEPLUS
        rcall   WITHIN
        rcall   XSQUOTE
        .db     3,"SP?"
        call    QABORT
        ret
;***************************************************
; EMIT  c --    output character to the emit vector
        fdw     VER_L
EMIT_L:
        .db     NFA|4,"emit",0
EMIT:
        rcall   UEMIT_
        jmp     FEXECUTE

;***************************************************
; KEY   -- c    get char from UKEY vector
        fdw     EMIT_L
KEY_L:
        .db     NFA|3,"key"
KEY:
        rcall   UKEY_
        jmp     FEXECUTE

;***************************************************
; KEY   -- c    get char from UKEY vector
        fdw     KEY_L
KEYQ_L:
        .db     NFA|4,"key?",0
KEYQ:
        rcall   UKEYQ_
        jmp     FEXECUTE

;***************************************************
; LIT   -- x    fetch inline 16 bit literal to the stack

DOLIT_L:
        .db     NFA|3, "lit"
DOLIT:
        pushtos
        pop     zh
        pop     zl
        lsl     zl
        rol     zh
        elpm    tosl, z+
        elpm    tosh, z+
        ror     zh
        ror     zl
        ijmp    ; (z)

        fdw     KEYQ_L
EXECUTE_L:
        .db     NFA|7,"execute"
EXECUTE:
        movw    zl, tosl
        poptos
        bset    0  ; RAMPV
        ror     zh
        ror     zl
        ijmp

        fdw     EXECUTE_L
FEXECUTE_L:
        .db     NFA|3,"@ex"
FEXECUTE:
        rcall   FETCH
        jmp     EXECUTE

        fdw     FEXECUTE_L
VARIABLE_L:
        .db     NFA|8,"variable",0
VARIABLE_:
        rcall   CREATE
        rcall   CELL
        jmp     ALLOT

        fdw     VARIABLE_L
CONSTANT_L:
        .db     NFA|8,"constant",0
CONSTANT_:
        call    CREATE
        rcall   CELL
        call    NEGATE
        call    IALLOT
        jmp     ICOMMA

        fdw     CONSTANT_L
CON_L:
        .db     NFA|3,"con"
CON:
        rcall   COLON
        rcall   LITERAL
        jmp     SEMICOLON

; DOCREATE, code action of CREATE
; Fetch the next cell from program memory to the parameter stack
DOCREATE_L:
        .db     NFA|3, "(c)"
DOCREATE:
        pushtos
        pop     zh
        pop     zl
        lsl     zl
        rol     zh
        elpm    tosl, z+
        elpm    tosh, z+
        pop     zh
        pop     zl
        ijmp

#if 0
TOS_TO_I:
        pop     zh
        pop     zl
        push    ih
        push    il
        mov     il, tosl
        mov     ih, tosh
        ld      tosl, Y+
        ld      tosh, Y+
        ijmp
#endif
;;; Resolve the runtime action of the word created by using does>
DODOES_L:
        .db     NFA|3, "(d)"
DODOES:
        pop     xh
        pop     xl
        pop     zh
        pop     zl
        lsl     zl
        rol     zh
        pushtos
        elpm    tosl, z+
        elpm    tosh, z+
        movw    z, x
        ijmp    ; (z)

;   SP@     -- addr         get parameter stack pointer
        fdw     CON_L
SPFETCH_L:
        .db     NFA|3,"sp@"
SPFETCH:
        movw    z, y
        pushtos
        movw    tosl, z
        ret

;   SP!     addr --         store stack pointer
        .db     NFA|3,"sp!"
SPSTORE:
        movw    y, tosl
        ret

;   RPEMPTY     -- EMPTY THE RETURN STACK       
        .db     NFA|3,"rp0"
RPEMPTY:
        pop     xh
        pop     xl
        call    R0_
        rcall   FETCH
        out     spl, tosl
        out     sph, tosh
        poptos
        movw    zl, xl
        ijmp

; DICTIONARY POINTER FOR the current section
; Flash -- sets the data section to flash
        fdw     SPFETCH_L
FLASH_L:
ROM_N:  
        .db     NFA|5,"flash"
ROM_:
        clr     t0
        sts     cse, t0
        ret

; EEPROM -- sets the data section to EEPROM data memory
        fdw     FLASH_L
EEPROM_L:
EROM_N: 
        .db     NFA|6,"eeprom",0
EROM:
        ldi     t0, 2
        sts     cse, t0
        ret
        
; RAM -- sets the data section to RAM memory
        fdw     EEPROM_L
RAM_L:
FRAM_N: 
        .db     NFA|3,"ram"
FRAM:
        ldi     t0, 4
        sts     cse, t0
        ret

; DP    -- a-addr          
; Fetched from EEPROM
        fdw     RAM_L
DP_L:
        .db     NFA|2,"dp",0
DP:
        call    IDP
        rcall   CSE_
        jmp     PLUS


;;; 
        .db     NFA|3,"cse"
CSE_:
        pushtos
        lds     tosl, cse
        clr     tosh
        ret

; HERE    -- addr    get current data space ptr
;   DP @ ;
        fdw     DP_L
HERE_L:
        .db     NFA|4,"here",0
HERE:
        rcall   DP
        jmp     FETCH

        .db     NFA|5,"ihere"
IHERE_P: 
        jmp    IHERE
; ,   x --             append cell to current data space
;   HERE ! CELL ALLOT ;
        fdw     HERE_L
COMMA_L:
        .db     NFA|1,","
COMMA:
        rcall   HERE
        rcall   STORE
        rcall   CELL
        jmp     ALLOT

; C,  c --             append char to current data space
;   HERE C! 1 ALLOT ;
        fdw     COMMA_L 
CCOMMA_L:
        .db     NFA|2,"c,",0
CCOMMA:
        rcall   HERE
        rcall   CSTORE
        rcall   ONE
        jmp     ALLOT


; CELL     -- n                 size of one cell
        fdw     CCOMMA_L
CELL_L:
        .db     NFA|4,"cell",0
CELL:
        pushtos
        ldi     tosl, 2
        ldi     tosh, 0
        ret

; ALIGN    --                         align DP
        fdw     CELL_L
ALIGN_L:
        .db     NFA|5,"align"
ALIGN:
        rcall   HERE
        rcall   ALIGNED
        rcall   DP
        jmp     STORE

; ALIGNED  addr -- a-addr       align given addr
        fdw     ALIGN_L
ALIGNED_L:
        .db     NFA|7,"aligned"
ALIGNED:
        adiw    tosl, 1
        rcall   DOLIT
        .dw     0xfffe
        jmp     AND_

; CELL+    a-addr1 -- a-addr2      add cell size
;   2 + ;
        fdw     ALIGNED_L
CELLPLUS_L:
        .db     NFA|5,"cell+"
CELLPLUS:
        adiw    tosl, 2
        ret

; CELLS    n1 -- n2            cells->adrs units
        fdw     CELLPLUS_L
CELLS_L:
        .db     NFA|5,"cells"
CELLS:
        lsl     tosl
        rol     tosh
        ret

; CHAR+    c-addr1 -- c-addr2   add char size
        fdw     CELLS_L
CHARPLUS_L:
        .db     NFA|5,"char+"
CHARPLUS:
        adiw    tosl, 1
        ret

; CHARS    n1 -- n2            chars->adrs units
        fdw     CHARPLUS_L
CHARS_L:
        .db     NFA|INLINE|5,"chars"
CHARS:  ret

        fdw     CHARS_L
COMMAXT_L:
        .db     NFA|3, "cf,"
COMMAXT:
        rcall   DUP
        rcall   IHERE
        rcall   MINUS
        rcall   ABS_ 
        rcall   DOLIT
        .dw     0xff0
        rcall   GREATER
        rcall   ZEROSENSE
        breq    STORECF1
STORECFF1: 
;        rcall   CALL_
        rcall   DOLIT
        .dw     0x940E      ; call jmp:0x940d
        rcall   ICOMMA
        bset    0  ; RAMPV
        ror     tosh
        ror     tosl
        rcall   ICOMMA
        rjmp    STORECF2
STORECF1:
        rcall   IHERE
        rcall   MINUS
        call    TWOMINUS
        call    TWOSLASH
        ;rcall   RCALL_
        andi    tosh, 0x0f
        ori     tosh, 0xd0
        rcall   ICOMMA
STORECF2:
        ret


; !COLON   --       change code field to docolon
;   -6 IALLOT ; 
;       .dw    link
;link   set     $
        .db     NFA|6,"!colon",0
STORCOLON:
        rcall   DOLIT
        .dw     0xfffa         ;  -6
        jmp     IALLOT


; 2@    a-addr -- x1 x2            fetch 2 cells
;   DUP @ SWAP CELL+ @ ;
;   the lower address will appear on top of stack
        fdw     COMMAXT_L
TWOFETCH_L:
        .db     NFA|2,"2@",0
TWOFETCH:
        rcall   DUP
        rcall   FETCH
        rcall   SWOP
        rcall   CELLPLUS
        jmp     FETCH

; 2!    x1 x2 a-addr --            store 2 cells
;   SWAP OVER ! CELL+ ! ;
;   the top of stack is stored at the lower adrs
        fdw     TWOFETCH_L
TWOSTORE_L:
        .db     NFA|2,"2!",0
TWOSTORE:
        rcall   SWOP
        rcall   OVER
        rcall   CELLPLUS
        rcall   STORE
        jmp     STORE

; 2DROP  x1 x2 --                   drop 2 cells
;   DROP DROP ;
        fdw     TWOSTORE_L
TWODROP_L:
        .db     NFA|5,"2drop"
TWODROP:
        rcall   DROP
        jmp     DROP

; 2DUP   x1 x2 -- x1 x2 x1 x2    dup top 2 cells
;   OVER OVER ;
        fdw     TWODROP_L
TWODUP_L:
        .db     NFA|4,"2dup",0
TWODUP:
        rcall   OVER
        jmp     OVER

; 2SWAP   x1 x2 x3 x4 -- x3 x4 x1 x2    dup top 2 cells
        fdw     TWODUP_L
TWOSWAP_L:
        .db     NFA|5,"2swap"
TWOSWAP:
        rcall   ROT
        rcall   TOR
        rcall   ROT
        rcall   RFROM
        ret

; INPUT/OUTPUT ==================================

; SPACE   --                      output a space
;   BL EMIT ;
        fdw     TWOSWAP_L
SPACE_L:
        .db     NFA|5,"space"
SPACE_:  
        call    BL
        jmp     EMIT

; SPACES   n --                  output n spaces
;   BEGIN DUP WHILE SPACE 1- REPEAT DROP ;
        fdw     SPACE_L
SPACES_L:
        .db     NFA|6,"spaces",0
SPACES:
SPCS1:
        rcall   DUPZEROSENSE
        breq    SPCS2
        rcall   SPACE_
        rcall   ONEMINUS
        rjmp    SPCS1
SPCS2:  jmp     DROP


; umin     u1 u2 -- u           unsigned minimum
;   2DUP U> IF SWAP THEN DROP ;
        fdw     SPACES_L
UMIN_L:
        .db     NFA|4,"umin",0
UMIN:
        rcall   TWODUP
        rcall   UGREATER
        rcall   ZEROSENSE
        breq    UMIN1
        rcall   SWOP
UMIN1:  jmp     DROP


; umax    u1 u2 -- u            unsigned maximum
;   2DUP U< IF SWAP THEN DROP ;
        fdw     UMIN_L
UMAX_L:
        .db     NFA|4,"umax",0
UMAX:
        rcall   TWODUP
        rcall   ULESS
        rcall   ZEROSENSE
        breq    UMAX1
        rcall   SWOP
UMAX1:  jmp     DROP

        fdw     UMAX_L
ONE_L:
        .db     NFA|1,"1"
ONE:
        pushtos
        ldi     tosl, 1
        ldi     tosh, 0
        ret

; ACCEPT  c-addr +n -- +n'  get line from terminal
        fdw     ONE_L
ACCEPT_L:
        .db     NFA|6,"accept",0
ACCEPT:
        rcall   OVER
        rcall   PLUS
        rcall   OVER
ACC1:
        rcall   KEY

        cpi     tosl, CR_
        brne    ACC_LF
        
        call    TRUE_
        rcall   FCR
        rcall   CSTORE
        rcall   DROP
        rjmp    ACC6
ACC_LF:
        cpi     tosl, LF_
        brne    ACC2
        rcall   DROP

        rcall   FCR
        rcall   CFETCH
        rcall   ZEROSENSE
        breq    ACC6
        rjmp    ACC1
ACC2:
        call   FALSE_
        rcall   FCR
        rcall   CSTORE
        rcall   DUP
        rcall   EMIT
        rcall   DUP
        rcall   DOLIT
        .dw     BS_
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    ACC3
        rcall   DROP
        rcall   ONEMINUS
        rcall   TOR
        rcall   OVER
        rcall   RFROM
        rcall   UMAX
        rjmp    ACC1
ACC3:
        rcall   OVER
        rcall   CSTORE
        rcall   ONEPLUS
        rcall   OVER
        rcall   UMIN
        rcall   TWODUP
        rcall   NOTEQUAL
        rcall   ZEROSENSE
        brne     ACC1
ACC6:
        rcall   NIP
        rcall   SWOP
        jmp     MINUS

        .db     NFA|3,"fcr"
FCR:
        rcall   DOUSER
        .dw     uflg


; TYPE    c-addr u --   type line to terminal u < $100
; : type for c@+ emit next drop ;

        fdw      ACCEPT_L
TYPE_L:
        .db     NFA|4,"type",0
TYPE:
        rcall   TOR
        rjmp    TYPE2       ; XFOR
TYPE1:  
        rcall   CFETCHPP
        rcall   EMIT
TYPE2:
        call    XNEXT
        brcc    TYPE1
        pop     t1
        pop     t0
        jmp     DROP


; (S"    -- c-addr u      run-time code for S"
        .db      NFA|3,"(s",0x22
XSQUOTE:
        rcall   RFETCH
        lsl     tosl
        rol     tosh
        rcall   CFETCHPP
        rcall   DUP
        rcall   ALIGNED
        lsr     tosh
        ror     tosl
        rcall   RFROM
        rcall   PLUS
;       rcall   ONEPLUS
        rcall   TOR
        ret

        fdw     TYPE_L
SQUOTE_L:
        .db      NFA|IMMED|COMPILE|2,"s",0x22,0
SQUOTE:
        rcall   DOLIT
        fdw     XSQUOTE
        rcall   COMMAXT
        rcall   ROM_
        rcall   CQUOTE
        jmp     FRAM

        fdw     SQUOTE_L
CQUOTE_L:
        .db     NFA|2,",",0x22,0
CQUOTE: 
        rcall   DOLIT
        .dw     0x22
        rcall   PARSE
        rcall   HERE
        rcall   OVER
        rcall   ONEPLUS
        rcall   ALIGNED
        rcall   ALLOT
        jmp     PLACE


        fdw     CQUOTE_L
DOTQUOTE_L:
        .db      NFA|IMMED|COMPILE|2,".",0x22,0
DOTQUOTE:
        rcall   SQUOTE
        rcall   DOLIT
        fdw     TYPE
        jmp     COMMAXT

        fdw     DOTQUOTE_L
ALLOT_L:
        .db     NFA|5,"allot"
ALLOT:
        rcall   DP
        jmp     PLUSSTORE

        fdw     ALLOT_L
DROP_L:
        .db     NFA|4,"drop",0
DROP:
        poptos
        ret

        fdw     DROP_L
SWOP_L:
        .db     NFA|4,"swap",0
SWOP:
        ld      t0, y+
        ld      t1, y+
        pushtos
        movw    tosl, t0
        ret

        fdw     SWOP_L
OVER_L:
        .db     NFA|4,"over",0
OVER:
        pushtos
        ldd     tosl, y+2
        ldd     tosh, y+3
        ret

        fdw     OVER_L
ROT_L:
        .db     NFA|3, "rot"
ROT:
        rcall   TOR
        rcall   SWOP
        rcall   RFROM
        rjmp    SWOP

        fdw     ROT_L
TOR_L:
        .db     NFA|COMPILE|2,">r",0
TOR:
        pop     zh
        pop     zl
        push    tosl
        push    tosh
        poptos
        ijmp

        fdw     TOR_L
RFROM_L:
        .db     NFA|COMPILE|2,"r>",0
RFROM:
        pop     zh
        pop     zl
        pushtos
        pop     tosh
        pop     tosl
        ijmp

        fdw     RFROM_L
RFETCH_L:
        .db     NFA|COMPILE|2,"r@",0
RFETCH:
        pop     zh
        pop     zl
        pushtos
        pop     tosh
        pop     tosl
        push    tosl
        push    tosh
        ijmp


        fdw     RFETCH_L
DUP_L:
        .db     NFA|3, "dup"
DUP:
        pushtos
        ret

;   ABS     n   --- n1      absolute value of n
        fdw     DUP_L
ABS_L:
        .db     NFA|3,"abs"
ABS_:
        rcall   DUP
        jmp     QNEGATE

        fdw     ABS_L
PLUS_L:
        .db     NFA|1, "+"

PLUS:
        ld      t0, Y+        
        ld      t1, Y+
        add     tosl, t0
        adc     tosh, t1
        ret

; m+  ( d n -- d1 )
        fdw     PLUS_L
MPLUS_L:
        .db     NFA|2, "m+",0
MPLUS:
        push    t2
        push    t3
        ld      t2, Y+
        ld      t3, Y+
        ld      t0, Y+
        ld      t1, Y+
        add     t0, tosl
        adc     t1, tosh
        clr     tosl
        adc     tosl, t2
        clr     tosh
        adc     tosh, t3
        st      -Y, t1
        st      -Y, t0
        pop     t3
        pop     t2
        ret


        fdw     MPLUS_L
MINUS_L:
        .db     NFA|1, "-"
MINUS:
        ld      t0, Y+
        ld      t1, Y+
        sub     t0, tosl
        sbc     t1, tosh
        movw    tosl, t0
        ret

        fdw     MINUS_L
AND_L:
        .db     NFA|3, "and"
AND_:
        ld      t0, Y+
        ld      t1, Y+
        and     tosl, t0
        and     tosh, t1
        ret

        fdw     AND_L
OR_L:
        .db     NFA|2, "or",0
OR_:
        ld      t0, Y+
        ld      t1, Y+
        or      tosl, t0
        or      tosh, t1
        ret

        fdw     OR_L
XOR_L:
        .db     NFA|3, "xor"
XOR_:
        ld      t0, Y+
        ld      t1, Y+
        eor     tosl, t0
        eor     tosh, t1
        ret

        fdw     XOR_L
INVERT_L:
        .db     NFA|6, "invert",0
INVERT:
        com     tosl
        com     tosh
        ret

        fdw     INVERT_L
NEGATE_L:
        .db     NFA|6, "negate",0
NEGATE:
        rcall   INVERT
        jmp     ONEPLUS

        fdw     NEGATE_L
ONEPLUS_L:
        .db     NFA|INLINE|2, "1+",0
ONEPLUS:
        adiw    tosl, 1
        ret

        fdw     ONEPLUS_L
ONEMINUS_L:
        .db     NFA|INLINE|2, "1-",0
ONEMINUS:
        sbiw    tosl, 1
        ret

        fdw     ONEMINUS_L
TWOPLUS_L:
        .db     NFA|INLINE|2, "2+",0
TWOPLUS:
        adiw    tosl, 2
        ret

        fdw     TWOPLUS_L
TOBODY_L:
        .db     NFA|INLINE|5, ">body"
TOBODY:
        adiw    tosl, 4
        ret

        fdw     TOBODY_L
TWOSTAR_L:
        .db     NFA|INLINE|2, "2*",0
TWOSTAR:
        lsl     tosl
        rol     tosh
        ret

        fdw     TWOSTAR_L
TWOSLASH_L:
        .db     NFA|INLINE|2, "2/",0
TWOSLASH:
        asr     tosh
        ror     tosl
        ret

        fdw     TWOSLASH_L
PLUSSTORE_L:
        .db     NFA|2,"+!",0
PLUSSTORE:
        rcall   SWOP
        rcall   OVER
        rcall   FETCH
        rcall   PLUS
        rcall   SWOP
        jmp     STORE

        fdw     PLUSSTORE_L
WITHIN_L:
        .db     NFA|6,"within",0
WITHIN:
        rcall   OVER
        rcall   MINUS
        rcall   TOR
        rcall   MINUS
        rcall   RFROM
        jmp     ULESS

        fdw     WITHIN_L
NOTEQUAL_L:
        .db     NFA|2,"<>",0
NOTEQUAL:
        jmp     XOR_

        fdw     NOTEQUAL_L
ZEROEQUAL_L:
        .db     NFA|2, "0=",0
ZEROEQUAL:      
        or      tosh, tosl
        brne    FALSE_F
TRUE_F:
        ser     tosh
        ser     tosl
ZEROEQUAL_1:
        ret

        fdw     ZEROEQUAL_L
ZEROLESS_L:
        .db     NFA|2, "0<",0
ZEROLESS:
        tst     tosh
        brmi    TRUE_F
FALSE_F:
        clr     tosh
        clr     tosl
        ret

        fdw     ZEROLESS_L
EQUAL_L:
        .db     NFA|1, "="
EQUAL:
        rcall   MINUS
        jmp     ZEROEQUAL


        fdw     EQUAL_L
LESS_L:
        .db     NFA|1,"<"
LESS:
        rcall   MINUS
        jmp     ZEROLESS

        fdw     LESS_L
GREATER_L:
        .db     NFA|1,">"
GREATER:
        rcall   SWOP
        jmp     LESS

        fdw     GREATER_L
ULESS_L:
        .db     NFA|2,"u<",0
ULESS:
        rcall   MINUS
        brmi    TRUE_F        ; Carry test  
        jmp     FALSE_F


        fdw     ULESS_L
UGREATER_L:
        .db     NFA|2, "u>",0
UGREATER:
        rcall   SWOP
        jmp     ULESS

        fdw     UGREATER_L
STORE_P_L:
        .db     NFA|2,"!p",0
STORE_P:
        movw    pl, tosl
        poptos
        ret

        fdw     STORE_P_L
STORE_P_TO_R_L:
        .db     NFA|COMPILE|4,"!p>r",0
STORE_P_TO_R:
        pop     zh
        pop     zl
        push    pl
        push    ph
        movw    pl, tosl
        poptos
        ijmp

        fdw     STORE_P_TO_R_L
R_TO_P_L:
        .db     NFA|COMPILE|3,"r>p"
R_TO_P:
        pop     zh
        pop     zl
        pop     ph
        pop     pl
        ijmp

        fdw     R_TO_P_L
PFETCH_L:
        .db     NFA|2,"p@",0
PFETCH:
        pushtos
        movw    tosl, pl
        jmp     FETCH

        fdw     PFETCH_L
PSTORE_L:
        .db     NFA|2,"p!",0
PSTORE:
        pushtos
        movw    tosl, pl
        jmp     STORE

        fdw     PSTORE_L
PCSTORE_L:
        .db     NFA|3,"pc!"
PCSTORE:
        pushtos
        movw    tosl, pl
        jmp     CSTORE

        fdw     PCSTORE_L
PPLUS_L:
        .db     NFA|2,"p+",0
PPLUS:
        inc     pl
        brne    PPLUS1
        inc     ph
PPLUS1:
        ret

        fdw     PPLUS_L
PNPLUS_L:
        .db     NFA|3,"p++"
PNPLUS:
        add     pl, tosl
        adc     ph, tosh
        poptos
        ret

        fdw     PNPLUS_L
UEMIT_L:
        .db     NFA|5,"'emit"
UEMIT_:
        rcall   DOUSER
        .dw     uemit
        
        fdw     UEMIT_L
UKEY_L:
        .db     NFA|4,"'key",0
UKEY_:
        rcall   DOUSER
        .dw     ukey

        fdw     UKEY_L
UKEYQ_L:
        .db     NFA|5,"'key?"
UKEYQ_:
        rcall   DOUSER
        .dw     ukeyq

        .db     NFA|3,"?0="
ZEROSENSE:
        sbiw    tosl, 0
        poptos
        ret

        .db     NFA|3,"d0="
DUPZEROSENSE:
        sbiw    tosl, 0
        ret

        fdw     UKEYQ_L
UMSTAR_L:
        .db     NFA|3,"um*"
UMSTAR:
        jmp     umstar0

        fdw     UMSTAR_L
UMSLASHMOD_L:
        .db     NFA|6,"um/mod",0
UMSLASHMOD:
        jmp     umslashmod0


        fdw     UMSLASHMOD_L
USLASHMOD_L:
        .db     NFA|5,"u/mod"
USLASHMOD:
        rcall   FALSE_
        rcall   SWOP
        jmp     umslashmod0

        fdw     USLASHMOD_L
STAR_L:
        .db     NFA|1,"*"
STAR: 
        rcall   UMSTAR
        jmp     DROP

        fdw     STAR_L
USLASH_L:
        .db     NFA|2,"u/",0
USLASH:
        rcall   USLASHMOD
        jmp     NIP

        fdw     USLASH_L
USSMOD_L:
        .db     NFA|6,"u*/mod",0
USSMOD:
        rcall   TOR
        rcall   UMSTAR
        rcall   RFROM
        jmp     UMSLASHMOD


        fdw     USSMOD_L
SLASH_L:
        .db     NFA|1,"/"
SLASH: 
        rcall   TWODUP
        rcall   XOR_
        rcall   TOR
        rcall   ABS_
        rcall   SWOP
        rcall   ABS_
        rcall   SWOP
        rcall   USLASH
        rcall   RFROM
        jmp     QNEGATE

        fdw     SLASH_L
NIP_L:
        .db     NFA|3,"nip"
NIP:
        rcall   SWOP
        jmp     DROP
    
        fdw     NIP_L
TUCK_L:
        .db     NFA|4,"tuck",0
TUCK:
        rcall   SWOP
        jmp     OVER

        fdw     TUCK_L
QNEGATE_L:
        .db     NFA|7,"?negate"
QNEGATE:
        rcall   ZEROLESS
        rcall   ZEROSENSE
        breq    QNEGATE1
        rcall   NEGATE
QNEGATE1:
        ret

        fdw     QNEGATE_L
MAX_L:
        .db     NFA|3,"max"
MAX:    rcall   TWODUP
        rcall   LESS
        rcall   ZEROSENSE
        breq    max1
        rcall   SWOP
max1:   jmp     DROP

        fdw     MAX_L
MIN_L:
        .db     NFA|3,"min"
MIN:    rcall   TWODUP
        rcall   GREATER
        rcall   ZEROSENSE
        brne    pc+2
        rjmp    min1
;        breq    min1
        rcall   SWOP
min1:   jmp     DROP

        .db     NFA|2,"c@",0
CFETCH_A:       
        rjmp    CFETCH

        fdw     MIN_L
UPTR_L:
        .db     NFA|2,"up",0
UPTR:   rcall   DOCREATE_A
        .dw     4 ; upl

        fdw     UPTR_L
HOLD_L:
        .db     NFA|4,"hold",0
HOLD:   rcall   TRUE_
        rcall   HP
        rcall   PLUSSTORE
        rcall   HP
        rcall   FETCH
        jmp     CSTORE

; <#    --              begin numeric conversion
;   PAD HP ! ;          (initialize Hold Pointer)
        fdw     HOLD_L
LESSNUM_L:
        .db     NFA|2,"<#",0
LESSNUM: 
        rcall   PAD
        rcall   HP
        jmp     STORE

; >digit   n -- c            convert to 0..9a..z
        fdw     LESSNUM_L
TODIGIT_L:
        .db     NFA|6,">digit",0
TODIGIT: 
        rcall   DUP
        rcall   DOLIT_A
        .dw     9
        rcall   GREATER
        rcall   DOLIT_A
        .dw     0x27
        rcall   AND_
        rcall   PLUS
        rcall   DOLIT_A
        .dw     0x30
        jmp     PLUS

; #     ud1 -- ud2     convert 1 digit of output
;   base @ ud/mod rot >digit hold ;
        fdw     TODIGIT_L
NUM_L:
        .db     NFA|1,"#"
NUM:
        rcall   BASE
        rcall   FETCH
        rcall   UDSLASHMOD
        rcall   ROT
        rcall   TODIGIT
        jmp     HOLD

; #S    ud1 -- ud2      convert remaining digits
;   begin # 2dup or 0= until ;
        fdw     NUM_L
NUMS_L:
        .db     NFA|2,"#s",0
NUMS:
        rcall   NUM
        rcall   TWODUP
        rcall   OR_
        rcall   ZEROSENSE
        brne    NUMS
        ret

; #>    ud1 -- c-addr u    end conv., get string
;   2drop hp @ pad over - ;
        fdw     NUMS_L
NUMGREATER_L:
        .db     NFA|2,"#>", 0
NUMGREATER:
        rcall   TWODROP
        rcall   HP
        rcall   FETCH
        rcall   PAD
        rcall   OVER
        jmp     MINUS

; SIGN  n --               add minus sign if n<0
;   0< IF 2D HOLD THEN ; 
        fdw     NUMGREATER_L
SIGN_L:
        .db     NFA|4,"sign",0
SIGN:   
        rcall   ZEROLESS
        rcall   ZEROSENSE
        breq    SIGN1
        rcall   DOLIT_A
        .dw     0x2D
        rcall   HOLD
SIGN1:
        ret

; U.    u --                  display u unsigned
;   <# 0 #S #> TYPE SPACE ;
        fdw     SIGN_L
UDOT_L:
        .db     NFA|2,"u.",0
UDOT:
        rcall   LESSNUM
        rcall   FALSE_
        rcall   NUMS
        rcall   NUMGREATER
        rcall   TYPE
        jmp     SPACE_


; U.R    u +n --      display u unsigned in field of n. 1<n<=255 
;    0 swap <# 1- for # next #s #> type space ;
        fdw     UDOT_L
UDOTR_L:
        .db     NFA|3,"u.r"
UDOTR:
        rcall   LESSNUM
        rcall   ONEMINUS
        rcall   TOR
        rcall   FALSE_
        rjmp    UDOTR2
UDOTR1:
        rcall   NUM
UDOTR2: 
        rcall   XNEXT
        brcc    UDOTR1
        pop     t1
        pop     t0
        rcall   NUMS
        rcall   NUMGREATER
        rcall   TYPE
        jmp     SPACE_

; .     n --                    display n signed
;   <# DUP ABS #S SWAP SIGN #> TYPE SPACE ;
        fdw     UDOTR_L
DOT_L:
        .db     NFA|1,"."
DOT:    rcall   LESSNUM
        rcall   DUP
        rcall   ABS_
        rcall   FALSE_
        rcall   NUMS
        rcall   ROT
        rcall   SIGN
        rcall   NUMGREATER
        rcall   TYPE
        jmp     SPACE_

        FDW     DOT_L
DECIMAL_L:
        .db     NFA|7,"decimal"
DECIMAL: 
        rcall   TEN
        rcall   BASE
        jmp     STORE

; HEX     --              set number base to hex
;   #16 BASE ! ;
        Fdw     DECIMAL_l
HEX_L:
        .db     NFA|3,"hex"
HEX:
        rcall   DOLIT_A
        .dw     16
        rcall   BASE
        jmp     STORE

; BIN     --              set number base to binary
;   #2 BASE ! ;
        Fdw     HEX_L
BIN_L:
        .db     NFA|3,"bin"
BIN:    rcall   CELL
        rcall   BASE
        jmp     STORE

#ifndef SKIP_MULTITASKING
; RSAVE   -- a-addr     Saved return stack pointer
        fdw     BIN_L
RSAVE_L:
        .db     NFA|5,"rsave"
RSAVE_: rcall   DOUSER
        .dw     ursave


; SSAVE   -- a-addr     Saved parameter stack pointer
        fdw     RSAVE_L
SSAVE_L:
        .db     NFA|5,"ssave"
SSAVE_: rcall   DOUSER
        .dw     ussave


; ULINK   -- a-addr     link to next task
        fdw     SSAVE_L
ULINK_L:
        .db     NFA|5,"ulink"
ULINK_: rcall   DOUSER
        .dw     ulink


; TASK       -- a-addr              TASK pointer
        fdw     ULINK_L
#else
        fdw     BIN_L
#endif
TASK_L:
        .db     NFA|4,"task",0
TASK:   rcall   DOUSER
        .dw     utask


; HP       -- a-addr                HOLD pointer
        fdw     TASK_L
HP_L:
        .db     NFA|2,"hp",0
HP:     rcall   DOUSER
        .dw     uhp

; PAD     -- a-addr        User Pad buffer
        fdw     HP_L
PAD_L:
        .db     NFA|3,"pad"
PAD:
        rcall   TIB
        rcall   TIBSIZE
        jmp     PLUS

; BASE    -- a-addr       holds conversion radix
        fdw     PAD_L
BASE_L:
        .db     NFA|4,"base",0
BASE:
        rcall   DOUSER
        .dw     ubase

; USER   n --
        fdw     BASE_L
USER_L:
        .db     NFA|4,"user",0
USER:
        rcall   CONSTANT_
        rcall   XDOES
DOUSER:
        pushtos
        pop     zh
        pop     zl
        lsl     zl
        rol     zh
        elpm    tosl, z+
        elpm    tosh, z+
        add     tosl, upl
        adc     tosh, uph
        ret

; SOURCE   -- adr n         current input buffer
;   'SOURCE 2@ ;        length is at higher adrs
        fdw     USER_L
SOURCE_L:
        .db     NFA|6,"source",0
SOURCE:
        rcall   TICKSOURCE
        jmp     TWOFETCH

; /STRING  a u n -- a+n u-n          trim string
;   swap over - >r + r>
        fdw      SOURCE_L
SLASHSTRING_L:
        .db     NFA|7,"/string"
SLASHSTRING:
        rcall   SWOP
        rcall   OVER
        rcall   MINUS
        rcall   TOR
        rcall   PLUS
        rcall   RFROM
        ret

; \     Skip the rest of the line
        fdw     SLASHSTRING_L
BSLASH_L:
        .db     NFA|IMMED|1,0x5c
BSLASH:
        rcall   SOURCE
        rcall   TOIN
        rcall   STORE_A
        sbr     FLAGS1, (1<<noclear)  ; dont clear flags in case of \
        jmp     DROP

; PARSE  char -- c-addr u
        fdw     BSLASH_L
PARSE_L:
        .db     NFA|5,"parse"
PARSE:
        rcall   DUP             ; c c
        rcall   SOURCE          ; c c a u
        rcall   TOIN            ; c c a u a
        rcall   FETCH_A         ; c c a u n
        rcall   SLASHSTRING     ; c c a u   new tib addr/len
        rcall   DUP             ; c c a u u
        rcall   TOR             ; c c a u                  R: u (new tib len
        rcall   ROT             ; c a u c
        call    SKIP            ; c a u        
        rcall   OVER            ; c a u a
        rcall   TOR             ; c a u                    R: u a (start of word
        rcall   ROT             ; a u c
        call    SCAN            ; a u      end of word, tib left       
        rcall   DUPZEROSENSE
        breq    PARSE1
        rcall   ONEMINUS
PARSE1: rcall   RFROM           ; a u a
        rcall   RFROM           ; a u a u
        rcall   ROT             ; a a u u
        rcall   MINUS           ; a a n  ( addition to toin
        rcall   TOIN
        rcall   PLUSSTORE       ; aend astart
        rcall   TUCK            ; astart aend astart
        jmp     MINUS           ; astart wlen
     

; WORD   char -- c-addr        word delimited by char and/or TAB
        fdw     PARSE_L
WORD_L:
        .db     NFA|4,"word",0
WORD:
        rcall   PARSE           ; c-addr wlen
        rcall   SWOP
        rcall   ONEMINUS
        rcall   TUCK
        jmp     CSTORE          ; Write the length into the TIB ! 

; CMOVE  src dst u --  copy u bytes from src to dst
; cmove swap !p for c@+ pc! p+ next drop ;
        fdw     WORD_L
CMOVE_L:
        .db     NFA|5,"cmove"
CMOVE:
        rcall   SWOP
        rcall   STORE_P_TO_R
        rcall   TOR
        rjmp    CMOVE2
CMOVE1:
        rcall   CFETCHPP
        rcall   PCSTORE
        rcall   PPLUS
CMOVE2:
        rcall   XNEXT
        brcc    CMOVE1
        pop     t1
        pop     t0
        rcall   R_TO_P
        jmp     DROP


; place  src n dst --     place as counted str
        fdw     CMOVE_L
PLACE_L:
        .db     NFA|5,"place"
PLACE: 
        rcall   TWODUP
        call    CSTORE
        call    CHARPLUS
        rcall   SWOP
        jmp     CMOVE

; :     c@+ ( addr -- addr+1 n ) dup 1+ swap c@ ;
        fdw     PLACE_L
CFETCHPP_L:
        .db     NFA|3,"c@+"
CFETCHPP:
        rcall   DUP
        rcall   ONEPLUS
        rcall   SWOP
        jmp     CFETCH

; :     @+ ( addr -- addr+2 n ) dup 2+ swap @ ;
        fdw     CFETCHPP_L
FETCHPP_L:
        .db     NFA|2,"@+",0
FETCHPP:
        rcall   DUP
        rcall   TWOPLUS
        rcall   SWOP
        jmp     FETCH

        .db     NFA|1,"!"
STORE_A:        
        jmp     STORE

; N>C   nfa -- cfa    name adr -> code field
        fdw    FETCHPP_L
NTOC_L:
        .db     NFA|3,"n>c"
NFATOCFA:
        rcall   CFETCHPP
        rcall   DOLIT_A
        .dw     0x0f
        rcall   AND_
        rcall   PLUS
        jmp     ALIGNED

; C>N   cfa -- nfa    code field addr -> name field addr
        fdw    NTOC_L
CTON_L:
        .db     NFA|3,"c>n"
CFATONFA:
        rcall   TWOMINUS
        rcall   DUP
        rcall   CFETCH_A
        rcall   DOLIT_A
        .dw     0x007F
        rcall   GREATER
        rcall   ZEROSENSE
        breq    CFATONFA
        ret

; findi   c-addr nfa -- c-addr 0   if not found
;                          xt  1      if immediate
;                          xt -1      if "normal"
        fdw     CTON_L
BRACFIND_L:
        .db     NFA|3,"(f)"
findi:
findi1:
FIND_1: 
        call    TWODUP
;        rcall   OVER
;        rcall   CFETCH_A
        call    NEQUAL
        rcall   DUPZEROSENSE
        breq    findi2
        rcall   DROP
        rcall   TWOMINUS ;;;      NFATOLFA
        rcall   FETCH_A
        rcall   DUP
findi2:
        rcall   ZEROSENSE
        brne    findi1
        rcall   DUPZEROSENSE
        breq    findi3
        rcall   NIP
        rcall   DUP
        rcall   NFATOCFA
        rcall   SWOP
        rcall   IMMEDQ
        rcall   ZEROEQUAL
        rcall   ONE
        rcall   OR_
findi3: 
        ret
;        jmp     PAUSE

; IMMED?    nfa -- f        fetch immediate flag
        fdw     BRACFIND_L
IMMEDQ_L:
        .db     NFA|6,"immed?",0
IMMEDQ: 
        rcall   CFETCH_A
        mov     wflags, tosl  ; COMPILE and INLINE flags for the compiler
        rcall   DOLIT_A
        .dw     IMMED
        jmp     AND_

; FIND   c-addr -- c-addr 0   if not found
;                  xt  1      if immediate
;                  xt -1      if "normal"
        fdw     IMMEDQ_L
FIND_L:
        .db     NFA|4,"find",0
FIND:   
        rcall   DOLIT_A
        fdw     kernellink
        rcall   findi
        rcall   DUPZEROSENSE
        brne    FIND1
        rcall   DROP
        call    LATEST_
        rcall   FETCH_A
        rcall   findi
FIND1:
        ret

; DIGIT?   c -- n -1   if c is a valid digit
        fdw     FIND_L
DIGITQ_L:
        .db     NFA|6,"digit?",0
DIGITQ:
                                ; 1 = 31    A = 41
        rcall   DUP             ; c c       c c
        rcall   DOLIT_A
        .dw     0x39            ; c c 39    c c 39
        rcall   GREATER         ; c 0       c ffff
        rcall   ZEROSENSE
        breq    DIGITQ1
        rcall   DOLIT_A
        .dw     0x27
        rcall   MINUS
DIGITQ1:        
        rcall   DOLIT_A
        .dw     0x30            ; c 30
        rcall   MINUS           ; 1
        rcall   DUP             ; 1 1
        rcall   BASE            ; 1 1 base
        rcall   FETCH_A         ; 1 1 10
        rcall   LESS            ; 1 ffff
        rcall   OVER            ; 1 ffff 1
        rcall   ZEROLESS        ; 1 ffff 0
        rcall   INVERT
        jmp     AND_

; SIGN?   adr n -- adr' n' f   get optional sign
; + leaves $0000 flag
; - leaves $0002 flag
        fdw     DIGITQ_L
SIGNQ_L:
        .db     NFA|5,"sign?"
SIGNQ:
        rcall   OVER
        rcall   CFETCH_A
        rcall   DOLIT_A
        .dw     ','
        rcall   MINUS
        rcall   DUP
        rcall   ABS_
        call    ONE
        rcall   EQUAL
        rcall   AND_
        rcall   DUPZEROSENSE
        breq    QSIGN1
        rcall   ONEPLUS
        rcall   TOR
        call    ONE
        rcall   SLASHSTRING
        rcall   RFROM
QSIGN1: ret

; UD*  ud u -- ud
        fdw     SIGNQ_L
UDSTAR_L:
        .db     NFA|3,"ud*"
UDSTAR:
        rcall   DUP
        rcall   TOR
        rcall   UMSTAR
        rcall   DROP
        rcall   SWOP
        rcall   RFROM
        rcall   UMSTAR
        rcall   ROT
        jmp     PLUS
        
; UD/MOD  ud u --u(rem) ud(quot)
        fdw     UDSTAR_L
UDSLASHMOD_L:
        .db     NFA|6,"ud/mod",0
UDSLASHMOD:
        rcall   TOR             ; ud.l ud.h 
        rcall   FALSE_          ; ud.l ud.h 0
        rcall   RFETCH          ; ud.l ud.h 0 u
        rcall   UMSLASHMOD      ; ud.l r.h q.h
        rcall   ROT             ; r.h q.h ud.l
        rcall   ROT             ; q.h ud.l r.h
        rcall   RFROM           ; q.h ud.l r.h u
        rcall   UMSLASHMOD      ; q.h r.l q.l
        jmp     ROT             ; r.l q.l q.h
        
; >NUMBER  0 0 adr u -- ud.l ud.h adr' u'
;                       convert string to number
        fdw     UDSLASHMOD_L
TONUMBER_L:
        .db     NFA|7,">number"
TONUMBER:
TONUM1:
        rcall   DUPZEROSENSE      ; ud.l ud.h adr u
        breq    TONUM3
        rcall   TOR
        rcall   DUP
        rcall   TOR             ; ud.l ud.h adr
        rcall   CFETCH_A
        rcall   DIGITQ          ; ud.l ud.h digit flag
        rcall   ZEROSENSE
        brne    TONUM2
        rcall   DROP
        rcall   RFROM
        rcall   RFROM
        rjmp    TONUM3
TONUM2: 
        rcall   TOR             ; ud.l ud.h digit
        rcall   BASE
        rcall   FETCH_A
        rcall   UDSTAR
        rcall   RFROM
        rcall   MPLUS
        rcall   RFROM
        rcall   RFROM
        
        call    ONE
        rcall   SLASHSTRING
        rjmp    TONUM1
TONUM3: 
        ret

BASEQV:   
        fdw     DECIMAL
        fdw     HEX
        fdw     BIN


; NUMBER?  c-addr -- n 1
;                 -- dl dh 2
;                 -- c-addr 0  if convert error
        fdw     TONUMBER_L
NUMBERQ_L:
        .db     NFA|7,"number?"
NUMBERQ:
        rcall   DUP             ; a a
        rcall   FALSE_          ; a a 0 0
        rcall   FALSE_          ; a a 0 0
        rcall   ROT             ; a 0 0 a
        rcall   CFETCHPP        ; a 0 0 a' u
        rcall   SIGNQ           ; a 0 0 a' u f
        rcall   TOR             ; a 0 0 a' u

        rcall   BASE
        rcall   FETCH_A
        rcall   TOR             ; a 0 0 a' u
        
        rcall   OVER
        rcall   CFETCH_A
        
        rcall   DOLIT_A
        .dw     '#'
        rcall   MINUS
        rcall   DUP
        rcall   DOLIT_A
        .dw     3
        rcall   ULESS
        rcall   ZEROSENSE
        breq    BASEQ1
        call    CELLS
        
        rcall   DOLIT_A
        fdw     BASEQV
        rcall   PLUS
        call    FEXECUTE

        call    ONE
        rcall   SLASHSTRING
        rjmp    BASEQ2
BASEQ1:
        call    DROP
BASEQ2:                         ; a 0 0 a' u
        rcall   TONUMBER        ; a ud.l ud.h  a' u
        rcall   RFROM           ; a ud.l ud.h  a' u oldbase
        rcall   BASE            ; a ud.l ud.h  a' u oldbase addr
        rcall   STORE_A         ; a ud.l ud.h  a' u

        rcall   DUP
        rcall   TWOMINUS
        rcall   ZEROLESS        ; a ud.l ud.h  a' u f
        rcall   ZEROSENSE       ; a ud.l ud.h  a' u
        brne    QNUMD
QNUM_ERR:                       ; Not a number
        rcall   RFROM           ; a ud.l ud.h a' u sign
        call    DROP
        call    TWODROP
QNUM_ERR1:      
        call    TWODROP
        rcall   FALSE_          ; a 0           Not a number
        rjmp    QNUM3
QNUMD:                          ; Double number
                                ; a ud.l ud.h a' u
        call    TWOSWAP         ; a a' u ud.l ud.h 
        rcall   RFROM           ; a a' u ud.l ud.d sign
        rcall   ZEROSENSE
        breq    QNUMD1
        call    DNEGATE
QNUMD1: 
        call    TWOSWAP         ; a d.l d.h a' u
        rcall   ZEROSENSE       ; a d.l d.h a'
        breq    QNUM1
        call    CFETCH
        rcall   DOLIT_A
        .dw     '.'
        rcall   MINUS
        rcall   ZEROSENSE       ; a d.l d.h
        brne    QNUM_ERR1
        call    ROT             ; d.l d.h a
        call    DROP            ; d.l d.h
        rcall   DOLIT_A         ; 
        .dw     2               ; d.l ud.h 2    Double number
        rjmp    QNUM3
QNUM1:                          ; single precision dumber
                                ; a ud.l ud.h  a'
        call    TWODROP         ; a n
        rcall   NIP             ; n
        call    ONE             ; n 1           Single number
QNUM3:  
        ret


        .db     NFA|4,"swap",0
SWOP_A:
        jmp     SWOP

; TI#  -- n                      size of TIB
; : ti# task @ 8 + @ ;
        fdw     NUMBERQ_L
TIBSIZE_L:
        .db     NFA|3,"ti#"
TIBSIZE:
        rcall   TASK
        rcall   FETCH_A
        adiw    tosl, 5
        jmp     CFETCH

; TIB     -- a-addr        Terminal Input Buffer
        fdw     TIBSIZE_L
TIB_L:
        .db     NFA|3,"tib"
TIB:
        rcall   TIU
        jmp     FETCH
        
; TIU     -- a-addr        Terminal Input Buffer user variable 
        fdw     TIB_L
TIU_L:
        .db     NFA|3,"tiu"
TIU:
        rcall   DOUSER
        .dw     utib       ; pointer to Terminal input buffer

; >IN     -- a-addr        holds offset into TIB
; In RAM
        fdw     TIU_L
TOIN_L:
        .db     NFA|3,">in"
TOIN:
        rcall   DOUSER
        .dw     utoin

; 'SOURCE  -- a-addr        two cells: len, adrs
; In RAM ?
        fdw     TOIN_L
TICKSOURCE_L:
        .db     NFA|7,"'source"
TICKSOURCE:
        rcall   DOUSER
        .dw     usource       ; two cells !!!!!!

        .db     NFA|3,"dup"
DUP_A:  jmp     DUP

;  INTERPRET  c-addr u --    interpret given buffer
        fdw     TICKSOURCE_L
INTERPRET_L:
        .db     NFA|9,"interpret"
INTERPRET: 
        rcall   TICKSOURCE
        call    TWOSTORE
        rcall   FALSE_
        rcall   TOIN
        rcall   STORE_A
IPARSEWORD:
        rcall   BL
        rcall   WORD

        rcall   DUP_A
        rcall   CFETCH_A
        rcall   ZEROSENSE
        brne    IPARSEWORD1
        rjmp    INOWORD
IPARSEWORD1:
        rcall   FIND            ; sets also wflags
        rcall   DUPZEROSENSE    ; 0 = not found, -1 = normal, 1 = immediate
        breq    INUMBER         ; NUMBER?
        rcall   ONEPLUS         ; 0 = normal 2 = immediate
        rcall   STATE_
        rcall   ZEROEQUAL
        rcall   OR_
        rcall   ZEROSENSE
        breq    ICOMPILE_1      ; Compile a word
        
                                ; Execute a word
                                ; immediate&compiling or interpreting
        sbrs    wflags, 4       ; Compile only check
        rjmp    IEXECUTE        ; Not a compile only word
        rcall   STATE_          ; Compile only word check
        call    XSQUOTE
        .db     10,"COMPILING?",0
        rcall   QABORT
IEXECUTE:
        cbr     FLAGS1, (1<<noclear)
        call    EXECUTE
        sbrc    FLAGS1, noclear ;  set by \ and by (
        rjmp    IPARSEWORD
        cbr     FLAGS1, (1<<izeroeq) ; Clear 0= encountered in compilation
        cbr     FLAGS1, (1<<idup)    ; Clear DUP encountered in compilation
        rjmp    IPARSEWORD
ICOMPILE_1:
        cbr     FLAGS1, (1<<izeroeq) ; Clear 0= encountered in compilation
        rcall   DUP_A
        rcall   DOLIT_A
        fdw     ZEROEQUAL       ; Check for 0=, modifies IF and UNTIL to use bnz
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    ICOMPILE_2
        sbr     FLAGS1, (1<<izeroeq) ; Mark 0= encountered in compilation
        rjmp    ICOMMAXT
ICOMPILE_2:
        cbr     FLAGS1, (1<<idup)    ; Clear DUP encountered in compilation
        rcall   DUP_A
        rcall   DOLIT_A
        fdw     DUP             ; Check for DUP, modies IF and UNTIl to use DUPZEROSENSE
        rcall   EQUAL
        rcall   ZEROSENSE
        breq    ICOMPILE
        sbr     FLAGS1, (1<<idup)    ; Mark DUP encountered during compilation
ICOMMAXT:
        rcall   COMMAXT_A
        cbr     FLAGS2, (1<<fTAILC)  ; Allow tailjmp  optimisation
        sbrc    wflags, 4            ; Compile only ?
        sbr     FLAGS2, (1<<fTAILC)  ; Prevent tailjmp  optimisation
        rjmp    IPARSEWORD
ICOMPILE:
;        sbrs    wflags, 5       ; Inline check
        rjmp    ICOMMAXT
;        call    INLINE0
        rjmp    IPARSEWORD
INUMBER: 
        cbr     FLAGS1, (1<<izeroeq) ; Clear 0= encountered in compilation
        cbr     FLAGS1, (1<<idup)    ; Clear DUP encountered in compilation
        call    DROP
        rcall   NUMBERQ
        rcall   DUPZEROSENSE
        breq    IUNKNOWN
        rcall   STATE_
        rcall   ZEROSENSE
        breq    INUMBER1
        mov     t0, tosl
        poptos
        sbrs    t0, 1
        rjmp    ISINGLE
IDOUBLE:
        rcall   SWOP_A
        call    LITERAL
ISINGLE:        
        call    LITERAL
        rjmp    IPARSEWORD

INUMBER1:
        call    DROP
        rjmp    IPARSEWORD

IUNKNOWN:
        call    DROP 
        rcall   DP_TO_RAM
        rcall   CFETCHPP
        call    TYPE
        rcall   FALSE_
        rcall   QABORTQ         ; Never returns & resets the stacks
INOWORD: 
        jmp     DROP

        .db     NFA|1,"@"
FETCH_A:        
        jmp     FETCH

;;;    bitmask -- 
        fdw     INTERPRET_L
SHB_L:
        .db     NFA|3,"shb"     ; Set header bit
SHB:
        call    LATEST_
        rcall   FETCH_A
        rcall   DUP_A
        rcall   CFETCH_A
        call    ROT
        call    OR_
        rcall   SWOP_A
        jmp     CSTORE
        
        fdw     SHB_L
IMMEDIATE_L:
        .db     NFA|9,"immediate" ; 
IMMEDIATE:
        rcall   DOLIT_A
        .dw     IMMED
        jmp     SHB

;***************************************************************
        fdw     IMMEDIATE_L
INLINED_L:
        .db     NFA|7,"inlined" ; 
INLINED:
        rcall   DOLIT_A
        .dw     INLINE
        jmp     SHB

;; .st ( -- ) output a string with current data section and current base info
;;; : .st base @ dup decimal <#  [char] , hold #s  [char] < hold #> type 
;;;     <# [char] > hold cse @ #s #> type base ! ;
        fdw     INLINED_L
DOTSTATUS_L:
        .db     NFA|3,".st"
DOTSTATUS:
        rcall   DOLIT_A
        .dw     '<'
        call    EMIT
        rcall   DOTBASE
        call    EMIT
        rcall   DOLIT_A
        .dw     ','
        call    EMIT
        rcall   MEMQ
        call    TYPE
        rcall   DOLIT_A
        .dw     '>'
        call    EMIT
        jmp     DOTS
        
        .db     NFA|3,"lit"
DOLIT_A:
        jmp     DOLIT
        

        .db     NFA|2,">r",0
TOR_A:  jmp     TOR


;;; TEN ( -- n ) Leave decimal 10 on the stack
        .db     NFA|1,"a"
TEN:
        rcall   DOCREATE_A
        .dw     10

; dp> ( -- ) Copy ini, dps and latest from eeprom to ram
;        .dw     link
; link    set     $
        .db     NFA|3,"dp>"
DP_TO_RAM:
        rcall   DOLIT_A
        .dw     dp_start
        rcall   INI
        rcall   TEN
        jmp     CMOVE

; >dp ( -- ) Copy only changed turnkey, dp's and latest from ram to eeprom
;        .dw     link
; link    set     $
        .db     NFA|3,">dp"
DP_TO_EEPROM:
        rcall   DOLIT_A
        .dw     dp_start
        rcall   STORE_P_TO_R
        rcall   INI
        rcall   DOLIT_A
        .dw     4
        rcall   TOR
DP_TO_EEPROM_0: 
        rcall   FETCHPP
        call    DUP
        rcall   PFETCH
        call    NOTEQUAL
        call    ZEROSENSE
        breq    DP_TO_EEPROM_1
        rcall   PSTORE
        rjmp    DP_TO_EEPROM_2
DP_TO_EEPROM_1:
        call    DROP
DP_TO_EEPROM_2:
;        call    CELL
        rcall   PTWOPLUS
DP_TO_EEPROM_3:
        rcall   XNEXT
        brcc    DP_TO_EEPROM_0
        pop     t1
        pop     t0
        rcall   R_TO_P
        jmp     DROP

        fdw     DOTSTATUS_L
FALSE_L:
        .db     NFA|5,"false"
FALSE_:                     ; TOS is 0000 (FALSE)
        pushtos
        clr     tosl
        clr     tosh
        ret

        fdw     FALSE_L
TRUE_L:
        .db     NFA|4,"true",0
TRUE_:                      ; TOS is ffff (TRUE)
        pushtos
        ser     tosl
        ser     tosh
        ret

; QUIT     --    R: i*x --    interpret from kbd
        fdw     TRUE_L
QUIT_L:
        .db     NFA|4,"quit",0
QUIT:
        call    RPEMPTY
        rcall   LEFTBRACKET
        call    FRAM
QUIT0:  
        call    IFLUSH
        ;; Copy INI and DP's from eeprom to ram
        rcall   DP_TO_RAM
        call    XXON_TX1_1
QUIT1: 
        call    check_sp
        rcall   CR
        rcall   TIB
        rcall   DUP_A
        rcall   TIBSIZE
        rcall   TEN                 ; Reserve 10 bytes for hold buffer
        call    MINUS
        call    ACCEPT
        call    XXOFF_TX1_1
        call    SPACE_
        rcall   INTERPRET
        call    STATE_
        rcall   ZEROSENSE
        brne    QUIT1
        rcall   DP_TO_EEPROM
         
        call    XSQUOTE
        .db     3," ok"
        call    TYPE
        rcall   PROMPT_
        jmp     QUIT0

        fdw     QUIT_L
PROMPT_L:
        .db     NFA|6,"prompt",0
PROMPT_:
        call    DEFER_DOES
        .dw     prompt

; ABORT    i*x --   R: j*x --   clear stk & QUIT
        fdw     PROMPT_L
ABORT_L:
        .db     NFA|5,"abort"
ABORT:
        rcall   S0
        rcall   FETCH_A
        call    SPSTORE
        ;bsf     RCSTA, CREN, A
        jmp     QUIT            ; QUIT never rets

; ?ABORT   f --       abort & print ?
        fdw     ABORT_L
QABORTQ_L:
        .db     NFA|7,"?abort?"
QABORTQ:
        call    XSQUOTE
        .db     1,"?"
        jmp     QABORT


; ?ABORT   f c-addr u --       abort & print msg
        fdw     QABORTQ_L
QABORT_L:
        .db     NFA|6,"?abort",0
QABORT:
        call    ROT
        rcall   ZEROSENSE
        brne    QABO1
QABORT1:        
        call    SPACE_
        call    TYPE
        rcall   ABORT  ; ABORT never rets
QABO1:  jmp     TWODROP

; ABORT"  i*x 0  -- i*x   R: j*x -- j*x  x1=0
;         i*x x1 --       R: j*x --      x1<>0
        fdw     QABORT_L
ABORTQUOTE_L:
        .db     NFA|IMMED|COMPILE|6,"abort",'"',0
ABORTQUOTE:
        call    SQUOTE
        rcall   DOLIT_A
        fdw     QABORT
        jmp     COMMAXT

; '    -- xt             find word in dictionary
        fdw     ABORTQUOTE_L
TICK_L:
        .db     NFA|1,0x27    ; 27h = '
TICK:
        rcall   BL
        rcall   WORD
        rcall   FIND
        jmp     QABORTQ

; CHAR   -- char           parse ASCII character
        fdw     TICK_L
CHAR_L:
        .db     NFA|4,"char",0
CHAR:
        rcall   BL
        rcall   PARSE
        call    DROP
        jmp     CFETCH

; (    --                     skip input until )
        fdw     CHAR_L
PAREN_L:
        .db     NFA|IMMED|1,"("
PAREN:
        rcall   DOLIT_A
        .dw     ')'
        rcall   PARSE
        sbr     FLAGS1, (1<<noclear) ; dont clear flags in case of (
        jmp     TWODROP

; IHERE    -- a-addr    ret Code dictionary ptr
;   IDP @ ;
;;;         .dw     link
;;; link    set     $
        .db     NFA|5,"ihere"
IHERE:
        rcall   IDP
        rjmp    FETCH_A

; [CHAR]   --          compile character DOLITeral
        fdw     PAREN_L
BRACCHAR_L:
        .db     NFA|IMMED|COMPILE|6,"[char]",0
BRACCHAR:
        rcall   CHAR
        jmp     LITERAL

; COMPILE,  xt --         append codefield
        .db     NFA|3,"cf,"
COMMAXT_A:
        jmp     COMMAXT

        .db     NFA|3,"(c)"
DOCREATE_A: 
        jmp     DOCREATE


; CR      --                      output newline
        fdw     BRACCHAR_L
CR_L:
        .db     NFA|2,"cr",0
CR:
        rcall   DOLIT
        .dw     0x0d       ; CR \r
        rcall   EMIT
        rcall   DOLIT
        .dw     0x0a       ; LF \n
        jmp     EMIT

; CREATE   --         create an empty definition
; Create a definition header and append 
; doCREATE and the current data space dictionary pointer
; in FLASH.
;  Examples :   
; : table create 10 cells allot does> swap cells + ;
; ram table table_a     flash table table_b    eeprom table table_c
; ram variable  qqq
; eeprom variable www ram
; flash variable  rrr ram 
; eeprom create calibrationtable 30 allot ram
; 
        fdw     CR_L
CREATE_L:
        .db     NFA|6,"create",0
CREATE:
        rcall   BL
        rcall   WORD            ; Parse a word

        rcall   DUP_A           ; Remember parsed word at rhere
        rcall   FIND
        rcall   NIP
        call    ZEROEQUAL
        rcall   QABORTQ         ; ABORT if word has already been defined
        rcall   DUP_A           ; Check the word length 
        rcall   CFETCH_A
        call    ONE
        rcall   DOLIT_A
        .dw     16
        call    WITHIN
        rcall   QABORTQ          ; Abort if there is no name for create

        rcall   LATEST_
        rcall   FETCH_A
        call    ICOMMA          ; Link field
        rcall   CFETCHPP        ; str len
        rcall   IHERE
        rcall   DUP_A             
        rcall   LATEST_         ; new 'latest' link
        rcall   STORE_A         ; str len ihere
        rcall   PLACE           ; 
        rcall   IHERE           ; ihere
        rcall   CFETCH_A
        rcall   DOLIT_A
        .dw     NFA
        rcall   SHB
        call    ONEPLUS
        call    ALIGNED
        rcall   IALLOT          ; The header has now been created
        rcall   DOLIT_A             
        fdw     DOCREATE        ; compiles the runtime routine to fetch the next dictionary cell to the parameter stack
        rcall   COMMAXT_A       ; Append an exeution token
        call    ALIGN
        call    HERE            ; compiles the current dataspace dp into the dictionary
        call    CSE_
        call    ZEROSENSE
        brne    CREATE2
        call    TWOPLUS
CREATE2:
        jmp     ICOMMA          ; dp now points to a free cell

;***************************************************************
; POSTPONE
        fdw    CREATE_L
POSTPONE_L:
        .db     NFA|IMMED|COMPILE|8,"postpone",0
POSTPONE:
        rcall   BL
        rcall   WORD
        rcall   FIND
        rcall   DUP_A
        rcall   QABORTQ
        call    ZEROLESS
        call    ZEROSENSE
        breq    POSTPONE1
        call    LITERAL
        rcall   DOLIT_A
        fdw     COMMAXT
POSTPONE1:
        jmp    COMMAXT


IDP_L:
        .db     NFA|3,"idp"
IDP:
        rcall   DOCREATE_A
        .dw     dpFLASH

;***************************************************************
; (DOES>)  --      run-time action of DOES>
;        .dw    link
;link   set     $
        .db     NFA|7,"(does>)"
XDOES:
        rcall   RFROM
        call    LATEST_
        rcall   FETCH_A
        rcall   NFATOCFA
        rcall   IDP
        rcall   FETCH_A
        rcall   TOR_A
        rcall   IDP
        rcall   STORE_A
        lsl     tosl
        rol     tosh
        call    STORECFF1 ; Always stores a 4 byte call
        call    RFROM
        rcall   IDP
        jmp     STORE


; DOES>    --      change action of latest def'n
        fdw     POSTPONE_L
DOES_L:
        .db     NFA|IMMED|COMPILE|5,"does>"
DOES:   rcall   DOLIT_A
        fdw     XDOES
        rcall   COMMAXT_A
        rcall   DOLIT_A
        fdw     DODOES
        jmp     COMMAXT


;*****************************************************************
; [        --      enter interpretive state
        fdw     DOES_L
LEFTBRACKET_L:
        .db     NFA|IMMED|1,"["
LEFTBRACKET:
        cbr     t0, 0xff
        sts     state, t0
        ret


; ]        --      enter compiling state
        fdw     LEFTBRACKET_L
RIGHTBRACKET_L:
        .db     NFA|1,"]"
RIGHTBRACKET:
        sbr     t0, 0xff
        sts     state, t0
        ret

; :        --           begin a colon definition
        fdw     RIGHTBRACKET_L
COLON_L:
        .db     NFA|1,":"
COLON:
        rcall   CREATE
        rcall   RIGHTBRACKET
        jmp     STORCOLON

; :noname        -- a          define headerless forth code
        fdw     COLON_L
NONAME_L:
        .db     NFA|7,":noname"
NONAME:
        rcall   IHERE
        jmp     RIGHTBRACKET

; ;        --             end a colon definition
        fdw     NONAME_L
SEMICOLON_L:
        .db     NFA|IMMED|COMPILE|1,";"
SEMICOLON:
        rcall   DOLIT_A   ; Compile a ret
        .dw     0x9508
        call    ICOMMA
        jmp     LEFTBRACKET


        fdw     SEMICOLON_L
MINUS_FETCH_L:
        .db     NFA|2,"-@",0
MINUS_FETCH:
        rcall   TWOMINUS
        rcall   DUP_A
        jmp     FETCH

; [']  --         find word & compile as DOLITeral
        fdw     MINUS_FETCH_L
BRACTICK_L:
        .db     NFA|IMMED|COMPILE|3,"[']"
BRACTICK:
        rcall   TICK       ; get xt of 'xxx'
        jmp     LITERAL

; 2-    n -- n-2
        fdw     BRACTICK_L
TWOMINUS_L:
        .db     NFA|2,"2-",0
TWOMINUS:
        sbiw    tosl, 2
        ret

        
; BL      -- char                 an ASCII space
        fdw     TWOMINUS_L
BL_l:
        .db     NFA|2,"bl",0
BL:
        rcall   DOCREATE_A
        .dw     ' '

; STATE   -- flag                 holds compiler state
        fdw     BL_L
STATE_L:
        .db     NFA|5,"state"
STATE_:
        pushtos
        lds     tosl, state
        lds     tosh, state
        ret

; LATEST    -- a-addr           
        fdw     STATE_L
LATEST_L:
        .db     NFA|6,"latest",0
LATEST_:
        rcall   DOCREATE_A
        .dw     dpLATEST

; S0       -- a-addr      start of parameter stack
        fdw     LATEST_L
S0_L:
        .db     NFA|2,"s0",0
S0:
        rcall   DOUSER
        .dw     us0
        
; R0       -- a-addr      start of parameter stack
        fdw     S0_L
R0_L:
        .db     NFA|2,"r0",0
R0_:
        rcall   DOUSER
        .dw     ur0
        
; ini -- a-addr       ini variable contains the user-start xt
; In RAM
;        .dw     link
;link    set     $
        .db     NFA|3,"ini"
INI:
        rcall   DOCREATE_A
        .dw     dpSTART

; ticks  -- u      system ticks (0-ffff) in milliseconds
        fdw     R0_L
TICKS_L:
        .db     NFA|5,"ticks"
TICKS:
        pushtos
        cli
        lds     tosl, ms_count
        lds     tosh, ms_count+1
        sei
        ret

        
; ms  +n --      Pause for n millisconds
; : ms ( +n -- )     
;   ticks -
;   begin
;     pause dup ticks - 0<
;   until drop ;
;
        fdw     TICKS_L
MS_L:
        .db     NFA|2,"ms",0
MS:
        rcall   TICKS
        rcall   PLUS
MS1:    
        call    PAUSE
        rcall   DUP_A
        rcall   TICKS
        rcall   MINUS
        rcall   ZEROLESS
        rcall   ZEROSENSE
        breq    MS1
        jmp     DROP

;  .id ( nfa -- ) 
        fdw     MS_L
DOTID_L:
        .db     NFA|3,".id"
DOTID:
        rcall   CFETCHPP
        rcall   DOLIT_A
        .dw     0x0f
        call    AND_
        call    TOR
        rjmp    DOTID3
DOTID1:
        rcall   CFETCHPP
        rcall   TO_PRINTABLE
        call    EMIT
DOTID3:
        rcall   XNEXT
        brcc    DOTID1  
        pop     t1
        pop     t0
        jmp     DROP

 ; >pr   c -- c      Filter a character to printable 7-bit ASCII
        fdw     DOTID_L
TO_PRINTABLE_L:
        .db     NFA|3,">pr"
TO_PRINTABLE:   
        cpi     tosl, 0
        brmi    TO_PRINTABLE1
        cpi     tosl, 0x1f
        brpl    TO_PRINTABLE2
TO_PRINTABLE1:
        ldi     tosl, '.'
TO_PRINTABLE2:
        ret

 ; WORDS    --          list all words in dict.
        fdw     TO_PRINTABLE_L
WORDS_L:
        .db     NFA|5,"words"
        rcall   FALSE_
        rcall   CR
        rcall   LATEST_
        rcall   FETCH_A
        rcall   WDS1
        rcall   FALSE_
        rcall   CR
        rcall   DOLIT_A
        fdw     kernellink
WDS1:   rcall   DUP_A
        rcall   DOTID
        rcall   SWOP_A
        call    ONEPLUS
        rcall   DUP_A
        rcall   DOLIT_A
        .dw     7
        call    AND_
        call    ZEROSENSE
        breq    WDS2
        rcall   DOLIT_A
        .dw     9
        call    EMIT
        rjmp    WDS3
WDS2:   
        rcall   CR
WDS3:
        rcall   SWOP_A

        rcall   TWOMINUS
        rcall   FETCH_A
        call    DUPZEROSENSE
        brne    WDS1
        jmp     TWODROP

; .S      --           print stack contents
; : .s space sp@ s0 @ 2- begin 2dup < while -@ u. repeat 2drop ;
        fdw     WORDS_L
DOTS_L:
        .db     NFA|2,".s",0
DOTS:
        rcall   SPACE_
        rcall   DUP          ; push tosl:tosh to memory
        call    SPFETCH
        rcall   S0
        rcall   FETCH_A
        call    TWOMINUS
DOTS1:
        call    TWODUP
        call    LESS
        call    ZEROSENSE
        breq    DOTS2
        rcall   MINUS_FETCH
        call    UDOT
        rjmp    DOTS1
DOTS2:  
        rcall   DROP
        jmp     TWODROP

;   DUMP  ADDR U --       DISPLAY MEMORY
        fdw     DOTS_L
DUMP_L:
        .db     NFA|4,"dump",0
DUMP:
        rcall   DOLIT_A
        .dw     16
        call    USLASH
        call    TOR
        rjmp    DUMP7
DUMP1:  
        rcall   CR
        rcall   DUP_A
        rcall   DOLIT_A
        .dw     4
        call    UDOTR
        rcall   DOLIT_A
        .dw     ':'
        call    EMIT
        rcall   DOLIT_A
        .dw     15
        call    TOR
DUMP2:
        rcall   CFETCHPP
        rcall   DOLIT_A
        .dw     2
        call    UDOTR
        rcall   XNEXT
        brcc    DUMP2
        pop     t1
        pop     t0

        rcall   DOLIT_A
        .dw     16
        call    MINUS
        rcall   DOLIT_A
        .dw     15
        call    TOR
DUMP4:  
        call    CFETCHPP
        rcall   TO_PRINTABLE
        call    EMIT
        rcall   XNEXT
        brcc    DUMP4
        pop     t1
        pop     t0
DUMP7:
        rcall   XNEXT
        brcc    DUMP1
        pop     t1
        pop     t0
        jmp     DROP

; IALLOT   n --    allocate n bytes in ROM
;       .dw     link
;link   set     $
        .db     NFA|1," "
IALLOT:
        rcall   IDP
        jmp     PLUSSTORE
    

;***************************************************************
DNEGATE:
        rcall   SWOP        
        rcall   INVERT
        rcall   SWOP
        rcall   INVERT
        rcall   ONE
        jmp     MPLUS

;;; ******************************************************

        fdw     DUMP_L
PFLASH_L:
        .db     NFA|3,"pfl"
PFLASH_:
        rcall   DOCREATE_A
        .dw     PFLASH    

;***************************************************************
; check that the relative address is within reach of conditional branch
; instructions and leave the clipped relative address on the stack
; br?   ( rel-addr limit -- clipped-rel-addr)
;       2dup 2/ swap
;       abs > (qabort)
;       and 2/ ;
        fdw     PFLASH_L
BRQ_L:
        .db     NFA|3,"br?"
BRQ:
        call    TWODUP
        call    TWOSLASH
        rcall   SWOP_A          ; rel-addr limit limit' rel-addr
        call    ABS_            ; rel-addr limit limit' rel-addr
        call    GREATER
        call    XSQUOTE
        .db      3,"BR?"
        rcall   QABORT         ;  ?RANGE ABORT if TRUE
BRQ1:
        call    AND_
        jmp     TWOSLASH

; ,?0=    -- addr  Compile ?0= and make make place for a branch instruction
        .db     NFA|4,",?0=",0    ; Just for see to work !
COMMAZEROSENSE:
        sbrc    FLAGS1, idup
        rjmp    COMMAZEROSENSE1
        rcall   DOLIT_A
        fdw     ZEROSENSE
        rjmp    COMMAZEROSENSE2
COMMAZEROSENSE1:
        rcall   IDPMINUS
        rcall   DOLIT_A
        fdw     DUPZEROSENSE
COMMAZEROSENSE2:
        cbr     FLAGS1, (1<<idup)
        rjmp    INLINE0

IDPMINUS:
        rcall   DOLIT_A
        .dw     -4
        rjmp    IALLOT

;       rjmp, ( rel-addr -- )
RJMPC:
        rcall   TWOSLASH
        rcall   DOLIT_A
        .dw     0x0FFF
        rcall   AND_
        rcall   DOLIT_A
        .dw     0xc000
        rcall   OR_
        jmp     ICOMMA


BRCCC:
        rcall   DOLIT_A
        .dw     0xf008      ; brcc pc+2
        jmp     ICOMMA
BREQC:
        rcall   DOLIT_A
        .dw     0xf009      ; breq pc+2
        jmp     ICOMMA
BRNEC:
        rcall   DOLIT_A
        .dw     0xf409      ; brne pc+2
        jmp     ICOMMA

; IF       -- adrs   conditional forward branch
; Leaves address of branch instruction 
; and compiles the condition byte
        fdw     BRQ_L
IF_L:
        .db     NFA|IMMED|COMPILE|2,"if",0
IF_:
        rcall   COMMAZEROSENSE
        rcall   BRNEC
        rcall   IHERE
        rcall   FALSE_
        jmp     RJMPC           ; Dummy, replaced by THEN with rjmp 

; ELSE     adrs1 -- adrs2    branch for IF..ELSE
; Leave adrs2 of bra instruction and store bz in adrs1
; Leave adress of branch instruction and FALSE flag on stack
        fdw     IF_L
ELSE_L:
        .db     NFA|IMMED|COMPILE|4,"else",0
ELSE_:
        rcall   IHERE
        rcall   FALSE_
        rcall   RJMPC
        rcall   SWOP_A      ; else-addr  if-addr 
        jmp     THEN_

; THEN     adrs  --        resolve forward branch
        fdw     ELSE_L
THEN_L:
        .db     NFA|IMMED|COMPILE|4,"then",0
THEN_:
        rcall   IHERE
        rcall   OVER
        rcall   MINUS
        rcall   TWOMINUS
        rcall   TWOSLASH
        rcall   DOLIT_A
        .dw     0xc000      ;  back-addr mask 
        rcall   OR_
        rcall   SWOP_A
        jmp     STORE

; BEGIN    -- adrs        target for bwd. branch
        fdw     THEN_L
BEGIN_L:
        .db     NFA|IMMED|COMPILE|5,"begin"
BEGIN:
        jmp     IHERE

; UNTIL    adrs --   Branch bakwards if true
        fdw     BEGIN_L
UNTIL_L:
        .db     NFA|IMMED|COMPILE|5,"until"
UNTIL:
        rcall   COMMAZEROSENSE
        rcall   BRNEC
UNTIL1:
        rcall   IHERE
        rcall   MINUS
        rcall   TWOMINUS
        jmp     RJMPC

; AGAIN    adrs --      uncond'l backward branch
;   unconditional backward branch
        fdw     UNTIL_L
AGAIN_L:
        .db     NFA|IMMED|COMPILE|5,"again"
AGAIN_:
        rjmp    UNTIL1

; WHILE    addr1 -- addr2 addr1         branch for WHILE loop
; addr1 : address of BEGIN
; addr2 : address where to store bz instruction
        fdw     AGAIN_L
WHILE_L:
        .db     NFA|IMMED|COMPILE|5,"while"
WHILE_:
        rcall   IF_
        jmp     SWOP

; REPEAT   addr2 addr1 --     resolve WHILE loop
        fdw     WHILE_L
REPEAT_L:
        .db     NFA|IMMED|COMPILE|6,"repeat",0
REPEAT_:
        rcall   AGAIN_
        jmp     THEN_

L_INLINE:
; in, ( addr -- ) begin @+ dup $12 <> while i, repeat 2drop ;
        fdw      L_INLINE
L_INLINEC:
        .db      NFA|3,"in,"
INLINE0:        
        call    FETCHPP
        call    DUP
        rcall   DOLIT_A
        .dw     0x9508
        call    NOTEQUAL
        call    ZEROSENSE
        breq    INLINE1
        call    ICOMMA
        rjmp    INLINE0
INLINE1:
        jmp     TWODROP

; FOR   -- bc-addr bra-addr
        fdw     REPEAT_L
FOR_L:
        .db     NFA|IMMED|COMPILE|3,"for"
FOR:
        rcall   DOLIT_A
        fdw     TOR
        rcall   COMMAXT_A
        rcall   IHERE
        rcall   FALSE_
        rcall   RJMPC
        rcall   IHERE
        jmp     SWOP

; NEXT bra-addr bc-addr --
        fdw     FOR_L
NEXT_L:
        .db     NFA|IMMED|COMPILE|4,"next", 0
NEXT:
        rcall   THEN_
        rcall   DOLIT_A
        fdw     XNEXT
        rcall   COMMAXT_A
        rcall   BRCCC

        rcall   UNTIL1

        rcall   DOLIT_A
        fdw     XNEXT1
        jmp     INLINE0
; (next) decrement top of return stack
XNEXT:  
        pop     zh
        pop     zl
        pop     xh
        pop     xl
        sbiw    xl, 1
        push    xl
        push    xh
        ijmp
        ret
XNEXT1:
        pop     t1
        pop     t0
        ret

; leave clear top of return stack
        fdw     NEXT_L
LEAVE_L:
        .db     NFA|COMPILE|5,"leave"
LEAVE:
        pop     zh
        pop     zl
        pop     t1
        pop     t0
        clr     t0
        clr     t1
        push    t0
        push    t1
        ijmp

; RDROP compile a pop
        fdw      LEAVE_L
RDROP_L:
        .db      NFA|IMMED|COMPILE|5,"rdrop"
RDROP:
        rcall   DOLIT_A
        fdw     XNEXT1
        jmp     INLINE0

        fdw     RDROP_L
TEST_L:
        .db     NFA|3,"ttt"
        call    TOR
        rjmp    TEST1
TEST0:
        call    CHARS
TEST1:
        pop     xl
        pop     xh
        sbiw    xl, 1
        push    xh
        push    xl
        brcs    TEST2
        rjmp    TEST0
TEST2:
        pop     t0
        pop     t0
        ret
;***************************************************
        fdw      RDROP_L
L_FETCH_P:
        .db      NFA|2,"@p", 0
FETCH_P:
        pushtos
        movw    tosl, pl
        ret
;***************************************************
        fdw     L_FETCH_P
L_PCFETCH:
        .db     NFA|3,"pc@" ; ( -- c ) Fetch char from pointer
PCFETCH:
        pushtos
        movw    tosl, pl
        jmp     CFETCH
;***************************************************
        fdw      L_PCFETCH
L_PTWOPLUS:
kernellink:
        .db      NFA|INLINE|3,"p2+" ; ( n -- ) Add 2 to p
PTWOPLUS:
        ldi     t0, 2
        add     pl, t0
        adc     ph, zero
        ret

;***************************************************
; marker --- name
        .dw     0
L_MARKER:
lastword:
        .db     NFA|6,"marker",0
MARKER:
        call    ROM_
        rcall   CREATE
        call    DOLIT_A
        .dw     dp_start
        call    HERE
        call    TEN
        call    CMOVE
        call    TEN
        call    ALLOT
        call    FRAM
        rcall   XDOES
        call    DODOES
        rcall   INI
        call    TEN
        jmp     CMOVE


L_DOTBASE:
        .db      NFA|1,"I"
DOTBASE:
        call    BASE
        call    FETCH_A
        cpi     tosl, 0x10
        brne    DOTBASE1
        ldi     tosl,'$'
        rjmp    DOTBASEEND
DOTBASE1:
        cpi     tosl, 0xa
        brne    DOTBASE2
        ldi     tosl, '#'
        rjmp    DOTBASEEND
DOTBASE2:
        cpi     tosl, 0x2
        brne    DOTBASE3
        ldi     tosl, '%'
        rjmp    DOTBASEEND
DOTBASE3:
        ldi     tosl, '?'
DOTBASEEND:
        ret
;;;**************************************
;;; The USB code lib goes here in between
;;;**************************************
;FF_END_CODE code
MEMQADDR_N:
        fdw     ROM_N
        fdw     EROM_N
        fdw     FRAM_N
; M? -- caddr count    current data space string
;        dw      L_DOTBASE
L_MEMQ:
        .db     NFA|1,"I"
MEMQ:
        call    CSE_
        call    DOLIT
        fdw     MEMQADDR_N
        call    PLUS
        call    FETCH_A
        call    CFETCHPP
        call    DOLIT
        .dw     NFAmask
        jmp     AND_
end_of_dict:

;FF_DP code:
dpcode:
;****************************************************
;        org h'f00000'
;        de  h'ff', h'ff'
;        de  dp_user_dictionary&0xff, (dp_user_dictionary>>8)&0xff
;        de  dpeeprom&0xff, (dpeeprom>>8)&0xff
;        de  (dpdata)&0xff, ((dpdata)>>8)&0xff
;        de  lastword_lo, lastword_hi
;        de  DOTSTATUS;&0xff;, (DOTSTATUS>>8)&0xff

; .end
;********************************************************** 

KERNEL_END:
