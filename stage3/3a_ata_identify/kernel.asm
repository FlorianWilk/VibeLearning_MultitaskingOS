; ============================================================================
; 3a kernel.asm  --  ATA-Disk erkennen (IDENTIFY DEVICE)
; ----------------------------------------------------------------------------
; Erster Schritt von Etappe 3: ueberhaupt rausfinden, dass eine Festplatte
; angeschlossen ist und welche. Dazu schickt man dem IDE-Controller den Befehl
; "IDENTIFY DEVICE" (0xEC). Er antwortet mit 256 16-bit-Woertern Metadaten:
; Modell, Seriennummer, Sektorzahl, Features.
;
; ATA-PIO ist verblueffend simpel: alles laeuft ueber acht I/O-Ports.
;
;   0x1F0  Daten (16-bit)              ← hier kommen die Sektor-Bytes raus
;   0x1F1  Error / Features
;   0x1F2  Sektor-Anzahl               (bei IDENTIFY: 0)
;   0x1F3  LBA  0..7                   (bei IDENTIFY: 0)
;   0x1F4  LBA  8..15                  (bei IDENTIFY: 0)
;   0x1F5  LBA 16..23                  (bei IDENTIFY: 0)
;   0x1F6  Drive/Head  (0xA0 = Master, LBA-Mode)
;   0x1F7  Status (lesen) / Command (schreiben)
;
; Status-Bits (Port 0x1F7 beim Lesen):
;   Bit 7 BSY  Disk arbeitet, warten
;   Bit 3 DRQ  Datenwort bereit zum Abholen
;   Bit 0 ERR  Fehler
;
; Ablauf:
;   1. Warten bis BSY=0
;   2. Master-Drive selektieren (0xA0 -> 0x1F6)
;   3. Sektor-Anzahl + LBA = 0
;   4. IDENTIFY (0xEC -> 0x1F7)
;   5. Warten bis BSY=0 und DRQ=1
;   6. 256 Words aus 0x1F0 lesen
;
; Im Antwort-Block liegt der Modell-String in Words 27..46 (40 Zeichen). Jedes
; Word muss byte-vertauscht werden (ATA-Eigenheit aus den 80ern).
; ============================================================================

bits 32
org  0x10000

VGA    equ 0xB8000
WHITE  equ 0x0F
GREEN  equ 0x0A
COLS   equ 80
ROWB   equ COLS * 2

; ATA-Primary-Ports
ATA_DATA   equ 0x1F0
ATA_SCOUNT equ 0x1F2
ATA_LBA0   equ 0x1F3
ATA_LBA1   equ 0x1F4
ATA_LBA2   equ 0x1F5
ATA_DRIVE  equ 0x1F6
ATA_CMD    equ 0x1F7
ATA_STATUS equ 0x1F7

kernel_start:
    mov esp, 0x90000

    ; Statuszeile
    mov esi, msg_status
    mov edi, 0
    call print_string

    ; Disk identifizieren
    call ata_identify
    test eax, eax              ; eax = 0 -> keine Disk gefunden
    jz .no_disk

    ; Modell-String aus identify_buf (Words 27..46) nach VGA Zeile 2 kopieren,
    ; dabei jedes Word byte-vertauschen.
    mov esi, identify_buf + 27*2
    mov edi, VGA + ROWB*2
    mov ecx, 40 / 2            ; 20 Words = 40 Zeichen
.copy:
    mov al, [esi + 1]          ; high byte zuerst (byte-swap)
    mov [edi], al
    mov byte [edi + 1], GREEN
    mov al, [esi]
    mov [edi + 2], al
    mov byte [edi + 3], GREEN
    add esi, 2
    add edi, 4
    loop .copy

.hang:
    hlt
    jmp .hang

.no_disk:
    mov esi, msg_no_disk
    mov edi, ROWB*2
    call print_string
    jmp .hang

; ============================================================================
; ata_identify
;   Liest IDENTIFY-DEVICE-Daten in identify_buf (512 Byte = 256 Words).
;   Rueckgabe: eax = 1 OK, eax = 0 keine Disk.
; ============================================================================
ata_identify:
    ; 1) warten bis BSY=0
    mov dx, ATA_STATUS
.wait_bsy:
    in al, dx
    test al, 0x80
    jnz .wait_bsy

    ; 2) Master selektieren (LBA-Modus, ohne LBA-Anteile -> 0xA0)
    mov dx, ATA_DRIVE
    mov al, 0xA0
    out dx, al

    ; 3) Sektor-Anzahl und LBA = 0
    xor al, al
    mov dx, ATA_SCOUNT
    out dx, al
    mov dx, ATA_LBA0
    out dx, al
    mov dx, ATA_LBA1
    out dx, al
    mov dx, ATA_LBA2
    out dx, al

    ; 4) Befehl IDENTIFY senden
    mov dx, ATA_CMD
    mov al, 0xEC
    out dx, al

    ; 5) Status pruefen: 0 -> keine Disk
    in al, dx
    test al, al
    jz .none

.wait_drq:
    in al, dx
    test al, 0x80              ; BSY?
    jnz .wait_drq
    test al, 1                 ; ERR?
    jnz .none
    test al, 8                 ; DRQ?
    jz .wait_drq

    ; 6) 256 Words aus Datenport lesen -> identify_buf
    mov dx, ATA_DATA
    mov edi, identify_buf
    mov ecx, 256
    cld
    rep insw                   ; in word from dx into [edi], edi+=2, ecx--

    mov eax, 1
    ret
.none:
    xor eax, eax
    ret

; ============================================================================
; print_string: esi = 0-terminiert, edi = VGA-Offset
; ============================================================================
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
msg_status  db '3a ATA IDENTIFY -- Disk-Modell:', 0
msg_no_disk db '(keine Disk gefunden -- vergiss -hda nicht)', 0

align 4
identify_buf:
    times 512 db 0
