; ============================================================================
; 8b hello.asm  --  ein Programm, das die Shell startet ("hello")
; ----------------------------------------------------------------------------
; Liegt als Datei "hello" auf der Minix-Disk. Die Shell laedt es per exec.
; Laeuft in seinem EIGENEN Adressraum bei virt 0x800000 (genau wie die Shell --
; aber isoliert). Schreibt einen Gruss, dann exit.
; ============================================================================

bits 32
org  0x800000

SYS_EXIT  equ 1
SYS_WRITE equ 4
USER_DATA equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, msg
    mov edx, msg_len
    int 0x80

    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

msg db 'Hallo! Ich bin /hello, ein eigener Prozess.', 0x0A
msg_len equ $ - msg
