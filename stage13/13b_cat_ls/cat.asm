; ============================================================================
; 13b cat.asm  --  gibt den Inhalt einer Datei aus
; ----------------------------------------------------------------------------
; Liest das erste Argument (Dateiname) aus der cmdline (0x803000), laedt die
; Datei per readfile-Syscall und gibt sie aus.
; ============================================================================

bits 32
org  0x800000

SYS_EXIT     equ 1
SYS_WRITE    equ 4
SYS_READFILE equ 13
USER_DATA    equ 0x23
ARGS         equ 0x803000

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov esi, ARGS                    ; Programmnamen ueberspringen
.skip:
    mov al, [esi]
    test al, al
    jz .err
    inc esi
    cmp al, ' '
    jne .skip
    ; esi -> Dateiname (null-terminiert)
    mov eax, SYS_READFILE
    mov ebx, esi
    mov ecx, buf
    int 0x80
    test eax, eax
    js .err
    mov edx, eax
    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, buf
    int 0x80
    jmp .done
.err:
    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, errmsg
    mov edx, errlen
    int 0x80
.done:
    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

errmsg db 'cat: Datei nicht gefunden', 0x0A
errlen equ $ - errmsg
buf    equ 0x804000              ; Daten-Page (vom Kernel gemappt, nicht im Binary)
