; ============================================================================
; 1a -- "Der Bootsektor lebt"
; ----------------------------------------------------------------------------
; Das BIOS laedt den allerersten Sektor (512 Byte) der Diskette nach der festen
; Adresse 0x7C00 und springt hinein. Mehr Starthilfe gibt es nicht -- ab hier
; sind wir die einzige Software auf der CPU.
;
; Die CPU laeuft hier im 16-bit "Real Mode" -- genau wie ein PC von 1991 nach
; dem Einschalten. Wir geben EIN Zeichen ueber das BIOS aus, um zu beweisen,
; dass unser Code wirklich ausgefuehrt wird.
;
; VERGLEICH zu 1b: Hier laeuft die Ausgabe noch ueber das BIOS (int 0x10).
; ============================================================================

bits 16                 ; Real Mode = 16-bit Code
org  0x7C00             ; das BIOS laedt uns hierhin -> Adressen passend rechnen

start:
    mov ah, 0x0E        ; BIOS-Funktion "Teletype": Zeichen ausgeben
    mov al, 'L'         ; das Zeichen, das wir sehen wollen
    int 0x10            ; BIOS-Video-Interrupt aufrufen

hang:
    hlt                 ; CPU anhalten bis zum naechsten Interrupt ...
    jmp hang            ; ... und falls doch einer kommt: wieder anhalten

; ----------------------------------------------------------------------------
; Boot-Signatur: Das BIOS bootet einen Sektor nur, wenn die letzten zwei Bytes
; 0x55 0xAA sind. Wir fuellen bis Byte 510 mit Nullen auf und setzen die Marke.
; ----------------------------------------------------------------------------
times 510-($-$$) db 0
dw 0xAA55
