; ============================================================================
; 10b proc_a.asm  --  der LESER: blockiert auf Tastatureingabe
; ----------------------------------------------------------------------------
; read() blockiert diesen Prozess, bis eine Zeile getippt wurde. Waehrend er
; blockiert ist, laeuft proc_b weiter (Beweis: dessen Ziffern erscheinen).
; ============================================================================

bits 32
org  0x800000

SYS_READ  equ 3
SYS_WRITE equ 4
USER_DATA equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
.loop:
    mov eax, SYS_READ              ; blockiert bis Enter
    mov ebx, buf
    mov ecx, 64
    int 0x80
    mov [len], eax

    mov ecx, ob                   ; "  [du: "
    mov edx, ob_len
    call write
    mov ecx, buf
    mov edx, [len]
    call write
    mov ecx, cb                   ; "]" + Newline
    mov edx, cb_len
    call write
    jmp .loop

write:
    mov eax, SYS_WRITE
    mov ebx, 1
    int 0x80
    ret

ob  db 0x0A, '  [du: '
ob_len equ $ - ob
cb  db ']', 0x0A
cb_len equ $ - cb
len dd 0
buf times 64 db 0
