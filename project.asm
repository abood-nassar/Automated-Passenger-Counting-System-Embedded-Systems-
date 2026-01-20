; ==============================================
;  PIC16F877A Passenger Counter (0..10)
;  Single-digit 7-segment on RD6..RD0
;  RD7 = 1 if COUNT == 10
;  Buzzer on RA2 for 5s if going beyond limits
;  T1=RB4, T2=RB5
; ==============================================

            LIST      P=16F877A
            INCLUDE   <P16F877A.INC>
    __CONFIG   _XT_OSC & _WDT_OFF & _PWRTE_ON & _LVP_OFF & _CP_OFF & _BODEN_ON

; ----------------------------------------------
; DATA MEMORY ALLOCATION
; ----------------------------------------------
            CBLOCK   0x20
    COUNT           ; Holds passenger count (0..10)
    STATE           ; State machine for sensor sequence
    TEMP            ; Scratch register
    OLD_PORTB       ; Previous reading of PORTB
    loop1           ; Delay counters
    loop2
    loop3           ; For 5-second beep loops
            ENDC

; ----------------------------------------------
; STATE MACHINE DEFINITIONS
; ----------------------------------------------
STATE_IDLE      EQU   0x00  
STATE_FWAIT_T1  EQU   0x01  ; T2?T1 => +1
STATE_RWAIT_T2  EQU   0x02  ; T1?T2 => –1

; ----------------------------------------------
; VECTOR ADDRESSES
; ----------------------------------------------
            ORG     0x0000
            GOTO    MAIN

            ORG     0x0004
            GOTO    ISR

; ----------------------------------------------
; MAIN PROGRAM
; ----------------------------------------------
MAIN:
    CLRF    PORTA
    CLRF    PORTB
    CLRF    PORTD
    CLRF    COUNT
    CLRF    STATE
    CLRF    OLD_PORTB

    ; Set TRIS
    BSF     STATUS, RP0        ; Bank 1
    MOVLW   b'11111011'        ; RA2=0 => output for buzzer
    MOVWF   TRISA
    MOVLW   b'00110000'        ; RB4,RB5 => inputs
    MOVWF   TRISB
    MOVLW   0x00               ; RD => outputs
    MOVWF   TRISD
    BCF     STATUS, RP0

    ; Enable interrupts
    BSF     INTCON, RBIE
    BSF     INTCON, GIE

MAIN_LOOP:
    CALL    UPDATE_DISPLAY
    GOTO    MAIN_LOOP

; ----------------------------------------------
; ISR
; ----------------------------------------------
ISR:
    BCF     INTCON, GIE
    BTFSC   INTCON, RBIF
    CALL    HANDLE_PORTB_CHANGE
    BCF     INTCON, RBIF
    BSF     INTCON, GIE
    RETFIE

; ----------------------------------------------
; HANDLE PORTB CHANGE
; ----------------------------------------------
HANDLE_PORTB_CHANGE:
    MOVF    PORTB, W
    XORWF   OLD_PORTB, W
    MOVWF   TEMP
    MOVF    PORTB, W
    MOVWF   OLD_PORTB

    ; Check (RB4)
    BTFSC   TEMP, 4
    CALL    CHECK_T1

    ; Check  (RB5)
    BTFSC   TEMP, 5
    CALL    CHECK_T2
    RETURN

CHECK_T1:
    BTFSS   PORTB, 4
    RETURN
    MOVF    STATE, W
    XORLW   STATE_IDLE
    BTFSC   STATUS, Z
        GOTO  SET_RWAIT_T2

    MOVF    STATE, W
    XORLW   STATE_FWAIT_T1
    BTFSC   STATUS, Z
        GOTO  DO_INCREMENT
    RETURN

SET_RWAIT_T2:
    MOVLW   STATE_RWAIT_T2
    MOVWF   STATE
    RETURN

DO_INCREMENT:
    MOVF    COUNT, W
    SUBLW   d'10'
    BTFSC   STATUS, Z
        GOTO  DO_BEEP
    INCF    COUNT, F
    CLRF    STATE
    CALL    UPDATE_DISPLAY
    MOVF    COUNT, W
    SUBLW   d'10'
    BTFSC   STATUS, Z
        GOTO  DO_BEEP
    RETURN


CHECK_T2:
    BTFSS   PORTB, 5
    RETURN
    MOVF    STATE, W
    XORLW   STATE_IDLE
    BTFSC   STATUS, Z
        GOTO  SET_FWAIT_T1

    MOVF    STATE, W
    XORLW   STATE_RWAIT_T2
    BTFSC   STATUS, Z
        GOTO  DO_DECREMENT
    RETURN

SET_FWAIT_T1:
    MOVLW   STATE_FWAIT_T1
    MOVWF   STATE
    RETURN

DO_DECREMENT:
    MOVF    COUNT, W
    BTFSC   STATUS, Z
        GOTO  DO_BEEP
    DECF    COUNT, F
    CLRF    STATE
    CALL    UPDATE_DISPLAY
    MOVF    COUNT, W
    BTFSC   STATUS, Z
        GOTO  DO_BEEP
    RETURN

DO_BEEP:
    CALL    BEEP_5SEC
    CLRF    STATE
    ; <<< CLEAR OLD_PORTB so next attempt is recognized >>>
    CLRF    OLD_PORTB
    RETURN

; ----------------------------------------------
; UPDATE_DISPLAY
; ----------------------------------------------
UPDATE_DISPLAY:
    MOVF    COUNT, W
    SUBLW   d'10'
    BTFSC   STATUS, Z
        BSF     PORTD, 7
    BTFSS   STATUS, Z
        BCF     PORTD, 7

    MOVF    COUNT, W
    SUBLW   d'10'
    BTFSC   STATUS, Z
        GOTO SHOW_ZERO_FOR_TEN

    CALL    CONVERT_TO_7SEG
    MOVWF   TEMP
    GOTO    SET_SEGMENTS

SHOW_ZERO_FOR_TEN:
    ; Pattern for "1"
    MOVLW   b'00000110'
    MOVWF   TEMP

SET_SEGMENTS:
    MOVF    PORTD, W
    ANDLW   b'10000000'
    IORWF   TEMP, W
    MOVWF   PORTD
    RETURN

; ----------------------------------------------
; 7-SEG DECODER (0..9)
; ----------------------------------------------
CONVERT_TO_7SEG:
    MOVF    COUNT, W
    ADDWF   PCL, F
    RETLW   b'00111111'  ; 0
    RETLW   b'00000110'  ; 1
    RETLW   b'01011011'  ; 2
    RETLW   b'01001111'  ; 3
    RETLW   b'01100110'  ; 4
    RETLW   b'01101101'  ; 5
    RETLW   b'01111101'  ; 6
    RETLW   b'00000111'  ; 7
    RETLW   b'01111111'  ; 8
    RETLW   b'01101111'  ; 9

; ----------------------------------------------
; BEEP_5SEC
; ----------------------------------------------
BEEP_5SEC:
    BSF     PORTA, 2
    MOVLW   d'5'
    MOVWF   loop3
BEEP_LOOP:
    CALL    DELAY_1S
    DECFSZ  loop3, F
    GOTO    BEEP_LOOP
    BCF     PORTA, 2
    RETURN

; ----------------------------------------------
; DELAY_1S ~1 second at ~4 MHz
; Double-loop approach
; ----------------------------------------------
DELAY_1S:
    MOVLW   d'200'
    MOVWF   loop1
D1_OUTER:
    MOVLW   d'250'
    MOVWF   loop2
D1_INNER:

    NOP
    NOP
    NOP
    NOP

    DECFSZ loop2, F
    GOTO   D1_INNER
    DECFSZ loop1, F
    GOTO   D1_OUTER
    RETURN

            END
