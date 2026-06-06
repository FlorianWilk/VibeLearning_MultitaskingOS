; ============================================================================
; 11b user.asm  --  writefile testen: schreiben, dann zuruecklesen
; ----------------------------------------------------------------------------
; Schreibt Text in die Minix-Datei "notiz", liest sie mit readfile zurueck und
; gibt sie aus. Erscheint der Text, funktioniert das Schreiben ins Dateisystem.
; ============================================================================

bits 32
org  0x800000

SYS_EXIT      equ 1
SYS_WRITE     equ 4
SYS_READFILE  equ 13
SYS_WRITEFILE equ 16
USER_DATA     equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov eax, SYS_WRITEFILE         ; "notiz" schreiben
    mov ebx, fname
    mov ecx, text
    mov edx, text_len
    int 0x80

    mov eax, SYS_READFILE          ; "notiz" zuruecklesen
    mov ebx, fname
    mov ecx, rbuf
    int 0x80
    mov [rlen], eax

    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, rbuf
    mov edx, [rlen]
    int 0x80

    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

fname db 'notiz', 0
text  db 'In die Minix-Datei geschrieben und zurueckgelesen!', 0x0A
text_len equ $ - text
rlen  dd 0
rbuf  times 512 db 0
