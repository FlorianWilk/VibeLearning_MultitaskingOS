; ============================================================================
; 3d kernel.asm  --  Superblock parsen
; ----------------------------------------------------------------------------
; AENDERUNG zu 3c: statt eines rohen Hex-Dumps zeigen wir jetzt die WERTE der
; Superblock-Felder mit Beschriftung. Damit verstehen wir die Geometrie des
; Dateisystems -- das ist die Voraussetzung fuer Inode-Zugriff in 3e/3f.
;
; Superblock-Layout (Minix v1, ab Offset 0):
;     0  n_inodes              Anzahl Inodes insgesamt
;     2  n_zones               Anzahl Bloecke (= Zonen, weil log_zone_size=0)
;     4  imap_blocks           Anzahl Bloecke fuer die Inode-Bitmap
;     6  zmap_blocks           Anzahl Bloecke fuer die Zone-Bitmap
;     8  first_data_zone       erster Daten-Block (absolute Block-Nr)
;    10  log_zone_size         0 => 1 Zone = 1024 Byte
;    12  max_size              max. Dateigroesse (uns hier egal)
;    16  magic                 0x137F = Minix v1, 14-Zeichen-Namen
;
; Hilfsberechnung:
;     inode_table_block = 2 + imap_blocks + zmap_blocks   (Block-Nr in Minix)
; Bei uns: 2 + 1 + 1 = 4. In 3e/3f brauchen wir diese Zahl, um Inode 1 zu finden.
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

    ; Superblock einlesen (Minix-Block 1 -> Sektor 2)
    mov eax, 2
    mov edi, sector_buf
    call read_sector

    ; n_inodes
    mov esi, lbl_ninodes
    mov edi, ROWB * 2
    call print_string
    mov ax, [sector_buf + 0]
    call print_hex_word

    ; n_zones
    mov esi, lbl_nzones
    mov edi, ROWB * 3
    call print_string
    mov ax, [sector_buf + 2]
    call print_hex_word

    ; first_data_zone
    mov esi, lbl_firstdata
    mov edi, ROWB * 4
    call print_string
    mov ax, [sector_buf + 8]
    call print_hex_word

    ; magic
    mov esi, lbl_magic
    mov edi, ROWB * 5
    call print_string
    mov ax, [sector_buf + 16]
    call print_hex_word

    ; berechneter inode_table_block = 2 + imap + zmap
    movzx eax, word [sector_buf + 4]
    movzx ebx, word [sector_buf + 6]
    add eax, 2
    add eax, ebx
    push eax                  ; merken, gleich anzeigen

    mov esi, lbl_inodetab
    mov edi, ROWB * 6
    call print_string
    pop eax
    call print_hex_word

.hang:
    hlt
    jmp .hang

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

; ============================================================================
; print_hex_word: ax = 16-bit-Wert, edi = VGA-Offset; edi += 8.
;   Schreibt "XXXX" als Hex (big-endian fuer Lesbarkeit).
; ============================================================================
print_hex_word:
    push eax
    push edx
    mov dl, al                ; low byte sichern
    shr ax, 8                 ; al = high byte
    call print_hex_byte
    mov al, dl                ; low byte zurueck
    call print_hex_byte
    pop edx
    pop eax
    ret

print_hex_byte:               ; al = Byte, edi = VGA-Offset; edi += 4
    push eax
    push ebx
    movzx ebx, al
    shr ebx, 4
    mov bl, [hexchars + ebx]
    mov [VGA + edi], bl
    mov byte [VGA + edi + 1], GREEN
    movzx ebx, al
    and ebx, 0x0F
    mov bl, [hexchars + ebx]
    mov [VGA + edi + 2], bl
    mov byte [VGA + edi + 3], GREEN
    add edi, 4
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

; ============================================================================
; Daten
; ============================================================================
msg_status   db '3d Minix-Superblock geparst:', 0
lbl_ninodes  db 'n_inodes        = 0x', 0
lbl_nzones   db 'n_zones         = 0x', 0
lbl_firstdata db 'first_data_zone = 0x', 0
lbl_magic    db 'magic           = 0x', 0
lbl_inodetab db 'inode_table_blk = 0x', 0

hexchars     db '0123456789ABCDEF'

align 4
sector_buf:
    times 512 db 0
