; ============================================================================
; 2b kernel.asm  --  Scancode -> ASCII
; ----------------------------------------------------------------------------
; In 2a sahen wir rohe Scancodes (Tastenpositionen). Jetzt uebersetzen wir sie
; in echte Zeichen ueber eine Tabelle (US-Layout, Scancode-Set 1) und zeigen
; das getippte Zeichen an.
;
; Zwei Dinge filtern wir weg:
;   - "break"-Codes (Taste losgelassen, Bit 7 gesetzt, >= 0x80)
;   - unbelegte/nicht druckbare Tasten (Tabellenwert 0, bzw. < 0x20)
; Enter/Backspace/Tab stehen schon in der Tabelle, behandeln wir aber erst 2c.
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

    ; ---- Tastatur-Puffer leeren: evtl. vom BIOS uebrige Bytes wegwerfen, ---
    ; sonst schickt der Controller keinen neuen Interrupt.
.flush:
    in al, 0x64                ; Status-Port des Tastatur-Controllers
    test al, 1                 ; Bit 0 = Output-Buffer voll?
    jz .flushed
    in al, 0x60                ; Byte lesen und verwerfen
    jmp .flush
.flushed:

    mov al, 0xFD               ; nur IRQ1 (Tastatur) frei
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    sti
.idle:
    hlt
    jmp .idle

; ----------------------------------------------------------------------------
; Tastatur-Handler (IRQ1): Scancode -> ASCII -> anzeigen
; ----------------------------------------------------------------------------
kbd_handler:
    pusha
    in al, 0x60
    test al, 0x80              ; break-Code (Taste losgelassen)?
    jnz .eoi                   ; ja -> ignorieren
    cmp al, 0x39               ; ausserhalb unserer Tabelle?
    ja .eoi
    movzx ebx, al
    mov al, [scancode_to_ascii + ebx]
    cmp al, 0x20               ; nur druckbare Zeichen (>= Space) in 2b
    jb .eoi
    mov edi, [cursor]
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], 0x0F
    add edi, 2
    mov [cursor], edi
.eoi:
    mov al, 0x20               ; EOI
    out 0x20, al
    popa
    iret

; ----------------------------------------------------------------------------
; PIC / IDT (Vektor 0x21 -> kbd_handler) / print_string  -- wie 2a
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

idt_setup:
    mov eax, kbd_handler
    mov word [idt + 0x21*8 + 0], ax
    mov word [idt + 0x21*8 + 2], 0x08
    mov byte [idt + 0x21*8 + 4], 0x00
    mov byte [idt + 0x21*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x21*8 + 6], ax
    ret

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

; ============================================================================
; Scancode -> ASCII (US-Layout, Set 1). Index = Scancode (0x00..0x39).
; 0 = unbelegt; 0x08 Backspace, 0x09 Tab, 0x0D Enter (erst 2c relevant).
; Sonderzeichen als Hex, um NASM-Quoting-Fallen zu vermeiden.
; ============================================================================
scancode_to_ascii:
    db 0, 0, '1','2','3','4','5','6','7','8','9','0','-','=', 0x08, 0x09
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 0x0D, 0, 'a','s'
    db 'd','f','g','h','j','k','l', 0x3B, 0x27, 0x60, 0, 0x5C, 'z','x','c','v'
    db 'b','n','m', 0x2C, '.', '/', 0, '*', 0, ' '

msg_status db '2b: tippe etwas (US-Layout):', 0
cursor     dd 80*2*2          ; Schreibposition, Start Zeile 2

align 8
idt:
    times 256*8 db 0
idt_end:

idt_descriptor:
    dw idt_end - idt - 1
    dd idt
