; ============================================================================
; 3c kernel.asm  --  Minix-Image lesbar machen
; ----------------------------------------------------------------------------
; AENDERUNG zu 3b: derselbe Kernel-Code, nur lesen wir jetzt Sektor 2 statt
; Sektor 0. mkdisk.sh hat das Disk-Image durch ein gueltiges Minix-v1-FS
; ersetzt (kein mount, kein sudo -- alles als Bytes geschrieben). Sektor 2 ist
; der Beginn von Minix-Block 1 = Superblock.
;
; Beweis im Hex-Dump: an Offset 16..17 (= Byte 16 und 17 vom Superblock) muss
; die Minix-v1-Magic 0x137F stehen. Little-Endian gespeichert -> wir sehen
; im Dump dort die Bytes  7F 13.
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

    ; Sektor 2 lesen = Minix-Block 1 = Superblock
    mov eax, 2
    mov edi, sector_buf
    call read_sector

    ; ersten 64 Bytes als Hex-Dump (4 Zeilen zu je 16 Bytes)
    mov esi, sector_buf
    mov ebx, ROWB * 2
    mov edx, 4
.line:
    mov edi, ebx
    mov ecx, 16
.bytec:
    movzx eax, byte [esi]
    inc esi
    call print_hex_byte
    mov byte [VGA + edi], ' '
    mov byte [VGA + edi + 1], WHITE
    add edi, 2
    loop .bytec
    add ebx, ROWB
    dec edx
    jnz .line

.hang:
    hlt
    jmp .hang

; ============================================================================
; read_sector  --  eax = LBA, edi = Puffer (>= 512 Byte). Liest 512 Bytes.
;   eax und edi bleiben fuer den Aufrufer erhalten.
; ============================================================================
read_sector:
    push eax
    push ebx
    push ecx
    push edx
    push edi

    mov ebx, eax              ; LBA merken

    mov dx, ATA_STATUS
.wait_bsy:
    in al, dx
    test al, 0x80
    jnz .wait_bsy

    mov eax, ebx              ; Drive: 0xE0 | LBA[24:27], LBA-Modus, Master
    shr eax, 24
    and al, 0x0F
    or  al, 0xE0
    mov dx, ATA_DRIVE
    out dx, al

    mov al, 1                 ; Sektor-Anzahl
    mov dx, ATA_SCOUNT
    out dx, al

    mov al, bl                ; LBA 0..7
    mov dx, ATA_LBA0
    out dx, al
    mov eax, ebx
    shr eax, 8
    mov dx, ATA_LBA1
    out dx, al                ; LBA 8..15
    mov eax, ebx
    shr eax, 16
    mov dx, ATA_LBA2
    out dx, al                ; LBA 16..23

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
    mov ecx, 256              ; 256 Words = 512 Bytes
    cld
    rep insw                  ; Ziel: ES:EDI, edi += 512 danach

    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ============================================================================
; Display-Helfer
; ============================================================================
print_hex_byte:                ; al = Byte, edi = VGA-Offset; edi += 4
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

msg_status db '3c Minix-Superblock -- Magic 7F 13 erwartet bei Offset 16:', 0
hexchars   db '0123456789ABCDEF'

align 4
sector_buf:
    times 512 db 0
