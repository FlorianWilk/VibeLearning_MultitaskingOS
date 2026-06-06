; ============================================================================
; 13a echo.asm  --  gibt seine Argumente aus
; ----------------------------------------------------------------------------
; Liest die Kommandozeile, die der Kernel bei virt 0x803000 abgelegt hat,
; ueberspringt das erste Wort (den Programmnamen "echo") und gibt den Rest aus.
; Beweist: Argument-Passing funktioniert.
; ============================================================================

bits 32
org  0x800000

SYS_EXIT  equ 1
SYS_WRITE equ 4
USER_DATA equ 0x23
ARGS      equ 0x803000              ; hierhin legt der Kernel die cmdline

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov esi, ARGS
    ; bis zum ersten Leerzeichen (Ende des Programmnamens)
.skipname:
    mov al, [esi]
    test al, al
    jz .nl                          ; keine Argumente -> nur Newline
    inc esi
    cmp al, ' '
    jne .skipname
    ; esi steht jetzt auf dem ersten Argument; Laenge bis 0 messen
    mov ecx, esi
    xor edx, edx
.len:
    mov al, [esi]
    test al, al
    jz .out
    inc esi
    inc edx
    jmp .len
.out:
    mov eax, SYS_WRITE
    mov ebx, 1
    int 0x80                         ; ecx=arg, edx=len
.nl:
    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, newline
    mov edx, 1
    int 0x80
    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

newline db 0x0A
