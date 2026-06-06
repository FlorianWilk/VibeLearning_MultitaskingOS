; ============================================================================
; 8a shell.asm  --  Die Shell als echtes Ring-3-User-Programm
; ----------------------------------------------------------------------------
; Laeuft in Ring 3 bei virtueller Adresse 0x800000, in einem eigenen, per
; Paging isolierten Adressraum. Sie kann NUR ueber Syscalls mit dem Kernel
; reden -- genau wie /bin/sh unter echtem Unix.
;
; In 8a kann sie: ein Prompt schreiben, eine Zeile lesen, sie zurueck-echoen.
; Das Ausfuehren von Programmen (exec) kommt in 8b.
;
; Syscalls:  1=exit  3=read(buf,max)->len  4=write(buf,len)
; ============================================================================

bits 32
org  0x800000

SYS_EXIT  equ 1
SYS_READ  equ 3
SYS_WRITE equ 4
USER_DATA equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Begruessung einmalig
    mov ecx, banner
    mov edx, banner_len
    call write

.loop:
    ; Prompt
    mov ecx, prompt
    mov edx, prompt_len
    call write

    ; Zeile lesen (blockiert bis Enter); eax = Laenge
    mov eax, SYS_READ
    mov ebx, linebuf
    mov ecx, 128
    int 0x80
    mov [linelen], eax

    ; "du tipptest: " + Zeile + Newline
    mov ecx, echomsg
    mov edx, echomsg_len
    call write
    mov ecx, linebuf
    mov edx, [linelen]
    call write
    mov ecx, newline
    mov edx, 1
    call write

    jmp .loop

; ----------------------------------------------------------------------------
; write(ecx = buf, edx = len)
; ----------------------------------------------------------------------------
write:
    mov eax, SYS_WRITE
    mov ebx, 1
    int 0x80
    ret

banner  db 'Mini-Shell (Ring 3). Tippe etwas und druecke Enter.', 0x0A
banner_len equ $ - banner
prompt  db '$ '
prompt_len equ $ - prompt
echomsg db 'du tipptest: '
echomsg_len equ $ - echomsg
newline db 0x0A

linelen dd 0
linebuf times 128 db 0
