; ============================================================================
; 11b kernel.asm  --  Minix-FS schreiben (writefile, Overwrite-Modell)
; ----------------------------------------------------------------------------
; writefile(name, buf, size): findet die existierende Datei, schreibt die Daten
; in ihre Zonen und aktualisiert i_size. (Kein Allozieren -- die Datei muss mit
; genug Zonen vorab existieren. Reicht fuer Compiler-Output.)
;
; Kernel-interne, blockierende Disk-Routinen (ueber IRQ14, wie Etappe 10/11a):
;   kread(eax=sektor)            -> 512 Byte in disk_kbuf
;   kwrite(eax=sektor, esi=src)  -> 512 Byte aus [esi] schreiben
;
; minix_locate(name in fname_buf): -> found_inode + saved_size + saved_zones[7]
; (Zonen/Groesse werden in Variablen kopiert, da kread disk_kbuf ueberschreibt.)
; ============================================================================

bits 32
org  0x10000

VGA          equ 0xB8000
WHITE        equ 0x0F
YELLOW       equ 0x0E
COLS         equ 80
ROWB         equ COLS * 2
SCREEN       equ ROWB * 25

BOOT_STACK   equ 0x90000

NPROC        equ 1
PCB_SIZE     equ 20
ST_UNUSED    equ 0
ST_READY     equ 1
ST_RUNNING   equ 2
ST_BLOCKED   equ 3
WAIT_DISK    equ 2

KERNEL_PT    equ 0x101000
PD0          equ 0x102000
UPT0         equ 0x104000
CODE0        equ 0x200000
STK0         equ 0x201000
HEAP0        equ 0x300000
KSTACK0      equ 0x9F000

USER_VIRT    equ 0x800000
USTACK_VIRT  equ 0x802000

SYS_EXIT      equ 1
SYS_WRITE     equ 4
SYS_READFILE  equ 13
SYS_WRITEFILE equ 16

ATA_DATA   equ 0x1F0
ATA_SCOUNT equ 0x1F2
ATA_LBA0   equ 0x1F3
ATA_LBA1   equ 0x1F4
ATA_LBA2   equ 0x1F5
ATA_DRIVE  equ 0x1F6
ATA_CMD    equ 0x1F7
ATA_STATUS equ 0x1F7
ATA_CTRL   equ 0x3F6

kernel_start:
    mov esp, BOOT_STACK
    mov ebx, tss_main
    mov edi, gdt_tss
    mov [edi + 2], bx
    shr ebx, 16
    mov [edi + 4], bl
    mov [edi + 7], bh
    lgdt [gdt_descriptor]
    jmp 0x08:.cs
.cs:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov dword [tss_main + 8], 0x10
    mov ax, 0x28
    ltr ax

    call pic_remap
    mov al, 0xFA
    out 0x21, al
    mov al, 0xBF
    out 0xA1, al
    mov dx, ATA_CTRL
    xor al, al
    out dx, al
    call idt_setup
    lidt [idt_descriptor]

    mov esi, msg_status
    call screen_puts

    mov esi, user_image
    mov edi, CODE0
    mov ecx, user_image_end - user_image
    cld
    rep movsb

    call setup_paging

    mov eax, USER_VIRT
    mov ebx, USTACK_VIRT
    mov edi, KSTACK0
    call build_kstack
    mov [proc_table + 0], dword ST_READY
    mov [proc_table + 4], eax
    mov [proc_table + 8], dword KSTACK0
    mov [proc_table + 12], dword PD0

    mov dword [current], 0
    mov dword [proc_table + 0], ST_RUNNING
    mov dword [tss_main + 4], KSTACK0
    mov eax, PD0
    mov cr3, eax
    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax
    mov esp, [proc_table + 4]
    popa
    iret

; ============================================================================
build_kstack:
    mov edx, edi
    sub edx, 4
    mov dword [edx], 0x23
    sub edx, 4
    mov [edx], ebx
    sub edx, 4
    mov dword [edx], 0x202
    sub edx, 4
    mov dword [edx], 0x1B
    sub edx, 4
    mov [edx], eax
    mov ecx, 8
.z:
    sub edx, 4
    mov dword [edx], 0
    loop .z
    mov eax, edx
    ret

resume_current:
    mov eax, [current]
    imul eax, eax, PCB_SIZE
    mov ebx, [proc_table + eax + 8]
    mov [tss_main + 4], ebx
    mov ebx, [proc_table + eax + 12]
    mov cr3, ebx
    mov esp, [proc_table + eax + 4]
    popa
    iret

timer_handler:
    pusha
    mov al, 0x20
    out 0x20, al
    mov eax, [current]
    imul eax, eax, PCB_SIZE
    mov [proc_table + eax + 4], esp
    cmp dword [proc_table + eax + 0], ST_RUNNING
    jne .p
    mov dword [proc_table + eax + 0], ST_READY
.p:
    call schedule
    jmp resume_current

disk_irq_handler:
    pusha
    mov dx, ATA_STATUS
    in al, dx
    cmp byte [disk_op], 0
    jne .done
    mov edi, disk_kbuf
    mov dx, ATA_DATA
    mov ecx, 256
    cld
    rep insw
.done:
    mov eax, WAIT_DISK
    call wakeup
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    popa
    iret

block:
    pushfd
    push dword 0x08
    push dword .resume
    pusha
    mov ebx, [current]
    imul ebx, ebx, PCB_SIZE
    mov [proc_table + ebx + 4], esp
    mov dword [proc_table + ebx + 0], ST_BLOCKED
    mov [proc_table + ebx + 16], eax
    call schedule
    jmp resume_current
.resume:
    ret

wakeup:
    push ecx
    push ebx
    xor ecx, ecx
.w:
    mov ebx, ecx
    imul ebx, ebx, PCB_SIZE
    cmp dword [proc_table + ebx + 0], ST_BLOCKED
    jne .nx
    cmp [proc_table + ebx + 16], eax
    jne .nx
    mov dword [proc_table + ebx + 0], ST_READY
.nx:
    inc ecx
    cmp ecx, NPROC
    jb .w
    pop ebx
    pop ecx
    ret

schedule:
    mov ecx, [current]
.scan:
    inc ecx
    cmp ecx, NPROC
    jb .nw
    xor ecx, ecx
.nw:
    mov eax, ecx
    imul eax, eax, PCB_SIZE
    cmp dword [proc_table + eax + 0], ST_READY
    je .found
    cmp ecx, [current]
    jne .scan
    sti
    hlt
    cli
    mov ecx, [current]
    jmp .scan
.found:
    mov [current], ecx
    imul ecx, ecx, PCB_SIZE
    mov dword [proc_table + ecx + 0], ST_RUNNING
    ret

; ============================================================================
; ATA-Setup (Sektor in ebx) + kread/kwrite (blockierend ueber IRQ14)
; ============================================================================
ata_send:
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
    ret

kread:                                  ; eax = sektor -> disk_kbuf
    push ebx
    push ecx
    push edx
    mov byte [disk_op], 0
    mov ebx, eax
    call ata_send
    mov al, 0x20
    mov dx, ATA_CMD
    out dx, al
    mov eax, WAIT_DISK
    call block
    pop edx
    pop ecx
    pop ebx
    ret

kwrite:                                 ; eax = sektor, esi = src (512)
    push ebx
    push ecx
    push edx
    mov byte [disk_op], 1
    mov ebx, eax
    call ata_send
    mov al, 0x30
    mov dx, ATA_CMD
    out dx, al
    mov dx, ATA_STATUS
.wd:
    in al, dx
    test al, 0x08
    jz .wd
    mov dx, ATA_DATA
    mov ecx, 256
    cld
    rep outsw
    mov eax, WAIT_DISK
    call block
    pop edx
    pop ecx
    pop ebx
    ret

; ============================================================================
; copy_name(ebx = name): nach fname_buf (16 Byte, null-gepolstert)
; ============================================================================
copy_name:
    push eax
    push ecx
    push esi
    push edi
    mov edi, fname_buf
    mov ecx, 4
    xor eax, eax
    cld
    rep stosd
    mov esi, ebx
    mov edi, fname_buf
    mov ecx, 14
.c:
    mov al, [esi]
    test al, al
    jz .d
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .c
.d:
    pop edi
    pop esi
    pop ecx
    pop eax
    ret

name_eq_fname:                          ; esi = Dir-Name (14), ZF=1 wenn ==
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
; minix_locate: sucht fname_buf, fuellt found_inode/saved_size/saved_zones
;   found_inode = 0 wenn nicht gefunden.
; ============================================================================
minix_locate:
    mov eax, 2
    call kread
    movzx eax, word [disk_kbuf + 4]
    movzx ebx, word [disk_kbuf + 6]
    add eax, 2
    add eax, ebx
    shl eax, 1
    mov [inode_table_sector], eax
    mov eax, [inode_table_sector]
    call kread
    movzx eax, word [disk_kbuf + 14]    ; Root i_zone[0]
    shl eax, 1
    call kread                          ; Root-Dir
    mov esi, disk_kbuf
    mov ecx, 32
.f:
    movzx eax, word [esi]
    test eax, eax
    jz .skip
    push esi
    push eax
    push ecx
    add esi, 2
    call name_eq_fname
    pop ecx
    pop eax
    pop esi
    je .found
.skip:
    add esi, 16
    dec ecx
    jnz .f
    mov dword [found_inode], 0
    ret
.found:
    mov [found_inode], eax
    mov eax, [inode_table_sector]
    call kread
    mov eax, [found_inode]
    dec eax
    shl eax, 5
    lea esi, [disk_kbuf + eax]
    mov eax, [esi + 4]
    mov [saved_size], eax
    xor ecx, ecx
.zc:
    movzx eax, word [esi + ecx*2 + 14]
    mov [saved_zones + ecx*4], eax
    inc ecx
    cmp ecx, 7
    jb .zc
    mov eax, [found_inode]
    ret

; ============================================================================
; Syscalls
; ============================================================================
syscall_dispatch:
    pusha
    cmp eax, SYS_WRITE
    je do_write
    cmp eax, SYS_READFILE
    je do_readfile
    cmp eax, SYS_WRITEFILE
    je do_writefile
    cmp eax, SYS_EXIT
    je do_exit
.ret:
    popa
    iret

do_write:
    mov byte [attr], YELLOW
    mov esi, ecx
    mov ecx, edx
.n:
    test ecx, ecx
    jz .done
    lodsb
    call screen_putc
    dec ecx
    jmp .n
.done:
    mov byte [attr], WHITE
    popa
    iret

; ---- readfile(ebx=name, ecx=buf) -> eax=size ------------------------------
do_readfile:
    mov [io_dst], ecx
    call copy_name
    call minix_locate
    test eax, eax
    jz .nf
    mov eax, [saved_size]
    mov [io_rem], eax
    mov dword [io_idx], 0
.rl:
    mov eax, [io_rem]
    test eax, eax
    jz .done
    mov eax, [io_idx]
    cmp eax, 7
    jae .done
    mov ebx, [io_idx]
    mov eax, [saved_zones + ebx*4]
    test eax, eax
    jz .done
    shl eax, 1
    call kread                          ; erster Sektor -> disk_kbuf
    mov esi, disk_kbuf
    mov edi, [io_dst]
    mov ecx, 128
    cld
    rep movsd
    mov ebx, [io_idx]
    mov eax, [saved_zones + ebx*4]
    shl eax, 1
    inc eax
    call kread                          ; zweiter Sektor
    mov esi, disk_kbuf
    mov edi, [io_dst]
    add edi, 512
    mov ecx, 128
    cld
    rep movsd
    add dword [io_dst], 1024
    inc dword [io_idx]
    mov eax, [io_rem]
    cmp eax, 1024
    jbe .done
    sub eax, 1024
    mov [io_rem], eax
    jmp .rl
.done:
    mov eax, [saved_size]
    mov [esp + 28], eax
    jmp syscall_dispatch.ret
.nf:
    mov dword [esp + 28], -1
    jmp syscall_dispatch.ret

; ---- writefile(ebx=name, ecx=buf, edx=size) -> eax=0/-1 -------------------
do_writefile:
    mov [io_dst], ecx
    mov [io_param_size], edx
    call copy_name
    call minix_locate
    test eax, eax
    jz .nf
    mov eax, [io_param_size]
    mov [io_rem], eax
    mov dword [io_idx], 0
.wl:
    mov eax, [io_rem]
    test eax, eax
    jz .wdone
    mov eax, [io_idx]
    cmp eax, 7
    jae .wdone
    mov ebx, [io_idx]
    mov eax, [saved_zones + ebx*4]
    test eax, eax
    jz .wdone
    ; zbuf (1024) nullen, dann min(1024, rem) aus io_dst kopieren
    mov edi, zbuf
    mov ecx, 256
    xor eax, eax
    cld
    rep stosd
    mov ecx, [io_rem]
    cmp ecx, 1024
    jbe .cp
    mov ecx, 1024
.cp:
    mov esi, [io_dst]
    mov edi, zbuf
    cld
    rep movsb
    ; Zone (2 Sektoren) schreiben
    mov ebx, [io_idx]
    mov eax, [saved_zones + ebx*4]
    shl eax, 1
    mov esi, zbuf
    call kwrite
    mov ebx, [io_idx]
    mov eax, [saved_zones + ebx*4]
    shl eax, 1
    inc eax
    mov esi, zbuf + 512
    call kwrite
    add dword [io_dst], 1024
    inc dword [io_idx]
    mov eax, [io_rem]
    cmp eax, 1024
    jbe .wdone
    sub eax, 1024
    mov [io_rem], eax
    jmp .wl
.wdone:
    ; i_size aktualisieren
    mov eax, [inode_table_sector]
    call kread
    mov eax, [found_inode]
    dec eax
    shl eax, 5
    lea edi, [disk_kbuf + eax]
    mov ecx, [io_param_size]
    mov [edi + 4], ecx
    mov eax, [inode_table_sector]
    mov esi, disk_kbuf
    call kwrite
    mov dword [esp + 28], 0
    jmp syscall_dispatch.ret
.nf:
    mov dword [esp + 28], -1
    jmp syscall_dispatch.ret

do_exit:
    mov eax, [current]
    imul eax, eax, PCB_SIZE
    mov dword [proc_table + eax + 0], ST_UNUSED
    call schedule
    jmp resume_current

; ============================================================================
setup_paging:
    mov edi, KERNEL_PT
    mov eax, 0x003
    mov ecx, 1024
.k:
    mov [edi], eax
    add eax, 0x1000
    add edi, 4
    loop .k
    mov edi, UPT0
    call clear_page
    mov dword [UPT0 + 0*4], CODE0 | 0x007
    mov dword [UPT0 + 1*4], STK0  | 0x007
    mov edi, PD0
    call clear_page
    mov dword [PD0 + 0*4], KERNEL_PT | 0x003
    mov dword [PD0 + 2*4], UPT0      | 0x007
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
    jmp .wr
.nl:
    mov eax, [cursor]
    xor edx, edx
    mov ebx, ROWB
    div ebx
    inc eax
    mul ebx
    mov edx, eax
.wr:
    cmp edx, SCREEN
    jb .s
    mov edx, ROWB * 2
.s:
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

pic_remap:
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    ret

idt_setup:
    mov eax, timer_handler
    mov word [idt + 0x20*8 + 0], ax
    mov word [idt + 0x20*8 + 2], 0x08
    mov byte [idt + 0x20*8 + 4], 0x00
    mov byte [idt + 0x20*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x20*8 + 6], ax
    mov eax, disk_irq_handler
    mov word [idt + 0x2E*8 + 0], ax
    mov word [idt + 0x2E*8 + 2], 0x08
    mov byte [idt + 0x2E*8 + 4], 0x00
    mov byte [idt + 0x2E*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x2E*8 + 6], ax
    mov eax, syscall_dispatch
    mov word [idt + 0x80*8 + 0], ax
    mov word [idt + 0x80*8 + 2], 0x08
    mov byte [idt + 0x80*8 + 4], 0x00
    mov byte [idt + 0x80*8 + 5], 0xEE
    shr eax, 16
    mov word [idt + 0x80*8 + 6], ax
    ret

; ============================================================================
msg_status db '11b: writefile -> Minix-Datei "notiz" schreiben + lesen:', 0x0A, 0x0A, 0

attr               db WHITE
cursor             dd ROWB * 2
current            dd 0
disk_op            db 0
inode_table_sector dd 0
found_inode        dd 0
saved_size         dd 0
saved_zones        times 7 dd 0
io_dst             dd 0
io_rem             dd 0
io_idx             dd 0
io_param_size      dd 0
fname_buf          times 16 db 0
proc_table         times NPROC*PCB_SIZE db 0

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
disk_kbuf:
    times 512 db 0
align 4
zbuf:
    times 1024 db 0
