; ============================================================================
; 1b -- "VGA direkt beschreiben"
; ----------------------------------------------------------------------------
; In 1a lief die Ausgabe ueber das BIOS (int 0x10). Jetzt umgehen wir das BIOS
; und schreiben direkt in den VGA-Textspeicher. Der liegt fest bei physischer
; Adresse 0xB8000 und ist ein Array aus Zellen zu je 2 Byte:
;   Byte 0 = ASCII-Code,  Byte 1 = Attribut (Vorder-/Hintergrundfarbe).
; Schreiben wir dorthin, erscheint das Zeichen sofort -- ohne jede Software
; dazwischen. Genau diese direkte Hardware-Kontrolle wollte Linus.
;
; VERGLEICH zu 1a: kein "int 0x10" mehr, dafuer ein Speicher-Schreibzugriff.
; VERGLEICH zu 1c: hier noch Real Mode, Adressierung ueber Segment:Offset.
;   Wir brauchen das Segmentregister es=0xB800, um 0xB8000 zu erreichen
;   (0xB800 * 16 = 0xB8000). In 1c (Protected Mode, flach) faellt das weg.
; ============================================================================

bits 16
org  0x7C00

start:
    ; Im Real Mode adressieren wir Speicher als Segment:Offset.
    ; Physisch 0xB8000 = Segment 0xB800 (0xB800 * 16 = 0xB8000), Offset 0.
    mov ax, 0xB800
    mov es, ax          ; es zeigt jetzt auf den VGA-Textspeicher
    mov word [es:0], 0x0A41   ; Zelle 0: 0x41='A', 0x0A=hellgruen auf schwarz

hang:
    hlt
    jmp hang

times 510-($-$$) db 0
dw 0xAA55
