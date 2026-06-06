; ============================================================================
; 5 user.asm  --  unveraendert wie 4d, aber jetzt liegt es als /init.bin
; ----------------------------------------------------------------------------
; Identisches Programm wie 4d -- write + exit. Es weiss nicht, dass es jetzt
; nicht mehr in den Kernel eingebettet ist, sondern aus dem Dateisystem
; geladen wurde. Genau richtig: einem User-Programm soll der Lade-Mechanismus
; egal sein.
;
; Linus' /sbin/init macht im Prinzip genau dasselbe Spiel, nur dass es danach
; eine Shell startet statt zu exitieren.
; ============================================================================

bits 32
org  0x40000

USER_DATA equ 0x23

user_entry:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov eax, 4                ; sys_write
    mov ebx, 1                ; fd
    mov ecx, msg
    mov edx, msg_len
    int 0x80

    mov eax, 1                ; sys_exit
    xor ebx, ebx
    int 0x80

.never:
    jmp .never

msg     db 'Hallo aus /init.bin -- vom Minix-FS geladen, nicht eingebettet!', 10, 0
msg_len equ $ - msg - 1
