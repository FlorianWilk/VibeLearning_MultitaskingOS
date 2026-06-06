; ============================================================================
; 1c -- "Wechsel in den Protected Mode"
; ----------------------------------------------------------------------------
; Bis 1b lief alles im 16-bit Real Mode. Das 386-Hardware-Task-Switching (unser
; Ziel) existiert dort aber gar nicht -- es ist eine reine Protected-Mode-
; Funktion. Also schalten wir die CPU um.
;
; Der Umschaltvorgang in vier Schritten:
;   1. A20-Gate oeffnen (Adressleitung 20 freischalten)
;   2. GDT laden        (Tabelle, die unsere Speichersegmente beschreibt)
;   3. PE-Bit in CR0    (der eigentliche Schalter Real -> Protected)
;   4. Far Jump         (laedt CS mit dem Code-Selektor, leert die Pipeline)
; ============================================================================

bits 16
org  0x7C00

start:
    cli                     ; Interrupts AUS: ohne IDT wuerde jeder Interrupt
                            ; im Protected Mode sofort eine Triple-Fault ausloesen

    ; ---- 1. A20-Gate aktivieren (schnelle Methode ueber Port 0x92) ----------
    ; Aus 8086-Kompatibilitaet ist Adressleitung A20 anfangs deaktiviert.
    ; Ohne sie koennten wir nicht ueber 1 MB hinaus adressieren.
    in  al, 0x92
    or  al, 2
    out 0x92, al

    ; ---- 2. GDT laden -------------------------------------------------------
    lgdt [gdt_descriptor]

    ; ---- 3. Protected Mode einschalten: PE-Bit (Bit 0) in CR0 ---------------
    mov eax, cr0
    or  eax, 1
    mov cr0, eax

    ; ---- 4. Far Jump in 32-bit-Code -----------------------------------------
    ; Laedt CS mit dem Code-Selektor 0x08 und verwirft die vorab geladenen
    ; 16-bit-Befehle in der Pipeline. Ab hier rechnet die CPU in 32 bit.
    jmp 0x08:protected_start

; ----------------------------------------------------------------------------
bits 32
protected_start:
    ; Alle Datensegmente auf den Daten-Selektor 0x10 setzen. Beide Segmente
    ; haben Basis 0 und Limit 4 GB -> wir adressieren den Speicher "flach".
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000        ; Stack in freien RAM legen

    ; ====================================================================
    ; DER ENTSCHEIDENDE UNTERSCHIED ZU 1b
    ; --------------------------------------------------------------------
    ; 1b (Real Mode):     mov ax, 0xB800
    ;                     mov es, ax
    ;                     mov word [es:0], 0x0A41
    ;   -> Adressierung als Segment:Offset. Um 0xB8000 zu treffen, musste
    ;      das Segmentregister es auf 0xB800 gesetzt werden (0xB800*16).
    ;
    ; 1c (Protected Mode, flach): einfach die volle lineare Adresse
    ;      hinschreiben. ds hat Basis 0 und Limit 4 GB, also ist [0xB8000]
    ;      direkt 0xB8000 -- kein Segment-Register, kein *16-Trick noetig.
    ;      Genau diese flache Adressierung macht spaeter auch Linux.
    ; ====================================================================
    mov word [0xB8000], 0x4F50   ; 'P' (0x50), weiss auf rot (0x4F)

.hang:
    hlt
    jmp .hang

; ============================================================================
; GDT -- Global Descriptor Table
; Drei 8-Byte-Eintraege. Jeder beschreibt ein Speichersegment: Basis, Limit
; und Zugriffsrechte. Der "Selektor" ist der Byte-Offset in diese Tabelle.
; ============================================================================
gdt_start:
    dq 0                    ; Null-Deskriptor (Pflicht, Selektor 0x00)

gdt_code:                   ; Selektor 0x08  -- Code, ring 0, exec/read
    dw 0xFFFF               ; Limit  0..15
    dw 0x0000               ; Basis  0..15
    db 0x00                 ; Basis 16..23
    db 10011010b            ; present, ring0, code-segment, ausfuehrbar, lesbar
    db 11001111b            ; granularitaet 4K, 32-bit; Limit 16..19 = 0xF
    db 0x00                 ; Basis 24..31

gdt_data:                   ; Selektor 0x10  -- Daten, ring 0, read/write
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b            ; present, ring0, daten-segment, schreibbar
    db 11001111b
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1   ; Limit = Tabellengroesse - 1
    dd gdt_start                 ; lineare Basisadresse der Tabelle

times 510-($-$$) db 0
dw 0xAA55
