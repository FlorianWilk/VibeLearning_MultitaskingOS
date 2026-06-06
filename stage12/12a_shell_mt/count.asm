; ============================================================================
; 8b count.asm  --  Programm "count": zaehlt 1..9, dann exit
; ----------------------------------------------------------------------------
; Zeigt, dass die Shell verschiedene Programme starten kann. Eigener Adressraum.
; ============================================================================

bits 32
org  0x800000

SYS_EXIT  equ 1
SYS_WRITE equ 4
USER_DATA equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov byte [digit], '1'
.loop:
    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, digit
    mov edx, 2                 ; Ziffer + Leerzeichen
    int 0x80
    inc byte [digit]
    cmp byte [digit], '9'
    jbe .loop

    mov eax, SYS_WRITE         ; Newline am Ende
    mov ebx, 1
    mov ecx, nl
    mov edx, 1
    int 0x80

    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

digit db '1', ' '
nl    db 0x0A
