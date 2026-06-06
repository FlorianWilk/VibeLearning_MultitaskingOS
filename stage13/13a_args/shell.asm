; ============================================================================
; 12b shell.asm  --  Shell mit Hintergrund-Jobs (&)
; ----------------------------------------------------------------------------
; Enthaelt die Zeile ein '&', wird das Programm im HINTERGRUND gestartet:
; exec kehrt sofort zurueck (kein wait), die Shell nimmt gleich das naechste
; Kommando an, waehrend das Kind weiterlaeuft. Sonst Foreground (wait).
;
; exec-Konvention: eax=11, ebx=name, ecx=len, edx=bg (0/1)
; ============================================================================

bits 32
org  0x800000

SYS_EXIT  equ 1
SYS_READ  equ 3
SYS_WRITE equ 4
SYS_EXEC  equ 11
USER_DATA equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov ecx, banner
    mov edx, banner_len
    call write
.loop:
    mov ecx, prompt
    mov edx, prompt_len
    call write

    mov eax, SYS_READ
    mov ebx, linebuf
    mov ecx, 128
    int 0x80
    test eax, eax
    jz .loop
    mov [linelen], eax

    ; nach '&' suchen -> Hintergrund-Flag
    mov esi, linebuf
    mov ecx, eax
    xor edx, edx                  ; bg = 0
.scan:
    test ecx, ecx
    jz .scandone
    cmp byte [esi], '&'
    jne .sn
    mov dl, 1                     ; bg = 1
.sn:
    inc esi
    dec ecx
    jmp .scan
.scandone:
    ; exec(linebuf, linelen, bg)
    mov eax, SYS_EXEC
    mov ebx, linebuf
    mov ecx, [linelen]
    ; edx = bg
    int 0x80
    test eax, eax
    jns .loop
    mov ecx, notfound
    mov edx, notfound_len
    call write
    jmp .loop

write:
    mov eax, SYS_WRITE
    mov ebx, 1
    int 0x80
    ret

banner   db 'Shell mit Hintergrund-Jobs. Tipp z.B.: count &', 0x0A
banner_len equ $ - banner
prompt   db '$ '
prompt_len equ $ - prompt
notfound db '?: nicht gefunden', 0x0A
notfound_len equ $ - notfound
linelen  dd 0
linebuf  times 128 db 0
