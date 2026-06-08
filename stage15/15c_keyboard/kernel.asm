; ============================================================================
; 15c kernel.asm  --  Tastatur-Interrupt in 64-bit (Long Mode)
; ----------------------------------------------------------------------------
; Das 64-bit-Gegenstueck zu 2a/2b: IRQ1 (Tastatur) statt IRQ0 (Timer).
; Der kbd_handler liest den Scancode aus Port 0x60, uebersetzt ihn ueber die
; US-Layout-Tabelle nach ASCII und schreibt das Zeichen an die Cursor-Position.
; Key-Release-Codes (Bit 7 gesetzt) werden ignoriert.
;
; Neu gegenueber 15b nur: anderer Vektor (0x21), anderer IRQ-Mask, der Handler.
; IDT-Format, lidt, iretq -- alles wie in 15b.
; ============================================================================

bits 64
org  0x10000

VGA equ 0xB8000
IDT equ 0x6000

kernel_start:
    mov rsp, 0x90000

    mov rsi, msg_status
    xor rdi, rdi
    call print_string

    mov rdi, IDT               ; IDT nullen (512 Qwords)
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq

    call pic_remap
    call idt_setup
    lidt [idt_descriptor]

    mov al, 0xFD               ; nur IRQ1 (Tastatur) zulassen
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    sti
.idle:
    hlt
    jmp .idle

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
; IDT-Eintrag Vektor 0x21 (Tastatur) -> kbd_handler. 64-bit-Gate (16 Byte).
; ----------------------------------------------------------------------------
idt_setup:
    mov rax, kbd_handler
    mov rdi, IDT + 0x21*16
    mov [rdi + 0], ax
    mov word [rdi + 2], 0x08
    mov byte [rdi + 4], 0x00
    mov byte [rdi + 5], 0x8E
    shr rax, 16
    mov [rdi + 6], ax
    shr rax, 16
    mov [rdi + 8], eax
    mov dword [rdi + 12], 0
    ret

; ----------------------------------------------------------------------------
kbd_handler:
    push rax
    push rbx
    push rdi
    in  al, 0x60
    test al, 0x80              ; Key-Release? -> ignorieren
    jnz .eoi
    movzx rbx, al
    cmp rbx, scancode_len
    jae .eoi
    mov al, [scancode_to_ascii + rbx]
    test al, al               ; nicht belegter Scancode?
    jz .eoi
    mov rdi, [cursor]
    mov [VGA + rdi], al
    mov byte [VGA + rdi + 1], 0x0F
    add rdi, 2
    mov [cursor], rdi
.eoi:
    mov al, 0x20
    out 0x20, al
    pop rdi
    pop rbx
    pop rax
    iretq

; ----------------------------------------------------------------------------
print_string:
    push rax
.next:
    lodsb
    test al, al
    jz .done
    mov [VGA + rdi], al
    mov byte [VGA + rdi + 1], 0x0F
    add rdi, 2
    jmp .next
.done:
    pop rax
    ret

; ----------------------------------------------------------------------------
msg_status db '15c 64-bit kbd: tippe etwas (US-Layout)', 0
cursor     dq 160                ; Zeile 1 (unter der Statuszeile)

scancode_to_ascii:
    db 0, 0, '1','2','3','4','5','6','7','8','9','0','-','=', 0x08, 0x09
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 0x0D, 0, 'a','s'
    db 'd','f','g','h','j','k','l', 0x3B, 0x27, 0x60, 0, 0x5C, 'z','x','c','v'
    db 'b','n','m', 0x2C, '.', '/', 0, '*', 0, ' '
scancode_len equ $ - scancode_to_ascii

idt_descriptor:
    dw 256*16 - 1
    dq IDT
