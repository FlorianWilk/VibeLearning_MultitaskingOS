; ============================================================================
; 7b proc_b.asm  --  laeuft ebenfalls bei VIRTUELLER Adresse 0x800000
; ----------------------------------------------------------------------------
; Identisch zu proc_a, nur das Zeichen ist 'B'. BEIDE auf org 0x800000 -- sie
; teilen sich die virtuelle Adresse, liegen aber physisch getrennt (eigenes
; Page Directory pro Prozess).
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

mychar db 'B'
