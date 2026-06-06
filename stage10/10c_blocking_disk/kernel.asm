; ============================================================================
; 10c kernel.asm  --  Blockierende Disk-I/O (IRQ14, kein Polling mehr)
; ----------------------------------------------------------------------------
; sys_read_disk schickt den ATA-Read-Befehl und legt den Prozess schlafen
; (block(DISK)) -- es POLLT NICHT. Wenn die Disk fertig ist, feuert IRQ14
; (Vektor 0x2E, am Slave-PIC). Der Handler liest die 512 Byte in einen
; Kernel-Puffer und weckt den Prozess (wakeup(DISK)).
;
; Warum Kernel-Puffer? Der IRQ kann feuern, waehrend ein ANDERER Prozess laeuft
; (anderer CR3). Der identity-gemappte Kernel-Puffer ist in jedem Adressraum
; sichtbar; der geweckte Prozess kopiert ihn dann in seinen eigenen Puffer.
;
; Kein Lost-Wakeup: do_read_disk laeuft im Syscall (Interrupt Gate, IF=0), der
; IRQ feuert also erst, nachdem block() den Prozess BLOCKED gesetzt und zu
; proc_b (IF=1) gewechselt hat.
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

NPROC        equ 2
PCB_SIZE     equ 20
ST_UNUSED    equ 0
ST_READY     equ 1
ST_RUNNING   equ 2
ST_BLOCKED   equ 3
WAIT_DISK    equ 2

KERNEL_PT    equ 0x101000
PD0          equ 0x102000
PD1          equ 0x103000
UPT0         equ 0x104000
UPT1         equ 0x105000
CODE0        equ 0x200000
STK0         equ 0x201000
CODE1        equ 0x202000
STK1         equ 0x203000
KSTACK0      equ 0x9F000
KSTACK1      equ 0x9D000

USER_VIRT    equ 0x800000
USTACK_VIRT  equ 0x802000

SYS_EXIT     equ 1
SYS_WRITE    equ 4
SYS_READDISK equ 14

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
    mov al, 0xFA                       ; Master: Timer(0) + Cascade(2) frei
    out 0x21, al
    mov al, 0xBF                       ; Slave: IRQ14 (bit 6) frei
    out 0xA1, al
    ; ATA-Interrupts aktivieren (nIEN = 0 im Device Control)
    mov dx, ATA_CTRL
    xor al, al
    out dx, al
    call idt_setup
    lidt [idt_descriptor]

    mov esi, msg_status
    call screen_puts

    mov esi, proc_a_image
    mov edi, CODE0
    mov ecx, proc_a_image_end - proc_a_image
    cld
    rep movsb
    mov esi, proc_b_image
    mov edi, CODE1
    mov ecx, proc_b_image_end - proc_b_image
    rep movsb

    call setup_paging

    mov eax, USER_VIRT
    mov ebx, USTACK_VIRT
    mov edi, KSTACK0
    call build_kstack
    mov [proc_table + 0*PCB_SIZE + 0], dword ST_READY
    mov [proc_table + 0*PCB_SIZE + 4], eax
    mov [proc_table + 0*PCB_SIZE + 8], dword KSTACK0
    mov [proc_table + 0*PCB_SIZE + 12], dword PD0
    mov eax, USER_VIRT
    mov ebx, USTACK_VIRT
    mov edi, KSTACK1
    call build_kstack
    mov [proc_table + 1*PCB_SIZE + 0], dword ST_READY
    mov [proc_table + 1*PCB_SIZE + 4], eax
    mov [proc_table + 1*PCB_SIZE + 8], dword KSTACK1
    mov [proc_table + 1*PCB_SIZE + 12], dword PD1

    mov dword [current], 0
    mov dword [proc_table + 0*PCB_SIZE + 0], ST_RUNNING
    mov dword [tss_main + 4], KSTACK0
    mov eax, PD0
    mov cr3, eax
    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax
    mov esp, [proc_table + 0*PCB_SIZE + 4]
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

; ============================================================================
; Disk-IRQ-Handler (IRQ14 / Vektor 0x2E): Daten in Kernel-Puffer, wakeup
; ============================================================================
disk_irq_handler:
    pusha
    mov dx, ATA_STATUS
    in al, dx                           ; Status lesen = IRQ acknowledgen
    mov edi, disk_kbuf
    mov dx, ATA_DATA
    mov ecx, 256
    cld
    rep insw                            ; 512 Byte in den Kernel-Puffer
    mov eax, WAIT_DISK
    call wakeup
    mov al, 0x20                        ; EOI: erst Slave, dann Master
    out 0xA0, al
    out 0x20, al
    popa
    iret

; ============================================================================
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
    mov edi, UPT1
    call clear_page
    mov dword [UPT1 + 0*4], CODE1 | 0x007
    mov dword [UPT1 + 1*4], STK1  | 0x007
    mov edi, PD1
    call clear_page
    mov dword [PD1 + 0*4], KERNEL_PT | 0x003
    mov dword [PD1 + 2*4], UPT1      | 0x007
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
    cmp eax, SYS_READDISK
    je do_read_disk
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

; read_disk(ebx=sektor, ecx=buf): ATA-Befehl schicken, blockieren, dann kopieren
do_read_disk:
    mov [disk_user_buf], ecx
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
    mov al, 0x20
    mov dx, ATA_CMD
    out dx, al
    ; schlafen bis IRQ14 die Daten geliefert hat
    mov eax, WAIT_DISK
    call block
    ; Kernel-Puffer -> User-Puffer (jetzt im richtigen Adressraum)
    mov esi, disk_kbuf
    mov edi, [disk_user_buf]
    mov ecx, 128
    cld
    rep movsd
    jmp syscall_dispatch.ret

do_exit:
    mov eax, [current]
    imul eax, eax, PCB_SIZE
    mov dword [proc_table + eax + 0], ST_UNUSED
    call schedule
    jmp resume_current

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
msg_status db '10c: proc_b zaehlt, proc_a liest blockierend von Disk (IRQ14):', 0x0A, 0x0A, 0

attr           db WHITE
cursor         dd ROWB * 2
current        dd 0
disk_user_buf  dd 0
proc_table     times NPROC*PCB_SIZE db 0

align 16
proc_a_image:
    incbin "proc_a.bin"
proc_a_image_end:
align 16
proc_b_image:
    incbin "proc_b.bin"
proc_b_image_end:

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
