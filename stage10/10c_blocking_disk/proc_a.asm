; ============================================================================
; 10c proc_a.asm  --  liest einen Sektor von der Disk (blockierend per IRQ14)
; ----------------------------------------------------------------------------
; read_disk blockiert, bis IRQ14 die Daten geliefert hat. Waehrend dessen laeuft
; proc_b weiter (Ziffern). Danach zeigt proc_a den gelesenen Text.
; ============================================================================

bits 32
org  0x800000

SYS_EXIT     equ 1
SYS_WRITE    equ 4
SYS_READDISK equ 14
USER_DATA    equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; read_disk(sektor=1, buf)  -- blockiert bis IRQ14
    mov eax, SYS_READDISK
    mov ebx, 1
    mov ecx, buf
    int 0x80

    mov eax, SYS_WRITE         ; "  >> " + Disk-Text
    mov ebx, 1
    mov ecx, pre
    mov edx, pre_len
    int 0x80
    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, buf
    mov edx, 40
    int 0x80

    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

pre db 0x0A, '  >> Disk: '
pre_len equ $ - pre
buf times 512 db 0
