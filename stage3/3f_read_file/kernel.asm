; ============================================================================
; 3f kernel.asm  --  Datei lesen: /hello.txt -> Inhalt auf VGA
; ----------------------------------------------------------------------------
; AENDERUNG zu 3e: aus dem Listing wird ein Lookup.
;   1) Wir merken uns inode_table_sector (brauchen ihn zweimal)
;   2) Iterieren Root, vergleichen jeden Namen mit "hello.txt"
;   3) Bei Treffer: Inode neu laden, i_size + i_zone[0] holen
;   4) Datenblock lesen und i_size Bytes auf VGA ausgeben (\n -> neue Zeile)
;
; Das ist mini-`cat`: Pfad -> Inode -> Datenbloecke. Genau die Kette, die
; spaeter Linux' open()/read() unter der Haube macht (nur mit Caching/VFS).
; ============================================================================

bits 32
org  0x10000

VGA    equ 0xB8000
WHITE  equ 0x0F
YELLOW equ 0x0E
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

    ; ---- 1. Superblock --------------------------------------------------
    mov eax, 2
    mov edi, sector_buf
    call read_sector

    movzx eax, word [sector_buf + 4]      ; imap_blocks
    movzx ebx, word [sector_buf + 6]      ; zmap_blocks
    add eax, 2
    add eax, ebx
    shl eax, 1                            ; Minix-Block -> Sektor
    mov [inode_table_sector], eax

    ; ---- 2. Inode-Tabelle laden -----------------------------------------
    mov edi, sector_buf
    call read_sector

    ; Inode 1 -> Root-Daten-Block
    movzx eax, word [sector_buf + 14]
    shl eax, 1
    mov edi, sector_buf
    call read_sector

    ; ---- 3. Root durchsuchen ---------------------------------------------
    mov esi, sector_buf
    mov edx, 32
.find:
    movzx eax, word [esi]
    test eax, eax
    jz .skip
    push esi
    push eax                              ; Inode-Nr merken
    add esi, 2                            ; Name beginnt nach inode-Feld
    call name_eq_hello                    ; ZF=1 wenn "hello.txt"
    pop eax
    pop esi
    je .found
.skip:
    add esi, 16
    dec edx
    jnz .find

    mov esi, msg_notfound                 ; nicht gefunden
    mov edi, ROWB * 2
    call print_string
    jmp .hang

.found:
    ; ---- 4. Inode von hello.txt laden -----------------------------------
    push eax                              ; Inode-Nr fuer spaeter
    mov eax, [inode_table_sector]
    mov edi, sector_buf
    call read_sector
    pop eax                               ; Inode-Nr

    dec eax                               ; (N-1) * 32 = Offset im Inode-Block
    shl eax, 5
    lea esi, [sector_buf + eax]           ; esi -> Inode-Struktur

    mov ecx, [esi + 4]                    ; i_size (4 Byte)
    movzx eax, word [esi + 14]            ; i_zone[0] (Minix-Block-Nr)
    shl eax, 1                            ; -> Sektor

    ; ---- 5. Datenblock laden und ecx Bytes ausgeben ----------------------
    mov edi, sector_buf
    call read_sector

    mov esi, sector_buf
    mov edi, ROWB * 2                     ; Display ab Zeile 2
.print:
    test ecx, ecx
    jz .hang
    lodsb
    cmp al, 10                            ; Newline?
    je .nl
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], YELLOW
    add edi, 2
.advance:
    dec ecx
    jmp .print
.nl:
    push eax                              ; eax/edx/ebx ueber div retten
    push edx
    push ebx
    mov eax, edi
    xor edx, edx
    mov ebx, ROWB
    div ebx                               ; eax = Zeile, edx = Spalte*2
    inc eax
    mul ebx                               ; eax = (Zeile+1) * ROWB
    mov edi, eax
    pop ebx
    pop edx
    pop eax
    jmp .advance

.hang:
    hlt
    jmp .hang

; ============================================================================
; name_eq_hello: esi -> Kandidaten-Name (14 Byte, null-gepolstert)
;   ZF = 1 wenn die ersten 10 Bytes "hello.txt\0" sind.
; ============================================================================
name_eq_hello:
    push esi
    push edi
    push ecx
    mov edi, target_name
    mov ecx, 10
    cld
    repe cmpsb
    pop ecx
    pop edi
    pop esi
    ret

target_name db 'hello.txt', 0

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

; ============================================================================
; Daten
; ============================================================================
msg_status   db '3f cat /hello.txt -- Inhalt vom Minix-FS:', 0
msg_notfound db '(hello.txt nicht gefunden)', 0

inode_table_sector dd 0

align 4
sector_buf:
    times 512 db 0
