; ============================================================================
; 12a shell.asm  --  Shell als Prozess auf dem Multitasking-Kernel
; ----------------------------------------------------------------------------
; Eingebettet als Prozess 0 (init). Liest Kommandos (blockierend) und startet
; Programme per exec. Foreground: exec wartet, bis das Kind fertig ist.
;
; Syscalls:  1=exit  3=read  4=write  11=exec(name,len)->0/-1
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

    mov ecx, eax              ; len
    mov eax, SYS_EXEC
    mov ebx, linebuf
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

banner   db 'Shell (Multitasking-Kernel). Programme: hello, count', 0x0A
banner_len equ $ - banner
prompt   db '$ '
prompt_len equ $ - prompt
notfound db '?: nicht gefunden', 0x0A
notfound_len equ $ - notfound
linebuf  times 128 db 0
