; ============================================================================
; 2a kernel.asm  --  Tastatur-Interrupt empfangen
; ----------------------------------------------------------------------------
; Etappe 2 beginnt: der Weg zum Terminal-Emulator. Erster Schritt -- die
; Tastatur ueberhaupt "hoeren". Die Tastatur meldet jeden Tastendruck per IRQ1.
;
; Aufbau wie 1d (PIC umprogrammiert, IDT), aber statt des Timers (IRQ0)
; schalten wir die Tastatur (IRQ1, Vektor 0x21) frei. Der Handler liest den
; "Scancode" vom Tastatur-Port 0x60 -- eine Zahl, die NICHT der ASCII-Code ist,
; sondern die physische Tastenposition. Wir zeigen sie roh als Hex.
;
; Wichtig: Port 0x60 MUSS gelesen werden, sonst schickt der Tastatur-Controller
; keinen weiteren Interrupt. Pro Tastendruck kommen zwei Codes: "make" (runter)
; und "break" = make|0x80 (hoch). In 2a zeigen wir beide roh.
; ============================================================================

bits 32
org  0x10000

VGA equ 0xB8000

kernel_start:
    mov esp, 0x90000

    mov esi, msg_status
    mov edi, 0
    call print_string

    call pic_remap
    call idt_setup
    lidt [idt_descriptor]

    mov al, 0xFD                ; PIC-Master: nur IRQ1 (Tastatur) frei
    out 0x21, al               ;   0xFD = 11111101 -> Bit 1 = 0
    mov al, 0xFF
    out 0xA1, al

    sti
.idle:
    hlt
    jmp .idle

; ----------------------------------------------------------------------------
; Tastatur-Handler (IRQ1 / Vektor 0x21)
; ----------------------------------------------------------------------------
kbd_handler:
    pusha
    in al, 0x60                ; Scancode vom Tastatur-Port lesen
    movzx eax, al
    mov edi, 12*2              ; hinter "2a scancode="
    call print_hex
    mov al, 0x20               ; EOI an den Master-PIC
    out 0x20, al
    popa
    iret

; ----------------------------------------------------------------------------
; PIC umprogrammieren (identisch zu 1d)
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; IDT-Eintrag fuer Vektor 0x21 (Tastatur) -> kbd_handler
; ----------------------------------------------------------------------------
idt_setup:
    mov eax, kbd_handler
    mov word [idt + 0x21*8 + 0], ax
    mov word [idt + 0x21*8 + 2], 0x08
    mov byte [idt + 0x21*8 + 4], 0x00
    mov byte [idt + 0x21*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x21*8 + 6], ax
    ret

; ----------------------------------------------------------------------------
; print_string / print_hex (wie 1d)
; ----------------------------------------------------------------------------
print_string:
    push eax
.next:
    lodsb
    test al, al
    jz .done
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], 0x0F
    add edi, 2
    jmp .next
.done:
    pop eax
    ret

print_hex:
    push ebx
    push ecx
    mov ecx, 8
.digit:
    rol eax, 4
    mov ebx, eax
    and ebx, 0x0F
    mov bl, [hexchars + ebx]
    mov [VGA + edi], bl
    mov byte [VGA + edi + 1], 0x0A
    add edi, 2
    loop .digit
    pop ecx
    pop ebx
    ret

; ----------------------------------------------------------------------------
; Daten
; ----------------------------------------------------------------------------
msg_status db '2a scancode=', 0
hexchars   db '0123456789ABCDEF'

align 8
idt:
    times 256*8 db 0
idt_end:

idt_descriptor:
    dw idt_end - idt - 1
    dd idt
