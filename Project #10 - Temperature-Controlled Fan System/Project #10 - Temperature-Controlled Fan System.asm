; Project 10: Temperature-Controlled Fan System 
;  Model / Stack  (required by emu8086)

.MODEL SMALL
.STACK 100h

;  Hardware constants

PORT_A      EQU 00F8h
PORT_B      EQU 00F9h
PORT_C      EQU 00FAh
PORT_CTRL   EQU 00FBh

PPI_CTRL_MIXED EQU 98h          ; A=in, B=out, CL=out, CH=in

; Port-B output bits
GREEN_LED   EQU 00000001b
YELLOW_LED  EQU 00000010b
RED_LED     EQU 00000100b
MOTOR_ON    EQU 00001000b
MOTOR_HIGH  EQU 00010000b

; Port-C bit masks
ADC_WR      EQU 00000001b       ; PC0 – active-low WR pulse to ADC
ADC_RD      EQU 00000010b       ; PC1 – active-low RD to ADC
BUZZER      EQU 00000100b       ; PC2 – buzzer drive
PC_OUT_MSK  EQU 00000111b       ; only lower 3 bits are outputs
INTR_PC4    EQU 00010000b       ; PC4 – ADC INTR (low = conversion done)

; Temperature thresholds (°C, after scaling 0-255 → 0-100)
TEMP_LOW    EQU 30
TEMP_MED    EQU 60
TEMP_HIGH   EQU 100

;  Data segment

.DATA
    PC_SHADOW   DB 0
    MSG_INIT    DB 'Temperature-Controlled Fan System Started', 0Dh, 0Ah, '$'
    MSG_OFF     DB 'Status: FAN OFF   | GREEN  LED ON | Temp < 30C ', 0Dh, 0Ah, '$'
    MSG_LOW     DB 'Status: FAN LOW   | YELLOW LED ON | 30C - 60C  ', 0Dh, 0Ah, '$'
    MSG_HIGH    DB 'Status: FAN HIGH  | RED    LED ON | 60C - 100C ', 0Dh, 0Ah, '$'
    MSG_ALARM   DB 'STATUS: EMERGENCY! SHUTDOWN! TEMP >= 100C !!!  ', 0Dh, 0Ah, '$'
    MSG_TEMP    DB 'Current Temp: $'
    MSG_DEG     DB ' C', 0Dh, 0Ah, '$'
    MSG_SEP     DB '---------------------------------------------------', 0Dh, 0Ah, '$'


;  Code segment
.CODE

; ═════════════════════════════════════════════
MAIN PROC
; 
    MOV AX, @DATA
    MOV DS, AX

    ; Initialise PPI
    MOV AL, PPI_CTRL_MIXED
    OUT PORT_CTRL, AL

    ; Clear all outputs
    MOV BYTE PTR [PC_SHADOW], 0
    MOV AL, 00h
    OUT PORT_B, AL
    CALL WRITE_PC

    ; Startup banner
    LEA DX, MSG_INIT
    MOV AH, 09h
    INT 21h

    LEA DX, MSG_SEP
    MOV AH, 09h
    INT 21h

MAIN_LOOP:

    ; --- Trigger ADC conversion ---
    CALL START_ADC

    ; --- Wait for INTR (PC4 low) ---
    CALL WAIT_ADC

    ; --- Read raw 8-bit ADC value into AL ---
    CALL READ_ADC

    ; --- Scale: temp = raw * 100 / 255  (result in BL) ---
    ; AL holds raw value; use AX for 16-bit multiply
    XOR AH, AH              ; AX = raw (0-255)
    MOV BX, 100
    MUL BX                  ; DX:AX = raw * 100  (fits in AX, DX=0)
    MOV BX, 255
    DIV BX                  ; AX = (raw*100)/255 , DX = remainder
    MOV BL, AL              ; BL = scaled temperature (°C)

    ; --- Print label ---
    LEA DX, MSG_TEMP
    MOV AH, 09h
    INT 21h

    ; --- Print numeric value (BL = temperature) ---
    CALL PRINT_TEMP

    ; --- Print unit ---
    LEA DX, MSG_DEG
    MOV AH, 09h
    INT 21h

    ; --- Branch on temperature ---
    CMP BL, TEMP_HIGH
    JAE EMERGENCY

    CMP BL, TEMP_MED
    JAE FAN_HIGH_SPEED

    CMP BL, TEMP_LOW
    JAE FAN_LOW_SPEED

; ── Fan OFF (< 30 °C) ────────────────────────
FAN_OFF:
    MOV AL, GREEN_LED
    OUT PORT_B, AL
    CALL PC_CLEAR_OUTPUTS

    LEA DX, MSG_OFF
    MOV AH, 09h
    INT 21h

    JMP DELAY_NEXT

; ── Fan LOW (30-59 °C) ───────────────────────
FAN_LOW_SPEED:
    MOV AL, YELLOW_LED OR MOTOR_ON
    OUT PORT_B, AL
    CALL PC_CLEAR_OUTPUTS

    LEA DX, MSG_LOW
    MOV AH, 09h
    INT 21h

    JMP DELAY_NEXT

; ── Fan HIGH (60-99 °C) ──────────────────────
FAN_HIGH_SPEED:
    MOV AL, RED_LED OR MOTOR_ON OR MOTOR_HIGH
    OUT PORT_B, AL
    CALL PC_CLEAR_OUTPUTS

    LEA DX, MSG_HIGH
    MOV AH, 09h
    INT 21h

    JMP DELAY_NEXT

; ── EMERGENCY (>= 100 °C) ────────────────────
EMERGENCY:
    ; Motor off immediately
    MOV AL, 00h
    OUT PORT_B, AL

    ; Buzzer on
    MOV AL, BUZZER
    MOV [PC_SHADOW], AL
    CALL WRITE_PC

    LEA DX, MSG_ALARM
    MOV AH, 09h
    INT 21h

    ; Flash red LED 5 times
    MOV CX, 5
FLASH_LOOP:
    MOV AL, RED_LED
    OUT PORT_B, AL
    CALL SHORT_DELAY

    MOV AL, 00h
    OUT PORT_B, AL
    CALL SHORT_DELAY

    LOOP FLASH_LOOP

    ; Keep buzzer on for a while, then fall through to delay
    CALL LONG_DELAY

; ── Common 3-minute wait before next reading ─
DELAY_NEXT:
    LEA DX, MSG_SEP
    MOV AH, 09h
    INT 21h

    CALL DELAY_3_MINUTES

    JMP MAIN_LOOP

MAIN ENDP

; ══════════════════════════════════════════════
;  Write PC_SHADOW → Port-C  (masks to lower 3 bits)
; ══════════════════════════════════════════════
WRITE_PC PROC
    PUSH AX
    MOV AL, [PC_SHADOW]
    AND AL, PC_OUT_MSK
    OUT PORT_C, AL
    POP AX
    RET
WRITE_PC ENDP

; ══════════════════════════════════════════════
;  Clear Port-C output bits (WR, RD, BUZZER)
; ══════════════════════════════════════════════
PC_CLEAR_OUTPUTS PROC
    MOV BYTE PTR [PC_SHADOW], 0
    CALL WRITE_PC
    RET
PC_CLEAR_OUTPUTS ENDP

; ══════════════════════════════════════════════
;  Pulse ADC WR line (PC0): high→low starts conversion
; ══════════════════════════════════════════════
START_ADC PROC
    PUSH AX
    ; Assert WR (set PC0 high)
    MOV AL, [PC_SHADOW]
    OR  AL, ADC_WR
    MOV [PC_SHADOW], AL
    CALL WRITE_PC
    CALL TINY_DELAY
    ; De-assert WR (clear PC0)
    MOV AL, [PC_SHADOW]
    AND AL, NOT ADC_WR      ; 0FEh
    MOV [PC_SHADOW], AL
    CALL WRITE_PC
    POP AX
    RET
START_ADC ENDP

; ══════════════════════════════════════════════
;  Wait until ADC INTR (PC4) goes LOW
; ══════════════════════════════════════════════
WAIT_ADC PROC
    PUSH AX
    PUSH BX
    PUSH CX

    CALL SHORT_DELAY            ; give ADC time to start

    MOV BX, 0FFFFh              ; timeout counter
WADC_LOOP:
    IN  AL, PORT_C
    TEST AL, INTR_PC4
    JZ  WADC_DONE               ; PC4 low → conversion done

    MOV CX, 40                  ; short pause between polls
WADC_PAUSE:
    LOOP WADC_PAUSE

    DEC BX
    JNZ WADC_LOOP

WADC_DONE:
    POP CX
    POP BX
    POP AX
    RET
WAIT_ADC ENDP

; ══════════════════════════════════════════════
;  Assert ADC RD (PC1), read Port-A, de-assert RD
;  Returns: AL = raw ADC byte
; ══════════════════════════════════════════════
READ_ADC PROC
    PUSH BX
    ; Assert RD
    MOV AL, [PC_SHADOW]
    OR  AL, ADC_RD
    MOV [PC_SHADOW], AL
    CALL WRITE_PC
    CALL TINY_DELAY

    ; Read data
    IN  AL, PORT_A
    MOV BL, AL                  ; save result

    ; De-assert RD
    MOV AL, [PC_SHADOW]
    AND AL, NOT ADC_RD          ; 0FDh
    MOV [PC_SHADOW], AL
    CALL WRITE_PC

    MOV AL, BL                  ; return value in AL
    POP BX
    RET
READ_ADC ENDP

; ══════════════════════════════════════════════
;  Print 8-bit decimal value in BL  (0-100)
;  Destroys: nothing (all registers preserved)
; ══════════════════════════════════════════════
PRINT_TEMP PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    ; BL holds the temperature; copy to AL for division
    MOV AL, BL
    XOR AH, AH

    ; Hundreds digit
    MOV BL, 100
    DIV BL                  ; AL = hundreds, AH = remainder

    CMP AL, 0
    JE  PT_TENS             ; skip leading zero

    ADD AL, '0'
    MOV DL, AL
    MOV AH, 02h
    INT 21h

PT_TENS:
    ; AL still has the digit; AH has remainder (0-99)
    ; But DIV overwrites AH — reload:
    ; We need the remainder which was in AH after the hundreds divide.
    ; To keep it clean, redo with the saved remainder.
    MOV AL, AH              ; AH = remainder after /100  (0-99)
    XOR AH, AH

    MOV BL, 10
    DIV BL                  ; AL = tens digit, AH = units digit

    ADD AL, '0'
    MOV DL, AL
    MOV AH, 02h
    INT 21h

    ; Units digit (saved in AH before the 02h call clobbered it? No –
    ;  INT 21h/02h preserves AH=02h.  The remainder is still in AH.)
    MOV DL, AH
    ADD DL, '0'
    MOV AH, 02h
    INT 21h

    POP DX
    POP CX
    POP BX
    POP AX
    RET
PRINT_TEMP ENDP

; ══════════════════════════════════════════════
;  Delay routines
; ══════════════════════════════════════════════
TINY_DELAY PROC
    PUSH CX
    MOV CX, 0FFh
TINY_L: LOOP TINY_L
    POP CX
    RET
TINY_DELAY ENDP

SHORT_DELAY PROC
    PUSH CX
    MOV CX, 0FFFFh
SHORT_L: LOOP SHORT_L
    POP CX
    RET
SHORT_DELAY ENDP

MEDIUM_DELAY PROC
    PUSH CX
    MOV CX, 0FFFFh
MED_OUTER:
    PUSH CX
    MOV CX, 0FFFFh
MED_INNER: LOOP MED_INNER
    POP CX
    LOOP MED_OUTER
    POP CX
    RET
MEDIUM_DELAY ENDP

LONG_DELAY PROC
    PUSH CX
    MOV CX, 30
LONG_OUTER:
    CALL MEDIUM_DELAY
    LOOP LONG_OUTER
    POP CX
    RET
LONG_DELAY ENDP

DELAY_3_MINUTES PROC
    PUSH CX
    MOV CX, 6
THREE_MIN_L:
    CALL LONG_DELAY
    LOOP THREE_MIN_L
    POP CX
    RET
DELAY_3_MINUTES ENDP

END MAIN