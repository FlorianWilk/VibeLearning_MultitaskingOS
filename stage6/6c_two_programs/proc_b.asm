; ============================================================================
; 6c proc_b.asm  --  eigenstaendiges Programm B
; ----------------------------------------------------------------------------
; Identischer Aufbau wie proc_a, aber eigene Lade-Adresse (0x50000) und eigenes
; Zeichen ('B'). Voellig unabhaengiges Programm.
; ============================================================================

bits 32
org  0x50000

USER_DATA equ 0x23
DELAY     equ 0x00180000

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
.loop:
    mov eax, 4                ; sys_write
    mov ebx, 1                ; fd
    mov ecx, mychar
    mov edx, 1
    int 0x80
    mov edi, DELAY
.delay:
    dec edi
    jnz .delay
    jmp .loop

mychar db 'B'
