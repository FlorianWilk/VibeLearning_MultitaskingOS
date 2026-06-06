; ============================================================================
; 13b ls.asm  --  listet die Dateien im Verzeichnis
; ----------------------------------------------------------------------------
; Holt per listdir-Syscall die Dateinamen (newline-getrennt) und gibt sie aus.
; ============================================================================

bits 32
org  0x800000

SYS_EXIT    equ 1
SYS_WRITE   equ 4
SYS_LISTDIR equ 17
USER_DATA   equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov eax, SYS_LISTDIR
    mov ebx, buf
    int 0x80                         ; eax = Gesamtlaenge

    mov edx, eax
    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, buf
    int 0x80

    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

buf equ 0x804000                 ; Daten-Page (vom Kernel gemappt)
