; ============================================================================
; 6a kernel.asm  --  Timer-IRQ unterbricht Ring-3-Code sauber
; ----------------------------------------------------------------------------
; In Etappe 5 haben wir Hardware-IRQs einfach maskiert, weil ein verwaister
; Timer-IRQ nach dem Sprung nach Ring 3 einen Triple-Fault ausloeste. Jetzt
; machen wir es RICHTIG: wir behandeln den Timer-IRQ.
;
; Der kritische Mechanismus: Wenn ein IRQ waehrend Ring-3-Code feuert, wechselt
; die CPU nach Ring 0 und holt den Kernel-Stack-Pointer aus TSS.ESP0. Ohne
; korrektes ESP0 -> Crash. Genau dafuer haben wir das TSS.
;
; Wir benutzen ein INTERRUPT GATE (0x8E) fuer den Timer: damit ist IF=0
; waehrend des Handlers -> keine Verschachtelung (non-preemptive kernel).
;
; Beweis: oben laeuft der Tick-Zaehler (Kernel), in der Mitte dreht der
; User-Spinner (Ring 3). Beide bewegen sich => der Timer unterbricht den User
; und der iret bringt die CPU sauber zurueck nach Ring 3.
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

    ; ---- GDT/TSS einrichten (wie 4d) -----------------------------------
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
    ; ESP0 = Kernel-Stack: hierhin wechselt die CPU bei IRQ aus Ring 3
    mov dword [tss_main + 4], KERNEL_STACK
    mov dword [tss_main + 8], 0x10
    mov ax, 0x28
    ltr ax

    ; ---- PIC umprogrammieren, nur Timer (IRQ0) zulassen ----------------
    call pic_remap
    mov al, 0xFE                ; nur IRQ0 frei
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    ; ---- IDT: Timer-Vektor 0x20 ----------------------------------------
    call idt_setup
    lidt [idt_descriptor]

    mov esi, msg_status
    mov edi, 0
    call print_string

    ; ---- User laden + Sprung nach Ring 3 -------------------------------
    mov esi, user_image
    mov edi, USER_ENTRY
    mov ecx, user_image_end - user_image
    cld
    rep movsb

    push dword 0x23
    push dword USER_STACK
    push dword 0x202           ; IF=1 -> Timer darf feuern
    push dword 0x1B
    push dword USER_ENTRY
    iret

; ============================================================================
; Timer-Handler (IRQ0 / Vektor 0x20)
;   Wird aus Ring 3 aufgerufen: die CPU hat schon auf den Kernel-Stack (ESP0)
;   gewechselt und SS/ESP/EFLAGS/CS/EIP des Users gepusht. Wir zaehlen, zeigen,
;   EOI, iret -- die CPU wechselt zurueck nach Ring 3.
; ============================================================================
timer_handler:
    pusha
    inc dword [tick]
    mov eax, [tick]
    mov edi, 14 * 2            ; hinter "6a ticks="
    call print_hex
    mov al, 0x20               ; EOI
    out 0x20, al
    popa
    iret

; ============================================================================
; pic_remap (wie 1d): IRQs -> 0x20..0x2F
; ============================================================================
pic_remap:
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    ret

; ============================================================================
; idt_setup: Vektor 0x20 -> timer_handler, Interrupt Gate (0x8E, DPL=0)
; ============================================================================
idt_setup:
    mov eax, timer_handler
    mov word [idt + 0x20*8 + 0], ax
    mov word [idt + 0x20*8 + 2], 0x08
    mov byte [idt + 0x20*8 + 4], 0x00
    mov byte [idt + 0x20*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x20*8 + 6], ax
    ret

; ============================================================================
; print_hex (eax, edi) / print_string (esi, edi)
; ============================================================================
print_hex:
    push ebx
    push ecx
    mov ecx, 8
.d:
    rol eax, 4
    mov ebx, eax
    and ebx, 0x0F
    mov bl, [hexchars + ebx]
    mov [VGA + edi], bl
    mov byte [VGA + edi + 1], GREEN
    add edi, 2
    loop .d
    pop ecx
    pop ebx
    ret

print_string:
    push eax
.next:
    lodsb
    test al, al
    jz .done
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], WHITE
    add edi, 2
    jmp .next
.done:
    pop eax
    ret

; ============================================================================
; Daten
; ============================================================================
msg_status db '6a ticks=', 0
hexchars   db '0123456789ABCDEF'
tick       dd 0

align 16
user_image:
    incbin "user.bin"
user_image_end:

; ============================================================================
; GDT + IDT + TSS (wie 4d)
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
