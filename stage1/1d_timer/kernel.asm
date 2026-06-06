; ============================================================================
; 1d kernel.asm  --  Der Timer-Interrupt
; ----------------------------------------------------------------------------
; boot.asm hat uns hierher (phys. 0x10000) im 32-bit Protected Mode gebracht.
; Jetzt richten wir den Timer-Interrupt ein -- den Motor, der spaeter (1e) das
; Task-Switching antreibt. Drei Bausteine:
;
;   1. PIC umprogrammieren  Der Interrupt-Controller (8259) liefert IRQ0 (Timer)
;                           per Default auf Vektor 8 -- der kollidiert im
;                           Protected Mode mit der CPU-Exception "Double Fault".
;                           Wir verschieben die IRQs auf Vektoren 0x20..0x2F.
;   2. IDT aufbauen         Interrupt Descriptor Table: sagt der CPU, welche
;                           Routine bei welchem Vektor laufen soll. Wir fuellen
;                           nur Vektor 0x20 (Timer) -> timer_handler.
;   3. sti                  Interrupts scharfschalten. Ab jetzt feuert der PIT
;                           ~18,2-mal pro Sekunde und ruft timer_handler auf.
;
; Beweis, dass es laeuft: Der Handler zaehlt einen Tick-Zaehler hoch und zeigt
; ihn als Hex-Zahl an. Im Screenshot nach 2 s steht dort eine Zahl > 0 -- ohne
; laufenden Timer bliebe sie bei 00000000.
; ============================================================================

bits 32
org  0x10000

VGA equ 0xB8000

kernel_start:
    mov esp, 0x90000               ; Stack (boot.asm hat ihn schon gesetzt)

    mov esi, msg_status            ; Statuszeile oben links ausgeben
    mov edi, 0
    call print_string

    call pic_remap                 ; IRQs auf 0x20..0x2F verschieben
    call idt_setup                 ; Timer-Vektor 0x20 eintragen
    lidt [idt_descriptor]          ; IDT bei der CPU registrieren

    mov al, 0xFE                   ; PIC-Master: nur IRQ0 (Timer) zulassen,
    out 0x21, al                   ;   Bit 0 = 0 (frei), Rest maskiert
    mov al, 0xFF                   ; PIC-Slave: alles maskiert
    out 0xA1, al

    sti                            ; Interrupts an -> Timer feuert ab jetzt

.idle:
    hlt                            ; bis zum naechsten Interrupt schlafen
    jmp .idle

; ----------------------------------------------------------------------------
; PIC (8259) umprogrammieren -- Master (0x20/0x21) und Slave (0xA0/0xA1)
; ----------------------------------------------------------------------------
pic_remap:
    mov al, 0x11                   ; ICW1: Initialisierung, ICW4 folgt
    out 0x20, al
    out 0xA0, al
    mov al, 0x20                   ; ICW2 Master: IRQ0..7 -> Vektoren 0x20..0x27
    out 0x21, al
    mov al, 0x28                   ; ICW2 Slave:  IRQ8..15 -> Vektoren 0x28..0x2F
    out 0xA1, al
    mov al, 0x04                   ; ICW3 Master: Slave haengt an IRQ2
    out 0x21, al
    mov al, 0x02                   ; ICW3 Slave:  Kaskaden-Identitaet 2
    out 0xA1, al
    mov al, 0x01                   ; ICW4: 8086/88-Modus
    out 0x21, al
    out 0xA1, al
    ret

; ----------------------------------------------------------------------------
; IDT-Eintrag fuer Vektor 0x20 (Timer) auf timer_handler setzen.
; Ein Interrupt-Gate-Deskriptor (8 Byte):
;   [0..1] Offset 0..15   [2..3] Selektor   [4] 0   [5] Typ   [6..7] Offset 16..31
; ----------------------------------------------------------------------------
idt_setup:
    mov eax, timer_handler
    mov word [idt + 0x20*8 + 0], ax    ; Offset low
    mov word [idt + 0x20*8 + 2], 0x08  ; Code-Selektor (unser 32-bit Code)
    mov byte [idt + 0x20*8 + 4], 0x00  ; reserviert
    mov byte [idt + 0x20*8 + 5], 0x8E  ; P=1, DPL=0, 32-bit Interrupt-Gate
    shr eax, 16
    mov word [idt + 0x20*8 + 6], ax    ; Offset high
    ret

; ----------------------------------------------------------------------------
; Timer-Handler: laeuft bei jedem Tick. Zaehler hoch, anzeigen, EOI, iret.
; ----------------------------------------------------------------------------
timer_handler:
    pusha
    inc dword [tick]
    mov eax, [tick]
    mov edi, 16*2                  ; Position hinter "ticks=" (16 Zeichen)
    call print_hex
    mov al, 0x20                   ; EOI (End Of Interrupt) an den Master-PIC,
    out 0x20, al                   ;   sonst feuert der Timer nie wieder
    popa
    iret                           ; aus dem Interrupt zurueckkehren

; ----------------------------------------------------------------------------
; print_string: esi = 0-terminierter String, edi = VGA-Byte-Offset
; ----------------------------------------------------------------------------
print_string:
    push eax
.next:
    lodsb                          ; al = [esi], esi++
    test al, al
    jz .done
    mov [VGA + edi], al            ; ASCII
    mov byte [VGA + edi + 1], 0x0F ; Attribut weiss
    add edi, 2
    jmp .next
.done:
    pop eax
    ret

; ----------------------------------------------------------------------------
; print_hex: eax = Wert, edi = VGA-Byte-Offset. Gibt 8 Hex-Ziffern aus.
; ----------------------------------------------------------------------------
print_hex:
    push ebx
    push ecx
    mov ecx, 8
.digit:
    rol eax, 4                     ; oberste 4 Bit nach unten holen
    mov ebx, eax
    and ebx, 0x0F
    mov bl, [hexchars + ebx]
    mov [VGA + edi], bl            ; Hex-Ziffer
    mov byte [VGA + edi + 1], 0x0A ; Attribut hellgruen
    add edi, 2
    loop .digit
    pop ecx
    pop ebx
    ret

; ----------------------------------------------------------------------------
; Daten
; ----------------------------------------------------------------------------
msg_status db '1d timer  ticks=', 0
hexchars   db '0123456789ABCDEF'
tick       dd 0

; ----------------------------------------------------------------------------
; IDT: 256 Eintraege a 8 Byte (nur Vektor 0x20 wird gefuellt, Rest bleibt 0)
; ----------------------------------------------------------------------------
align 8
idt:
    times 256*8 db 0
idt_end:

idt_descriptor:
    dw idt_end - idt - 1           ; Limit = Tabellengroesse - 1
    dd idt                         ; lineare Basisadresse
