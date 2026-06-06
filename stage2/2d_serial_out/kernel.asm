; ============================================================================
; 2d kernel.asm  --  Zweite Hardware: serieller Output (COM1)
; ----------------------------------------------------------------------------
; AENDERUNG zu 2c: ein zweiter "Treiber" -- serial_putc -- haengt am UART
; 16550 (Port 0x3F8 = COM1). kbd_handler ruft jetzt BEIDE Senken auf:
;   screen_putc   schreibt auf VGA (lokales Echo)
;   serial_putc   schickt das Byte ueber den seriellen Port raus
;
; Genau diese Konstellation ist Linus' Terminal-Emulator (Tasten -> Modem +
; lokales Echo). Schoen daran: die Tastatur ruft zwei Treiber blind auf -- ein
; weiterer Treiber waere wieder nur ein call. Das ist das Treiber-Prinzip.
;
; Test: qemu mit "-serial stdio" -- in QEMU tippen erscheint im Host-Terminal.
; ============================================================================

bits 32
org  0x10000

VGA    equ 0xB8000
WHITE  equ 0x0F
COLS   equ 80
ROWS   equ 25
ROWB   equ COLS * 2        ; Bytes pro Zeile
SCREEN equ ROWB * ROWS

; UART 16550 (COM1) Ports
COM1     equ 0x3F8
LSR      equ COM1 + 5      ; Line Status Register (Bit 5 = TX bereit)

kernel_start:
    mov esp, 0x90000

    mov esi, msg_status
    mov edi, 0
    call print_string

    call pic_remap
    call idt_setup
    call serial_init           ; UART konfigurieren (8N1, 38400 Baud)
    lidt [idt_descriptor]

.flush:                    ; Tastatur-Puffer leeren (siehe 2b)
    in al, 0x64
    test al, 1
    jz .flushed
    in al, 0x60
    jmp .flush
.flushed:

    mov al, 0xFD           ; nur IRQ1 (Tastatur) frei
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    sti
.idle:
    hlt
    jmp .idle

; ============================================================================
; Tastatur-Treiber: Scancode lesen, uebersetzen, an Bildschirm-Treiber geben
; ============================================================================
kbd_handler:
    pusha
    in al, 0x60
    test al, 0x80              ; break-Code? -> ignorieren
    jnz .eoi
    cmp al, 0x39
    ja .eoi
    movzx ebx, al
    mov al, [scancode_to_ascii + ebx]
    test al, al                ; unbelegt in der Tabelle?
    jz .eoi
    call screen_putc           ; lokales Echo auf den Bildschirm
    call serial_putc           ; gleiches Byte ueber COM1 nach draussen
.eoi:
    mov al, 0x20
    out 0x20, al
    popa
    iret

; ============================================================================
; Bildschirm-Treiber
; ============================================================================
; screen_putc: al = ASCII-Zeichen. Interpretiert Enter/BS, schreibt, scrollt.
; ----------------------------------------------------------------------------
screen_putc:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    cmp al, 0x0D               ; Enter?
    je .enter
    cmp al, 0x08               ; Backspace?
    je .bksp
    cmp al, 0x20               ; nicht druckbar -> ignorieren
    jb .done

    ; ---- normales Zeichen schreiben + Cursor vor ----
    mov edi, [cursor]
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], WHITE
    add edi, 2
    jmp .check_wrap

.enter:
    ; Cursor auf Anfang der naechsten Zeile: cursor -= (cursor mod ROWB); += ROWB
    mov eax, [cursor]
    xor edx, edx
    mov ecx, ROWB
    div ecx                   ; edx = cursor mod ROWB
    mov edi, [cursor]
    sub edi, edx              ; Zeilenanfang
    add edi, ROWB             ; naechste Zeile
    jmp .check_wrap

.bksp:
    mov edi, [cursor]
    cmp edi, ROWB             ; nicht in/ueber die Statuszeile loeschen
    jbe .done
    sub edi, 2
    mov byte [VGA + edi], ' '
    mov byte [VGA + edi + 1], WHITE
    mov [cursor], edi
    jmp .done

.check_wrap:
    cmp edi, SCREEN           ; ueber das Schirmende hinaus?
    jb .store
    call scroll_up
    mov edi, ROWB * (ROWS - 1) ; Cursor auf Anfang der letzten Zeile
.store:
    mov [cursor], edi
.done:
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ----------------------------------------------------------------------------
; scroll_up: Inhalt der Zeilen 2..24 eine Zeile nach oben kopieren,
;            letzte Zeile leeren. Zeile 0 (Statuszeile) bleibt stehen.
; ----------------------------------------------------------------------------
scroll_up:
    push eax
    push ecx
    push esi
    push edi
    cld
    mov esi, VGA + ROWB * 2      ; Quelle: Zeile 2
    mov edi, VGA + ROWB * 1      ; Ziel:   Zeile 1
    mov ecx, (ROWB * (ROWS - 2)) / 4
    rep movsd                    ; 23 Zeilen hochschieben
    mov edi, VGA + ROWB * (ROWS - 1)  ; letzte Zeile leeren
    mov ecx, ROWB / 4
    xor eax, eax
    rep stosd
    pop edi
    pop esi
    pop ecx
    pop eax
    ret

; ============================================================================
; Serieller Treiber (UART 16550, COM1)
; ----------------------------------------------------------------------------
; serial_init: 8 Datenbits, 1 Stopbit, keine Paritaet, 38400 Baud, IRQs aus.
; Die Baudrate wird im "DLAB"-Modus per Divisor gesetzt (Divisor 3 = 38400).
; ----------------------------------------------------------------------------
serial_init:
    mov dx, COM1 + 1
    mov al, 0x00              ; alle UART-Interrupts aus (kommt erst in 2e)
    out dx, al
    mov dx, COM1 + 3
    mov al, 0x80              ; DLAB=1: naechste 2 Ports = Baudraten-Divisor
    out dx, al
    mov dx, COM1 + 0
    mov al, 3                 ; Divisor low  = 3  -> 115200/3 = 38400 Baud
    out dx, al
    mov dx, COM1 + 1
    mov al, 0
    out dx, al                ; Divisor high = 0
    mov dx, COM1 + 3
    mov al, 0x03              ; DLAB=0, 8N1
    out dx, al
    mov dx, COM1 + 2
    mov al, 0xC7              ; FIFO an, 14-Byte-Trigger
    out dx, al
    mov dx, COM1 + 4
    mov al, 0x0B              ; DTR, RTS, OUT2 (OUT2 = IRQs Richtung CPU)
    out dx, al
    ret

; ----------------------------------------------------------------------------
; serial_putc: al = Byte. Wartet bis TX bereit ist, schickt Byte raus.
; Das ist alles -- ein Treiber kann kleiner kaum sein.
; ----------------------------------------------------------------------------
serial_putc:
    push eax
    push edx
    mov ah, al                ; Byte merken
.wait:
    mov dx, LSR
    in al, dx
    test al, 0x20             ; Bit 5 = TX-Holding leer?
    jz .wait
    mov dx, COM1
    mov al, ah
    out dx, al
    pop edx
    pop eax
    ret

; ----------------------------------------------------------------------------
; PIC / IDT (Vektor 0x21) / print_string  -- identisch zu 2c
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
    mov byte [VGA + edi + 1], WHITE
    add edi, 2
    jmp .next
.done:
    pop eax
    ret

; ============================================================================
; Daten / Scancode-Tabelle (wie 2b)
; ============================================================================
scancode_to_ascii:
    db 0, 0, '1','2','3','4','5','6','7','8','9','0','-','=', 0x08, 0x09
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 0x0D, 0, 'a','s'
    db 'd','f','g','h','j','k','l', 0x3B, 0x27, 0x60, 0, 0x5C, 'z','x','c','v'
    db 'b','n','m', 0x2C, '.', '/', 0, '*', 0, ' '

msg_status db '2d terminal + serial out -- siehe Host-Term (-serial stdio)', 0
cursor     dd ROWB              ; Start: Zeile 1 (Zeile 0 = Statuszeile)

align 8
idt:
    times 256*8 db 0
idt_end:

idt_descriptor:
    dw idt_end - idt - 1
    dd idt
