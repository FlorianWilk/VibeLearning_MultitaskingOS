; ============================================================================
; 4d user.asm  --  Erstes Unix-style User-Programm
; ----------------------------------------------------------------------------
; Wenn du squintest, ist das hier schon ein winziges C-Programm:
;
;     int main(void) {
;         write(1, "Hallo aus Userland!\n", 20);
;         exit(0);
;     }
;
; In Linus' Linux 1991 sind die Syscall-Nummern:
;     1 = exit
;     4 = write
; Genau die nehmen wir.
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

    ; ---- write(1, msg, msg_len) ----------------------------------------
    mov eax, 4                ; sys_write
    mov ebx, 1                ; fd = stdout (vom Kernel ignoriert)
    mov ecx, msg              ; Puffer
    mov edx, msg_len          ; Laenge
    int 0x80

    ; ---- exit(0)  -- kehrt nicht zurueck -------------------------------
    mov eax, 1                ; sys_exit
    xor ebx, ebx              ; Exit-Code 0
    int 0x80

    ; Sicherheits-Netz, falls exit doch zurueckkommt
.never:
    jmp .never

msg     db 'Hallo aus Userland! (geschrieben via sys_write)', 10, 0
msg_len equ $ - msg - 1       ; Laenge ohne den Null-Terminator
