; ============================================================================
; 10b proc_b.asm  --  das LEBENSZEICHEN: zaehlt sichtbar weiter
; ----------------------------------------------------------------------------
; Schreibt endlos rotierende Ziffern 0..9. Solange diese erscheinen, laeuft
; die CPU -- auch waehrend proc_a auf Tastatureingabe BLOCKIERT ist. Das ist
; der Beweis: blockierende I/O verschwendet keine CPU-Zeit (anders als Polling).
; ============================================================================

bits 32
org  0x800000

SYS_WRITE equ 4
USER_DATA equ 0x23
DELAY     equ 0x00500000

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
.loop:
    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, digit
    mov edx, 1
    int 0x80
    inc byte [digit]
    cmp byte [digit], '9'
    jbe .nowrap
    mov byte [digit], '0'
.nowrap:
    mov ecx, DELAY
.d:
    dec ecx
    jnz .d
    jmp .loop

digit db '0'
