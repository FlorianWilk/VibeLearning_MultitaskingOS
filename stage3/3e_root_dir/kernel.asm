; ============================================================================
; 3e kernel.asm  --  Root-Verzeichnis listen (Inode 1 -> Datenblock -> Eintraege)
; ----------------------------------------------------------------------------
; AENDERUNG zu 3d: wir folgen jetzt der Kette
;     Superblock  ->  Inode-Tabelle  ->  Inode 1 (Root)  ->  Datenblock  ->  Liste
;
; Inode-Struktur (32 Byte, Minix v1):
;     0  i_mode    (2)
;     2  i_uid     (2)
;     4  i_size    (4)
;     8  i_time    (4)
;    12  i_gid     (1)
;    13  i_nlinks  (1)
;    14  i_zone[0..8] (je 2 Byte)   -- 7 direkt, 1 indirekt, 1 doppelt-indirekt
;
; Inode N liegt in der Inode-Tabelle bei Offset (N-1) * 32.
;
; Dir-Eintrag (16 Byte fuer v1 mit 14-Zeichen-Namen):
;     0  inode  (2)
;     2  name   (14, null-gepolstert)
;   inode == 0 -> Eintrag leer (ueberspringen).
;
; Wir lesen den ersten 512-Byte-Sektor des Root-Daten-Blocks und iterieren
; bis zu 32 Eintraege (= ein Sektor). Fuer unser Mini-FS mit . / .. / hello.txt
; reicht das locker.
; ============================================================================

bits 32
org  0x10000

VGA    equ 0xB8000
WHITE  equ 0x0F
GREEN  equ 0x0A
COLS   equ 80
ROWB   equ COLS * 2

ATA_DATA   equ 0x1F0
ATA_SCOUNT equ 0x1F2
ATA_LBA0   equ 0x1F3
ATA_LBA1   equ 0x1F4
ATA_LBA2   equ 0x1F5
ATA_DRIVE  equ 0x1F6
ATA_CMD    equ 0x1F7
ATA_STATUS equ 0x1F7

ATA_CMD_READ equ 0x20

kernel_start:
    mov esp, 0x90000

    mov esi, msg_status
    mov edi, 0
    call print_string

    ; ---- 1. Superblock lesen (Minix-Block 1 = Sektor 2) -------------------
    mov eax, 2
    mov edi, sector_buf
    call read_sector

    ; ---- 2. Inode-Tabelle finden: 2 + imap_blocks + zmap_blocks (Minix) ---
    movzx eax, word [sector_buf + 4]    ; imap_blocks
    movzx ebx, word [sector_buf + 6]    ; zmap_blocks
    add eax, 2
    add eax, ebx
    shl eax, 1                          ; Minix-Block -> ATA-Sektor (* 2)
    mov edi, sector_buf
    call read_sector

    ; ---- 3. Inode 1 (Root) = Offset 0; i_zone[0] = Offset 14 --------------
    movzx eax, word [sector_buf + 14]  ; Root-Daten-Block (Minix-Block-Nr)
    shl eax, 1                          ; -> Sektor
    mov edi, sector_buf
    call read_sector

    ; ---- 4. Eintraege iterieren: 32 Slots zu je 16 Byte (= 512 Byte) -----
    mov esi, sector_buf
    mov ebx, ROWB * 2                   ; Display: Zeile 2
    mov edx, 32                         ; max 32 Slots im Sektor
.entry:
    movzx eax, word [esi]              ; inode-nr
    test eax, eax
    jz .skip                            ; leerer Slot -> ueberspringen

    push esi
    add esi, 2                          ; Name beginnt nach dem inode-Feld
    mov edi, ebx
    mov ecx, 14                         ; max 14 Zeichen
    call print_name
    pop esi

    add ebx, ROWB                       ; naechste Zeile
.skip:
    add esi, 16
    dec edx
    jnz .entry

.hang:
    hlt
    jmp .hang

; ============================================================================
; print_name: esi = Name (bis zu ecx Zeichen, null-terminiert moeglich)
;             edi = VGA-Offset
; ============================================================================
print_name:
    push eax
.next:
    lodsb
    test al, al
    jz .done
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], WHITE
    add edi, 2
    loop .next
.done:
    pop eax
    ret

; ============================================================================
; read_sector  --  identisch zu 3b
; ============================================================================
read_sector:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    mov ebx, eax
    mov dx, ATA_STATUS
.wait_bsy:
    in al, dx
    test al, 0x80
    jnz .wait_bsy
    mov eax, ebx
    shr eax, 24
    and al, 0x0F
    or  al, 0xE0
    mov dx, ATA_DRIVE
    out dx, al
    mov al, 1
    mov dx, ATA_SCOUNT
    out dx, al
    mov al, bl
    mov dx, ATA_LBA0
    out dx, al
    mov eax, ebx
    shr eax, 8
    mov dx, ATA_LBA1
    out dx, al
    mov eax, ebx
    shr eax, 16
    mov dx, ATA_LBA2
    out dx, al
    mov al, ATA_CMD_READ
    mov dx, ATA_CMD
    out dx, al
.wait_drq:
    mov dx, ATA_STATUS
    in al, dx
    test al, 0x80
    jnz .wait_drq
    test al, 8
    jz .wait_drq
    mov dx, ATA_DATA
    mov ecx, 256
    cld
    rep insw
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
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

msg_status db '3e Root-Verzeichnis (Inode 1 -> Datenblock -> Eintraege):', 0

align 4
sector_buf:
    times 512 db 0
