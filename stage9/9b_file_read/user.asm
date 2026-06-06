; ============================================================================
; 9b user.asm  --  testet readfile
; ----------------------------------------------------------------------------
; Liest die ganze Datei "greet.txt" per Syscall in einen Puffer und gibt sie aus.
; Syscalls:  1=exit  4=write(buf,len)  13=readfile(name,buf)->size/-1
; ============================================================================

bits 32
org  0x800000

SYS_EXIT     equ 1
SYS_WRITE    equ 4
SYS_READFILE equ 13
USER_DATA    equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; size = readfile("greet.txt", buf)
    mov eax, SYS_READFILE
    mov ebx, fname
    mov ecx, buf
    int 0x80
    test eax, eax
    js .err
    mov [fsize], eax

    ; write(buf, size)
    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, buf
    mov edx, [fsize]
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

fname  db 'greet.txt', 0
errmsg db 'readfile fehlgeschlagen', 0x0A
errlen equ $ - errmsg
fsize  dd 0
buf    times 2048 db 0
