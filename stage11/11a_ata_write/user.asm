; ============================================================================
; 11a user.asm  --  Roundtrip: Sektor schreiben, dann zuruecklesen
; ----------------------------------------------------------------------------
; Schreibt einen Text in Sektor 5 (write_disk), liest ihn zurueck (read_disk)
; und gibt ihn aus. Erscheint der Text, funktioniert ATA-Write per IRQ.
; ============================================================================

bits 32
org  0x800000

SYS_EXIT      equ 1
SYS_WRITE     equ 4
SYS_READDISK  equ 14
SYS_WRITEDISK equ 15
USER_DATA     equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov eax, SYS_WRITEDISK         ; Sektor 5 schreiben
    mov ebx, 5
    mov ecx, wbuf
    int 0x80

    mov eax, SYS_READDISK          ; Sektor 5 zuruecklesen
    mov ebx, 5
    mov ecx, rbuf
    int 0x80

    mov eax, SYS_WRITE             ; ausgeben
    mov ebx, 1
    mov ecx, rbuf
    mov edx, wtext_len
    int 0x80

    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

wbuf:
    db 'Sektor 5: per IRQ geschrieben und wieder gelesen!', 0x0A
wtext_len equ $ - wbuf
    times 512 - wtext_len db 0
rbuf:
    times 512 db 0
