; ============================================================================
; 12b count.asm  --  zaehlt 1..9 LANGSAM (mit Bremse)
; ----------------------------------------------------------------------------
; Die Bremse macht count langlaeufig genug, dass man im Hintergrund (count &)
; sieht, wie es weiterzaehlt, waehrend die Shell schon wieder reagiert.
; ============================================================================

bits 32
org  0x800000

SYS_EXIT  equ 1
SYS_WRITE equ 4
USER_DATA equ 0x23
DELAY     equ 0x02000000

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
    mov edx, 2
    int 0x80
    mov edi, DELAY                ; Bremse zwischen Ziffern
.d:
    dec edi
    jnz .d
    inc byte [digit]
    cmp byte [digit], '9'
    jbe .loop
    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

digit db '1', ' '
