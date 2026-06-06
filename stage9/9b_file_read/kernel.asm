; ============================================================================
; 9b kernel.asm  --  readfile-Syscall (ganze Datei laden)
; ----------------------------------------------------------------------------
; Erweitert 9a um einen generischen Datei-Lese-Syscall:
;   readfile(name, buf) -> size       (laedt die ganze Datei in buf)
; Minix-FS-Lookup mit variablem Namen (wie Etappe 3, aber Name als Parameter),
; liest dann alle direkten Daten-Zonen (bis 7 = 7 KB) in den User-Puffer.
;
; Syscalls:  1=exit  4=write  12=sbrk  13=readfile(name,buf)
; ============================================================================

bits 32
org  0x10000

VGA          equ 0xB8000
WHITE        equ 0x0F
COLS         equ 80
ROWB         equ COLS * 2
SCREEN       equ ROWB * 25

BOOT_STACK   equ 0x90000
USER_KSTACK  equ 0x9F000

KERNEL_PT    equ 0x101000
PD_USER      equ 0x102000
USER_PT      equ 0x104000
CODE_FRAME   equ 0x200000
STACK_FRAME  equ 0x201000
HEAP_FRAME0  equ 0x300000

USER_VIRT    equ 0x800000
USTACK_VIRT  equ 0x802000
HEAP_VIRT    equ 0x900000
HEAP_PAGES   equ 8

SYS_EXIT     equ 1
SYS_WRITE    equ 4
SYS_SBRK     equ 12
SYS_READFILE equ 13

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
    mov esp, BOOT_STACK
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
    mov dword [tss_main + 4], USER_KSTACK
    mov dword [tss_main + 8], 0x10
    mov ax, 0x28
    ltr ax
    call idt_setup
    lidt [idt_descriptor]

    ; Alle Hardware-IRQs maskieren: wir pollen die Disk (read_sector), kein IRQ.
    ; Sonst feuert IRQ14 (ATA, Vektor 0x76) nach dem Lesen -> kein Handler -> GP.
    mov al, 0xFF
    out 0x21, al
    out 0xA1, al

    mov esi, user_image
    mov edi, CODE_FRAME
    mov ecx, user_image_end - user_image
    cld
    rep movsb

    call setup_paging
    mov eax, PD_USER
    mov cr3, eax
    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax
    mov dword [brk], HEAP_VIRT

    mov esp, USER_KSTACK
    push dword 0x23
    push dword USTACK_VIRT
    push dword 0x202
    push dword 0x1B
    push dword USER_VIRT
    iret

; ============================================================================
setup_paging:
    mov edi, KERNEL_PT
    mov eax, 0x003
    mov ecx, 1024
.kmap:
    mov [edi], eax
    add eax, 0x1000
    add edi, 4
    loop .kmap
    mov edi, USER_PT
    call clear_page
    mov dword [USER_PT + 0*4], CODE_FRAME  | 0x007
    mov dword [USER_PT + 1*4], STACK_FRAME | 0x007
    mov ecx, HEAP_PAGES
    mov edi, USER_PT + 256*4
    mov eax, HEAP_FRAME0 | 0x007
.hmap:
    mov [edi], eax
    add eax, 0x1000
    add edi, 4
    loop .hmap
    mov edi, PD_USER
    call clear_page
    mov dword [PD_USER + 0*4], KERNEL_PT | 0x003
    mov dword [PD_USER + 2*4], USER_PT   | 0x007
    ret

clear_page:
    push eax
    push ecx
    push edi
    mov ecx, 1024
    xor eax, eax
    cld
    rep stosd
    pop edi
    pop ecx
    pop eax
    ret

; ============================================================================
syscall_dispatch:
    pusha
    cmp eax, SYS_WRITE
    je do_write
    cmp eax, SYS_SBRK
    je do_sbrk
    cmp eax, SYS_READFILE
    je do_readfile
    cmp eax, SYS_EXIT
    je do_exit
.ret:
    popa
    iret

do_write:
    mov esi, ecx
    mov ecx, edx
.next:
    test ecx, ecx
    jz syscall_dispatch.ret
    lodsb
    call screen_putc
    dec ecx
    jmp .next

do_sbrk:
    mov eax, [brk]
    add ebx, eax
    mov [brk], ebx
    mov [esp + 28], eax
    jmp syscall_dispatch.ret

do_exit:
    cli
    mov esi, msg_halt
    call screen_puts
.dead:
    hlt
    jmp .dead

; ---- readfile(ebx=name, ecx=buf) -> eax=size / -1 -------------------------
do_readfile:
    ; Name nach fname_buf (16 Byte, null-gepolstert)
    mov edi, fname_buf
    push ecx
    mov ecx, 4
    xor eax, eax
    cld
    rep stosd
    pop ecx
    mov esi, ebx
    mov edi, fname_buf
    push ecx
    mov ecx, 14
.cpn:
    mov al, [esi]
    test al, al
    jz .cpdone
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .cpn
.cpdone:
    pop ecx                          ; ecx = buf

    call minix_find                  ; eax = inode-nr (0 = nicht gefunden)
    test eax, eax
    jz .notfound

    push ecx                         ; buf retten
    push eax                         ; inode-nr
    mov eax, [inode_table_sector]
    mov edi, sector_buf
    call read_sector
    pop eax
    dec eax
    shl eax, 5
    lea esi, [sector_buf + eax]      ; esi -> Inode (bleibt gueltig: reads gehen nach buf)
    pop ecx                          ; buf

    mov eax, [esi + 4]               ; i_size
    mov [rf_size], eax

    xor ebx, ebx                     ; Zone-Index
    mov edi, ecx                     ; Ziel-Puffer
    mov ecx, [rf_size]               ; verbleibende Bytes
    test ecx, ecx
    jz .rfdone
.zloop:
    cmp ebx, 7
    jae .rfdone
    movzx eax, word [esi + ebx*2 + 14]   ; Zone
    test eax, eax
    jz .rfdone
    shl eax, 1                       ; Zone -> Sektor
    call read_sector                 ; -> edi
    inc eax
    add edi, 512
    call read_sector                 ; -> edi+512
    add edi, 512                     ; insgesamt +1024
    inc ebx
    cmp ecx, 1024
    jbe .rfdone
    sub ecx, 1024
    jmp .zloop
.rfdone:
    mov eax, [rf_size]
    mov [esp + 28], eax
    jmp syscall_dispatch.ret
.notfound:
    mov dword [esp + 28], -1
    jmp syscall_dispatch.ret

; ============================================================================
; minix_find: sucht fname_buf im Root, eax = inode-nr (0 = nicht gefunden)
; ============================================================================
minix_find:
    mov eax, 2
    mov edi, sector_buf
    call read_sector
    movzx eax, word [sector_buf + 4]
    movzx ebx, word [sector_buf + 6]
    add eax, 2
    add eax, ebx
    shl eax, 1
    mov [inode_table_sector], eax
    mov edi, sector_buf
    call read_sector
    movzx eax, word [sector_buf + 14]
    shl eax, 1
    mov edi, sector_buf
    call read_sector
    mov esi, sector_buf
    mov edx, 32
.f:
    movzx eax, word [esi]
    test eax, eax
    jz .fskip
    push esi
    push eax
    add esi, 2
    call name_eq_fname
    pop eax
    pop esi
    je .ret
.fskip:
    add esi, 16
    dec edx
    jnz .f
    xor eax, eax
.ret:
    ret

name_eq_fname:
    push esi
    push edi
    push ecx
    mov edi, fname_buf
    mov ecx, 14
    cld
    repe cmpsb
    pop ecx
    pop edi
    pop esi
    ret

; ============================================================================
read_sector:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    mov ebx, eax
    mov dx, ATA_STATUS
.wb:
    in al, dx
    test al, 0x80
    jnz .wb
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
.wd:
    mov dx, ATA_STATUS
    in al, dx
    test al, 0x80
    jnz .wd
    test al, 8
    jz .wd
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
screen_putc:
    push eax
    push ebx
    push edx
    cmp al, 0x0A
    je .nl
    mov ah, WHITE
    mov edx, [cursor]
    mov [VGA + edx], ax
    add edx, 2
    jmp .wrap
.nl:
    mov eax, [cursor]
    xor edx, edx
    mov ebx, ROWB
    div ebx
    inc eax
    mul ebx
    mov edx, eax
.wrap:
    cmp edx, SCREEN
    jb .store
    mov edx, ROWB * 24
.store:
    mov [cursor], edx
    pop edx
    pop ebx
    pop eax
    ret

screen_puts:
    push eax
.l:
    lodsb
    test al, al
    jz .d
    call screen_putc
    jmp .l
.d:
    pop eax
    ret

idt_setup:
    mov eax, syscall_dispatch
    mov word [idt + 0x80*8 + 0], ax
    mov word [idt + 0x80*8 + 2], 0x08
    mov byte [idt + 0x80*8 + 4], 0x00
    mov byte [idt + 0x80*8 + 5], 0xEE
    shr eax, 16
    mov word [idt + 0x80*8 + 6], ax
    ret

; ============================================================================
msg_halt           db 0x0A, '[exit -- system haelt]', 0
cursor             dd 0
brk                dd 0
fname_buf          times 16 db 0
inode_table_sector dd 0
rf_size            dd 0

align 16
user_image:
    incbin "user.bin"
user_image_end:

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
