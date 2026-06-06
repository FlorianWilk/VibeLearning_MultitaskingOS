; ============================================================================
; 7b proc_a.asm  --  laeuft bei VIRTUELLER Adresse 0x800000
; ----------------------------------------------------------------------------
; Wichtig: proc_a UND proc_b sind beide auf org 0x800000 assembliert -- sie
; benutzen dieselben virtuellen Adressen! Moeglich wird das nur durch Paging:
; jeder Prozess hat ein eigenes Page Directory, das 0x800000 auf einen anderen
; physischen Frame zeigen laesst. Echte Adressraum-Isolation.
; ============================================================================

bits 32
org  0x800000

USER_DATA equ 0x23
DELAY     equ 0x00180000

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
.loop:
    mov eax, 4
    mov ebx, 1
    mov ecx, mychar
    mov edx, 1
    int 0x80
    mov edi, DELAY
.delay:
    dec edi
    jnz .delay
    jmp .loop

mychar db 'A'
