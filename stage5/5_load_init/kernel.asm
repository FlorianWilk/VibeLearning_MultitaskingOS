; ============================================================================
; 5 kernel.asm  --  /init.bin vom Minix-FS laden, dann nach Ring 3 springen
; ----------------------------------------------------------------------------
; AENDERUNG zu 4d: statt `incbin "user.bin"` lesen wir das User-Programm zur
; Boot-Zeit von der Disk. Das ist genau das Zusammenspiel, das Linus 1991 hatte:
; Disk-Treiber + FS + ein /sbin/init, das beim Boot geladen wird.
;
; Der neue Code load_init/() macht die volle Kette:
;     ATA read_sector -> Minix Superblock -> Inode-Tabelle -> Root-Dir
;     -> "init.bin" suchen -> Inode lesen -> Datenblock nach USER_ENTRY laden
;
; Danach ist alles wie in 4d: iret nach Ring 3, User macht sys_write + sys_exit.
;
; Damit haben wir alle vier Etappen verbunden:
;   Etappe 2 (Treiber-Prinzip)  ->  screen_putc
;   Etappe 3 (Disk + FS)         ->  read_sector + Minix-Reader
;   Etappe 4 (Userspace)         ->  iret-Trick + Syscalls
; ============================================================================

bits 32
org  0x10000

VGA          equ 0xB8000
WHITE        equ 0x0F
YELLOW       equ 0x0E
GREEN        equ 0x0A
COLS         equ 80
ROWB         equ COLS * 2
KERNEL_STACK equ 0x90000
USER_ENTRY   equ 0x40000
USER_STACK   equ 0x80000

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
    mov esp, KERNEL_STACK

    ; ---- Hardware-IRQs am PIC maskieren --------------------------------
    ; Wir springen gleich mit IF=1 nach Ring 3, haben aber keine IRQ-Handler
    ; in der IDT. Ohne Maske wuerde der erste Timer-IRQ -> GP -> Double ->
    ; Triple Fault ausloesen. (In 4d nur per Timing-Glueck nicht passiert.)
    mov al, 0xFF
    out 0x21, al
    out 0xA1, al

    ; ---- GDT/TSS/IDT wie 4d --------------------------------------------
    mov ebx, tss_main
    mov edi, gdt_tss
    mov [edi + 2], bx
    shr ebx, 16
    mov [edi + 4], bl
    mov [edi + 7], bh
    lgdt [gdt_descriptor]
    jmp 0x08:.cs_reloaded
.cs_reloaded:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov dword [tss_main + 4], KERNEL_STACK
    mov dword [tss_main + 8], 0x10
    mov ax, 0x28
    ltr ax
    call idt_setup
    lidt [idt_descriptor]

    mov esi, msg_status
    call screen_puts

    ; ---- /init.bin von Disk laden -> USER_ENTRY ------------------------
    call load_init
    test eax, eax
    jz .load_failed

    mov esi, msg_loaded
    call screen_puts

    ; ---- Sprung nach Ring 3 (wie 4d) -----------------------------------
    push dword 0x23
    push dword USER_STACK
    push dword 0x202
    push dword 0x1B
    push dword USER_ENTRY
    iret

.load_failed:
    mov esi, msg_no_init
    call screen_puts
    cli
.dead:
    hlt
    jmp .dead

; ============================================================================
; load_init  --  Minix-FS lesen, "init.bin" finden, nach USER_ENTRY laden.
;   Rueckgabe: eax = 1 wenn erfolgreich, 0 wenn nicht gefunden / zu gross.
; ============================================================================
load_init:
    ; ---- Superblock (Minix-Block 1 = Sektor 2) -------------------------
    mov eax, 2
    mov edi, sector_buf
    call read_sector

    movzx eax, word [sector_buf + 4]      ; imap_blocks
    movzx ebx, word [sector_buf + 6]      ; zmap_blocks
    add eax, 2
    add eax, ebx                          ; inode-table-block (Minix)
    shl eax, 1                            ; -> Sektor
    mov [inode_table_sector], eax

    ; ---- Inode-Tabelle laden -------------------------------------------
    mov edi, sector_buf
    call read_sector

    ; ---- Inode 1 (Root) -> Daten-Block -> einlesen ---------------------
    movzx eax, word [sector_buf + 14]    ; root i_zone[0]
    shl eax, 1
    mov edi, sector_buf
    call read_sector

    ; ---- "init.bin" im Root suchen -------------------------------------
    mov esi, sector_buf
    mov edx, 32
.find:
    movzx eax, word [esi]
    test eax, eax
    jz .skip
    push esi
    push eax
    add esi, 2
    call name_eq_init
    pop eax
    pop esi
    je .found
.skip:
    add esi, 16
    dec edx
    jnz .find
    xor eax, eax                          ; nicht gefunden
    ret

.found:
    ; eax = Inode-Nummer von init.bin
    ; ---- Inode-Tabelle erneut laden, dann auf den Inode zeigen ---------
    push eax
    mov eax, [inode_table_sector]
    mov edi, sector_buf
    call read_sector
    pop eax

    dec eax
    shl eax, 5                            ; (N-1) * 32
    lea esi, [sector_buf + eax]           ; -> Inode-Struktur

    ; ---- i_size und i_zone[0] sichern (sector_buf wird gleich ueberschrieben)
    mov ecx, [esi + 4]                    ; i_size
    movzx eax, word [esi + 14]            ; i_zone[0]

    cmp ecx, 1024
    ja .too_big

    ; ---- Daten-Block nach USER_ENTRY laden (1 Minix-Block = 2 Sektoren)
    shl eax, 1
    mov edi, USER_ENTRY
    call read_sector                      ; erster Sektor (512 B)
    inc eax
    add edi, 512
    call read_sector                      ; zweiter Sektor (weitere 512 B)

    mov eax, 1
    ret

.too_big:
    xor eax, eax
    ret

; ============================================================================
; name_eq_init  --  esi -> Kandidaten-Name; ZF=1 wenn "init.bin"
; ============================================================================
name_eq_init:
    push esi
    push edi
    push ecx
    mov edi, target_init
    mov ecx, 9                            ; "init.bin\0" = 9 Bytes
    cld
    repe cmpsb
    pop ecx
    pop edi
    pop esi
    ret

target_init db 'init.bin', 0

; ============================================================================
; read_sector  --  identisch zu 3b/3f
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
; IDT + Syscall-Dispatcher (identisch zu 4d)
; ============================================================================
idt_setup:
    mov eax, syscall_dispatch
    mov word [idt + 0x80*8 + 0], ax
    mov word [idt + 0x80*8 + 2], 0x08
    mov byte [idt + 0x80*8 + 4], 0x00
    mov byte [idt + 0x80*8 + 5], 0xEF
    shr eax, 16
    mov word [idt + 0x80*8 + 6], ax
    ret

syscall_dispatch:
    pusha
    cmp eax, 1
    je sys_exit
    cmp eax, 4
    je sys_write
    popa
    iret

sys_write:
    mov byte [attr], YELLOW
    mov esi, ecx
    mov ecx, edx
.next:
    test ecx, ecx
    jz .done
    lodsb
    call screen_putc
    dec ecx
    jmp .next
.done:
    mov byte [attr], WHITE
    popa
    iret

sys_exit:
    cli
    mov esi, msg_exited
    call screen_puts
    mov eax, ebx
    call screen_puthex
    mov esi, msg_close
    call screen_puts
.hang:
    hlt
    jmp .hang

; ============================================================================
; screen_putc / _puts / _puthex (identisch zu 4d)
; ============================================================================
screen_putc:
    push eax
    push ebx
    push edx
    cmp al, 0x0A
    je .nl
    mov ah, [attr]
    mov edx, [cursor]
    mov [VGA + edx], ax
    add edx, 2
    mov [cursor], edx
    jmp .done
.nl:
    mov eax, [cursor]
    xor edx, edx
    mov ebx, ROWB
    div ebx
    inc eax
    mul ebx
    mov [cursor], eax
.done:
    pop edx
    pop ebx
    pop eax
    ret

screen_puts:
    push eax
.loop:
    lodsb
    test al, al
    jz .done
    call screen_putc
    jmp .loop
.done:
    pop eax
    ret

screen_puthex:
    push eax
    push ebx
    push ecx
    push edx
    mov edx, eax
    mov ecx, 8
.next:
    rol edx, 4
    mov ebx, edx
    and ebx, 0x0F
    mov al, [hexchars + ebx]
    call screen_putc
    loop .next
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ============================================================================
; Daten
; ============================================================================
msg_status  db '5: lade /init.bin vom Minix-FS, starte als Ring-3-Prozess', 10, 0
msg_loaded  db '   ... geladen. iret nach Ring 3:', 10, 10, 0
msg_no_init db '*** /init.bin nicht gefunden -- system halt', 0
msg_exited  db '[process exited (code = 0x', 0
msg_close   db ')]', 10, 0

hexchars    db '0123456789ABCDEF'

attr        db WHITE
cursor      dd 0

inode_table_sector dd 0

; ============================================================================
; GDT + IDT + TSS (identisch zu 4d)
; ============================================================================
align 8
gdt_start:
    dq 0
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 11001111b
    db 0x00
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b
    db 11001111b
    db 0x00
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 11111010b
    db 11001111b
    db 0x00
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 11110010b
    db 11001111b
    db 0x00
gdt_tss:
    dw 0x67
    dw 0x0000
    db 0x00
    db 0x89
    db 0x00
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

align 8
idt:
    times 256*8 db 0
idt_end:

idt_descriptor:
    dw idt_end - idt - 1
    dd idt

align 4
tss_main:
    times 104 db 0

align 4
sector_buf:
    times 512 db 0
