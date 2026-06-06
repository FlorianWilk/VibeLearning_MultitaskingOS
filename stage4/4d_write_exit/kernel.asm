; ============================================================================
; 4d kernel.asm  --  sys_write + sys_exit
; ----------------------------------------------------------------------------
; AENDERUNG zu 4c: aus dem Demo-Handler wird ein echter Syscall-Dispatcher.
; Wir implementieren zwei Syscalls (genau die ersten zwei, die Linus 1991
; hatte):
;
;     eax = 1   sys_exit(ebx = code)
;                 Kernel zeigt "exited (code = N)" und legt sich schlafen.
;     eax = 4   sys_write(ebx = fd, ecx = buf, edx = len)
;                 Kernel schreibt len Bytes ab buf auf den Bildschirm.
;
; Das ist alles. Mit diesen zwei Syscalls hat man bereits ein "Programm das
; etwas ausgibt und sauber endet" -- den Kern jedes klassischen Unix-Tools.
;
; Da User und Kernel im selben flachen Adressraum leben (kein Paging), kann
; der Kernel die User-Adresse in ecx einfach direkt lesen. In modernen
; Kerneln mit Paging waere das ein "copy_from_user" Helfer.
; ============================================================================

bits 32
org  0x10000

VGA          equ 0xB8000
WHITE        equ 0x0F
YELLOW       equ 0x0E
GREEN        equ 0x0A
COLS         equ 80
ROWB         equ COLS * 2
KERNEL_STACK equ 0x90000
USER_ENTRY   equ 0x40000
USER_STACK   equ 0x80000

kernel_start:
    mov esp, KERNEL_STACK

    ; ---- GDT/TSS/IDT wie 4c --------------------------------------------
    mov ebx, tss_main
    mov edi, gdt_tss
    mov [edi + 2], bx
    shr ebx, 16
    mov [edi + 4], bl
    mov [edi + 7], bh
    lgdt [gdt_descriptor]
    jmp 0x08:.cs_reloaded
.cs_reloaded:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov dword [tss_main + 4], KERNEL_STACK
    mov dword [tss_main + 8], 0x10
    mov ax, 0x28
    ltr ax
    call idt_setup
    lidt [idt_descriptor]

    ; ---- Header ueber screen_puts (nutzt cursor) -----------------------
    mov esi, msg_status
    call screen_puts
    mov esi, msg_jump
    call screen_puts

    ; ---- User-Programm laden und Sprung nach Ring 3 --------------------
    mov esi, user_image
    mov edi, USER_ENTRY
    mov ecx, user_image_end - user_image
    cld
    rep movsb

    push dword 0x23
    push dword USER_STACK
    push dword 0x202
    push dword 0x1B
    push dword USER_ENTRY
    iret

; ============================================================================
; idt_setup: Vektor 0x80 -> syscall_dispatch (DPL=3, Trap Gate)
; ============================================================================
idt_setup:
    mov eax, syscall_dispatch
    mov word [idt + 0x80*8 + 0], ax
    mov word [idt + 0x80*8 + 2], 0x08
    mov byte [idt + 0x80*8 + 4], 0x00
    mov byte [idt + 0x80*8 + 5], 0xEF
    shr eax, 16
    mov word [idt + 0x80*8 + 6], ax
    ret

; ============================================================================
; syscall_dispatch  --  Eingang fuer int 0x80
;   eax = Nummer, ebx/ecx/edx = Args (alles noch in CPU-Registern vom User).
; ============================================================================
syscall_dispatch:
    pusha
    cmp eax, 1
    je sys_exit
    cmp eax, 4
    je sys_write
    ; unbekannter Syscall -> stillschweigend zurueck
    popa
    iret

; ----------------------------------------------------------------------------
; sys_write(ebx = fd, ecx = buf, edx = len)
;   fd ignoriert; schreibt len Bytes ab buf via screen_putc.
; ----------------------------------------------------------------------------
sys_write:
    mov byte [attr], YELLOW    ; User-Output in Gelb, damit man's erkennt
    mov esi, ecx               ; buf
    mov ecx, edx               ; len  (Loop-Zaehler)
.next:
    test ecx, ecx
    jz .done
    lodsb
    call screen_putc
    dec ecx
    jmp .next
.done:
    mov byte [attr], WHITE     ; zurueck auf Kernel-Default
    popa
    iret

; ----------------------------------------------------------------------------
; sys_exit(ebx = code)
;   Kernel zeigt "[process exited (code = 0xNNNNNNNN)]" und haengt.
;   Kein iret -- User kommt nie zurueck.
; ----------------------------------------------------------------------------
sys_exit:
    cli                        ; keine Interrupts mehr -- wir sind fertig
    mov esi, msg_exited
    call screen_puts
    mov eax, ebx               ; Exit-Code
    call screen_puthex
    mov esi, msg_close
    call screen_puts
.hang:
    hlt
    jmp .hang

; ============================================================================
; screen_putc  --  al = Zeichen; nutzt [cursor], [attr]; behandelt \n
; ============================================================================
screen_putc:
    push eax
    push ebx
    push edx
    cmp al, 0x0A               ; \n?
    je .nl
    mov ah, [attr]
    mov edx, [cursor]
    mov [VGA + edx], ax        ; ASCII + Attribut in einer Aktion
    add edx, 2
    mov [cursor], edx
    jmp .done
.nl:
    mov eax, [cursor]
    xor edx, edx
    mov ebx, ROWB
    div ebx                    ; eax = Zeile, edx = Spalte*2
    inc eax
    mul ebx
    mov [cursor], eax
.done:
    pop edx
    pop ebx
    pop eax
    ret

; ============================================================================
; screen_puts  --  esi = 0-terminiert; Schleife ueber screen_putc
; ============================================================================
screen_puts:
    push eax
.loop:
    lodsb
    test al, al
    jz .done
    call screen_putc
    jmp .loop
.done:
    pop eax
    ret

; ============================================================================
; screen_puthex  --  eax = 32-bit; "XXXXXXXX" via screen_putc
; ============================================================================
screen_puthex:
    push eax
    push ebx
    push ecx
    push edx
    mov edx, eax
    mov ecx, 8
.next:
    rol edx, 4
    mov ebx, edx
    and ebx, 0x0F
    mov al, [hexchars + ebx]
    call screen_putc
    loop .next
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ============================================================================
; Daten
; ============================================================================
msg_status db '4d: sys_write + sys_exit -- Unix-style aus Ring 3', 10, 0
msg_jump   db 'Springe nach Ring 3 -- User wird write(msg) + exit(0) rufen:', 10, 10, 0
msg_exited db '[process exited (code = 0x', 0
msg_close  db ')]', 10, 0

hexchars   db '0123456789ABCDEF'

attr       db WHITE
cursor     dd 0

; ============================================================================
; Eingebettetes User-Programm
; ============================================================================
align 16
user_image:
    incbin "user.bin"
user_image_end:

; ============================================================================
; GDT + IDT + TSS (identisch zu 4c)
; ============================================================================
align 8
gdt_start:
    dq 0
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 11001111b
    db 0x00
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b
    db 11001111b
    db 0x00
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 11111010b
    db 11001111b
    db 0x00
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 11110010b
    db 11001111b
    db 0x00
gdt_tss:
    dw 0x67
    dw 0x0000
    db 0x00
    db 0x89
    db 0x00
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

align 8
idt:
    times 256*8 db 0
idt_end:

idt_descriptor:
    dw idt_end - idt - 1
    dd idt

align 4
tss_main:
    times 104 db 0
