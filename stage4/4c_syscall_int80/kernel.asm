; ============================================================================
; 4c kernel.asm  --  int 0x80 Syscall-Mechanismus
; ----------------------------------------------------------------------------
; AENDERUNG zu 4b: IDT mit einem Eintrag fuer Vektor 0x80, der vom User-Ring
; aus aufrufbar ist. Wichtig: DPL=3 im Gate-Byte (sonst wirft die CPU eine
; GP-Fault, weil Ring 3 keine Erlaubnis hat, einen Ring-0-Gate-Eintrag
; aufzurufen).
;
; Konvention im Handler (wie Linus' Linux 1991):
;     eax = Syscall-Nummer
;     ebx, ecx, edx, esi, edi = Argumente
;
; Wir benutzen "Trap Gate" (Typ 0xF) statt "Interrupt Gate" (0xE), damit
; Interrupts waehrend des Syscalls AN bleiben -- so wie Linux es macht. Bei
; einem Trap Gate loescht die CPU IF nicht beim Eintritt.
;
; Beweis-Anzeige: der Handler druckt eax/ebx/ecx als Hex.
; ============================================================================

bits 32
org  0x10000

VGA          equ 0xB8000
WHITE        equ 0x0F
GREEN        equ 0x0A
COLS         equ 80
ROWB         equ COLS * 2
KERNEL_STACK equ 0x90000
USER_ENTRY   equ 0x40000
USER_STACK   equ 0x80000

kernel_start:
    mov esp, KERNEL_STACK

    ; ---- GDT/TSS wie in 4a/4b -------------------------------------------
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

    ; ---- IDT-Eintrag 0x80 (DPL=3, Trap Gate) ----------------------------
    call idt_setup
    lidt [idt_descriptor]

    mov esi, msg_status
    mov edi, 0
    call print_string

    ; ---- User-Programm laden + Sprung nach Ring 3 -----------------------
    mov esi, user_image
    mov edi, USER_ENTRY
    mov ecx, user_image_end - user_image
    cld
    rep movsb

    mov esi, msg_jump
    mov edi, ROWB * 2
    call print_string

    push dword 0x23
    push dword USER_STACK
    push dword 0x202
    push dword 0x1B
    push dword USER_ENTRY
    iret

; ============================================================================
; idt_setup: Vektor 0x80 -> syscall_handler, Gate-Byte 0xEF
;     0xEF = P=1, DPL=3, S=0, Type=1111 (32-bit Trap Gate)
; Ohne DPL=3 koennte Ring 3 das Gate nicht aufrufen (GP-Fault).
; ============================================================================
idt_setup:
    mov eax, syscall_handler
    mov word [idt + 0x80*8 + 0], ax
    mov word [idt + 0x80*8 + 2], 0x08          ; Kernel-Code-Selektor
    mov byte [idt + 0x80*8 + 4], 0x00
    mov byte [idt + 0x80*8 + 5], 0xEF          ; <-- DPL=3 ist hier entscheidend
    shr eax, 16
    mov word [idt + 0x80*8 + 6], ax
    ret

; ============================================================================
; syscall_handler  --  Dispatcher fuer int 0x80
;   Bekommt: eax = Nummer, ebx/ecx/edx = Args (User-Register, noch in CPU)
;   Aufgabe in 4c: Werte protokollieren und sauber zurueckkehren.
; ============================================================================
syscall_handler:
    ; User-Register sichern, BEVOR wir sie ueberschreiben
    mov [user_eax], eax
    mov [user_ebx], ebx
    mov [user_ecx], ecx

    pusha                              ; alle GP-Regs sichern (popa restore vor iret)

    mov esi, msg_got
    mov edi, ROWB * 10
    call print_string

    mov esi, lbl_eax
    mov edi, ROWB * 11
    call print_string
    mov eax, [user_eax]
    call print_hex_dword

    mov esi, lbl_ebx
    mov edi, ROWB * 12
    call print_string
    mov eax, [user_ebx]
    call print_hex_dword

    mov esi, lbl_ecx
    mov edi, ROWB * 13
    call print_string
    mov eax, [user_ecx]
    call print_hex_dword

    popa                               ; User-Register wiederherstellen
    iret                               ; zurueck nach Ring 3, hinter int 0x80

; ============================================================================
; print_hex_dword: eax = 32-Bit-Wert, edi = VGA-Offset; edi += 16
; ============================================================================
print_hex_dword:
    push eax
    push ecx
    push edx
    mov edx, eax
    mov ecx, 8
.next:
    rol edx, 4
    mov eax, edx
    and eax, 0x0F
    mov al, [hexchars + eax]
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], GREEN
    add edi, 2
    loop .next
    pop edx
    pop ecx
    pop eax
    ret

; ============================================================================
; print_string mit \n-Unterstuetzung
; ============================================================================
print_string:
    push eax
    push edx
    push ebx
.next:
    lodsb
    test al, al
    jz .done
    cmp al, 10
    je .nl
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], WHITE
    add edi, 2
    jmp .next
.nl:
    mov eax, edi
    xor edx, edx
    mov ebx, ROWB
    div ebx
    inc eax
    mul ebx
    mov edi, eax
    jmp .next
.done:
    pop ebx
    pop edx
    pop eax
    ret

; ============================================================================
; Daten
; ============================================================================
msg_status db '4c: IDT 0x80 (DPL=3, Trap Gate) eingerichtet', 0
msg_jump   db 'Springe nach Ring 3 -- User wird gleich int 0x80 rufen:', 0
msg_got    db '*** SYSCALL EMPFANGEN IM KERNEL ***', 0
lbl_eax    db 'eax (Nummer) = 0x', 0
lbl_ebx    db 'ebx (arg1)   = 0x', 0
lbl_ecx    db 'ecx (arg2)   = 0x', 0
hexchars   db '0123456789ABCDEF'

user_eax dd 0
user_ebx dd 0
user_ecx dd 0

; ============================================================================
; Eingebettetes User-Programm
; ============================================================================
align 16
user_image:
    incbin "user.bin"
user_image_end:

; ============================================================================
; GDT + IDT + TSS  (GDT/TSS identisch zu 4a/4b; IDT mit 0x80 ist neu)
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
