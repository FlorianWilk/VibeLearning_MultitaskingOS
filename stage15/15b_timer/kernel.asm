; ============================================================================
; 15b kernel.asm  --  Timer-Interrupt in 64-bit (Long Mode)
; ----------------------------------------------------------------------------
; Das 64-bit-Gegenstueck zu 1d. Gleiche drei Bausteine (PIC-Remap, IDT, sti),
; aber mit den 64-bit-Unterschieden:
;   - IDT-Eintraege sind jetzt 16 Byte (statt 8): Offset wird auf 0..15, 16..31
;     UND 32..63 verteilt, plus 4 reservierte Bytes.
;   - kein pusha/popa mehr -> Register einzeln retten.
;   - Rueckkehr mit iretq (nicht iret).
; PIC-Programmierung (Port-I/O) ist identisch -- der 8259 kennt keine Bit-Breite.
;
; Beweis: Tick-Zaehler steigt. Ohne laufenden Timer bliebe er bei 00000000.
; ============================================================================

bits 64
org  0x10000

VGA equ 0xB8000
IDT equ 0x6000                  ; IDT zur Laufzeit hier aufbauen (256*16 = 4 KB)

kernel_start:
    mov rsp, 0x90000

    mov rsi, msg_status
    xor rdi, rdi
    call print_string

    ; ---- IDT-Speicher nullen (256 Eintraege * 16 Byte = 512 Qwords) ---------
    mov rdi, IDT
    xor rax, rax
    mov rcx, 512
    cld
    rep stosq

    call pic_remap
    call idt_setup
    lidt [idt_descriptor]

    mov al, 0xFE                ; nur IRQ0 (Timer) zulassen
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
    mov al, 0x20               ; Master-IRQs -> 0x20..0x27
    out 0x21, al
    mov al, 0x28               ; Slave-IRQs  -> 0x28..0x2F
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
; IDT-Eintrag fuer Vektor 0x20 (Timer). 64-bit-Gate (16 Byte):
;   [0..1] off0..15  [2..3] sel  [4] IST  [5] typ  [6..7] off16..31
;   [8..11] off32..63  [12..15] reserviert
; ----------------------------------------------------------------------------
idt_setup:
    mov rax, timer_handler
    mov rdi, IDT + 0x20*16
    mov [rdi + 0], ax          ; Offset 0..15
    mov word [rdi + 2], 0x08   ; Code-Selektor
    mov byte [rdi + 4], 0x00   ; IST = 0
    mov byte [rdi + 5], 0x8E   ; P=1, DPL=0, 64-bit Interrupt-Gate
    shr rax, 16
    mov [rdi + 6], ax          ; Offset 16..31
    shr rax, 16
    mov [rdi + 8], eax         ; Offset 32..63
    mov dword [rdi + 12], 0    ; reserviert
    ret

; ----------------------------------------------------------------------------
timer_handler:
    push rax
    push rbx
    push rcx
    push rdi
    inc dword [tick]
    mov eax, [tick]
    mov rdi, 16*2              ; hinter "...ticks="
    call print_hex
    mov al, 0x20              ; EOI an Master-PIC
    out 0x20, al
    pop rdi
    pop rcx
    pop rbx
    pop rax
    iretq

; ----------------------------------------------------------------------------
; print_string: rsi = 0-terminiert, rdi = VGA-Byte-Offset
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
; print_hex: eax = Wert, rdi = VGA-Byte-Offset, 8 Hex-Ziffern
; ----------------------------------------------------------------------------
print_hex:
    push rbx
    push rcx
    mov rcx, 8
.digit:
    rol eax, 4
    mov ebx, eax
    and ebx, 0x0F
    mov bl, [hexchars + rbx]
    mov [VGA + rdi], bl
    mov byte [VGA + rdi + 1], 0x0A
    add rdi, 2
    loop .digit
    pop rcx
    pop rbx
    ret

; ----------------------------------------------------------------------------
msg_status db '15b 64-bit tick=', 0
hexchars   db '0123456789ABCDEF'
tick       dd 0

idt_descriptor:
    dw 256*16 - 1
    dq IDT
