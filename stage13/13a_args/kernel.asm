; ============================================================================
; 12a kernel.asm  --  Shell auf dem Multitasking-Kernel (exec + wait)
; ----------------------------------------------------------------------------
; Vereint: Scheduler+Zustaende (10), blockierende Tastatur (10b), Disk-Load per
; IRQ (10c/11), und neu: exec/wait mit mehreren Prozess-Slots.
;
; Prozess-Slots (NPROC): Slot 0 = Shell (init). exec sucht einen freien Slot,
; laedt das Programm in dessen Adressraum und setzt ihn READY. Foreground:
; die Shell ruft danach block(WAIT_CHILD) -> sie schlaeft, bis das Kind exit
; macht (do_exit weckt per wakeup(WAIT_CHILD)).
;
; Pro Slot ein eigener Adressraum (PD/UPT/Code/Stack-Frame) + Kernel-Stack,
; alle beim Boot vorab aufgebaut. Alle Programme bei virt 0x800000 (isoliert).
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

NPROC        equ 4
PCB_SIZE     equ 20
ST_UNUSED    equ 0
ST_READY     equ 1
ST_RUNNING   equ 2
ST_BLOCKED   equ 3
WAIT_KBD     equ 1
WAIT_DISK    equ 2
WAIT_CHILD   equ 3

KERNEL_PT    equ 0x101000
PD_BASE      equ 0x110000           ; PD[i]=PD_BASE+i*0x2000, UPT[i]=+0x1000
CODE_BASE    equ 0x200000           ; CODE[i]=CODE_BASE+i*0x10000, STACK=+0x1000
KSTACK_BASE  equ 0x9F000            ; KSTACK[i]=KSTACK_BASE-i*0x1000

USER_VIRT    equ 0x800000
USTACK_VIRT  equ 0x802000

SYS_EXIT     equ 1
SYS_READ     equ 3
SYS_WRITE    equ 4
SYS_EXEC     equ 11

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
    mov al, 0xF8                        ; Timer(0)+Tastatur(1)+Cascade(2) frei
    out 0x21, al
    mov al, 0xBF                        ; Slave: IRQ14 (Disk) frei
    out 0xA1, al
    mov dx, ATA_CTRL
    xor al, al
    out dx, al
    call idt_setup
    lidt [idt_descriptor]

    call setup_paging

    ; ---- Shell in Slot 0 laden (eingebettet) --------------------------
    mov esi, shell_image
    mov edi, CODE_BASE                  ; CODE[0]
    mov ecx, shell_image_end - shell_image
    cld
    rep movsb

    mov eax, USER_VIRT
    mov ebx, USTACK_VIRT
    mov edi, KSTACK_BASE                ; KSTACK[0]
    call build_kstack
    mov [proc_table + 0], dword ST_READY
    mov [proc_table + 4], eax
    mov [proc_table + 8], dword KSTACK_BASE
    mov [proc_table + 12], dword PD_BASE

    mov dword [current], 0
    mov dword [proc_table + 0], ST_RUNNING
    mov dword [tss_main + 4], KSTACK_BASE
    mov eax, PD_BASE
    mov cr3, eax
    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax
    mov esp, [proc_table + 4]
    popa
    iret

; ============================================================================
build_kstack:                           ; eax=EIP, ebx=user-esp, edi=kstack-top
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
    ; Nur umschalten, wenn current wirklich RUNNING ist. Im Idle (current
    ; BLOCKED, wir stecken in schedules hlt-Schleife) wuerde sonst der
    ; saved_esp des Blockierten ueberschrieben + der Stack nested wachsen.
    cmp dword [proc_table + eax + 0], ST_RUNNING
    jne .justret
    mov [proc_table + eax + 4], esp
    mov dword [proc_table + eax + 0], ST_READY
    call schedule
    jmp resume_current
.justret:
    popa
    iret

kbd_handler:
    pusha
    in al, 0x60
    cmp al, 0x2A                 ; Shift links gedrueckt
    je .shift_on
    cmp al, 0x36                 ; Shift rechts gedrueckt
    je .shift_on
    cmp al, 0xAA                 ; Shift links losgelassen
    je .shift_off
    cmp al, 0xB6                 ; Shift rechts losgelassen
    je .shift_off
    test al, 0x80
    jnz .eoi
    cmp al, 0x39
    ja .eoi
    movzx ebx, al
    cmp byte [shift_state], 0    ; Shift aktiv? -> andere Tabelle
    jne .sh
    mov al, [scancode_to_ascii + ebx]
    jmp .got
.sh:
    mov al, [scancode_to_ascii_shift + ebx]
.got:
    test al, al
    jz .eoi
    cmp al, 0x0D
    je .enter
    cmp al, 0x08
    je .bs
    movzx ecx, byte [line_len]
    cmp ecx, 127
    jae .eoi
    mov [line_buffer + ecx], al
    inc byte [line_len]
    mov byte [attr], WHITE
    call screen_putc
    jmp .eoi
.enter:
    mov al, 0x0A
    mov byte [attr], WHITE
    call screen_putc
    mov eax, WAIT_KBD
    call wakeup
    jmp .eoi
.bs:
    cmp byte [line_len], 0
    je .eoi
    dec byte [line_len]
    mov al, 0x08
    mov byte [attr], WHITE
    call screen_putc
    jmp .eoi
.shift_on:
    mov byte [shift_state], 1
    jmp .eoi
.shift_off:
    mov byte [shift_state], 0
.eoi:
    mov al, 0x20
    out 0x20, al
    popa
    iret

disk_irq_handler:
    pusha
    mov dx, ATA_STATUS
    in al, dx
    mov edi, disk_kbuf
    mov dx, ATA_DATA
    mov ecx, 256
    cld
    rep insw
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
; kread (eax=sektor -> disk_kbuf)
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

kread:
    push ebx
    push ecx
    push edx
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

; ============================================================================
; minix_locate / load_program
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
    cmp al, 0x21                 ; <= Space (null/space/control) -> Name-Ende
    jb .d
    cmp al, '&'                  ; & -> Name-Ende
    je .d
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
    movzx eax, word [disk_kbuf + 14]
    shl eax, 1
    call kread
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

; load_program: fname_buf gesetzt, edi = Ziel. eax=1 ok / 0 nicht gefunden.
load_program:
    mov [io_dst], edi
    call minix_locate
    test eax, eax
    jz .nf
    mov dword [io_idx], 0
    mov eax, [saved_size]
    mov [io_rem], eax
.l:
    mov eax, [io_rem]
    test eax, eax
    jz .ok
    mov eax, [io_idx]
    cmp eax, 7
    jae .ok
    mov ebx, [io_idx]
    mov eax, [saved_zones + ebx*4]
    test eax, eax
    jz .ok
    shl eax, 1
    call kread
    mov esi, disk_kbuf
    mov edi, [io_dst]
    mov ecx, 128
    cld
    rep movsd
    mov ebx, [io_idx]
    mov eax, [saved_zones + ebx*4]
    shl eax, 1
    inc eax
    call kread
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
    jbe .ok
    sub eax, 1024
    mov [io_rem], eax
    jmp .l
.ok:
    mov eax, 1
    ret
.nf:
    xor eax, eax
    ret

; ============================================================================
; Syscalls
; ============================================================================
syscall_dispatch:
    pusha
    cmp eax, SYS_WRITE
    je do_write
    cmp eax, SYS_READ
    je do_read
    cmp eax, SYS_EXEC
    je do_exec
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

do_read:
    mov eax, WAIT_KBD
    call block
    movzx edx, byte [line_len]
    cmp edx, ecx
    jbe .ok
    mov edx, ecx
.ok:
    mov esi, line_buffer
    mov edi, ebx
    mov ecx, edx
    push edx
    cld
    rep movsb
    pop edx
    mov byte [line_len], 0
    mov [esp + 28], edx
    jmp syscall_dispatch.ret

; ---- exec(ebx=name, ecx=len, edx=bg) -> 0/-1 ------------------------------
do_exec:
    mov [exec_bg], edx                  ; Hintergrund-Flag merken (0/1)
    mov [exec_cmdline], ebx             ; cmdline-Zeiger + Laenge merken
    mov [exec_cmdlen], ecx
    call copy_name
    ; freien Slot suchen (1..NPROC-1)
    mov ecx, 1
.fs:
    mov eax, ecx
    imul eax, eax, PCB_SIZE
    cmp dword [proc_table + eax + 0], ST_UNUSED
    je .got
    inc ecx
    cmp ecx, NPROC
    jb .fs
    mov dword [esp + 28], -1
    jmp syscall_dispatch.ret
.got:
    mov [exec_slot], ecx
    ; Programm laden -> CODE[slot]
    mov eax, ecx
    imul eax, eax, 0x10000
    add eax, CODE_BASE
    mov edi, eax
    call load_program
    test eax, eax
    jz .nf
    ; cmdline in die Args-Page ARGS[slot] = CODE_BASE + slot*0x10000 + 0x3000
    mov eax, [exec_slot]
    imul eax, eax, 0x10000
    add eax, CODE_BASE + 0x3000
    mov edi, eax
    mov esi, [exec_cmdline]
    mov ecx, [exec_cmdlen]
    cmp ecx, 255
    jbe .clok
    mov ecx, 255
.clok:
    cld
    rep movsb
    mov byte [edi], 0                   ; null-terminieren
    ; PCB[slot] aufsetzen
    mov ecx, [exec_slot]
    mov edi, KSTACK_BASE                ; KSTACK[slot] = BASE - slot*0x1000
    mov eax, ecx
    shl eax, 12
    sub edi, eax
    push edi                            ; kstack_top merken
    mov eax, USER_VIRT
    mov ebx, USTACK_VIRT
    call build_kstack                   ; -> eax=saved_esp (edi=kstack_top)
    pop edi                             ; kstack_top
    mov esi, [exec_slot]
    imul esi, esi, PCB_SIZE
    mov [proc_table + esi + 4], eax     ; saved_esp
    mov [proc_table + esi + 8], edi     ; kstack_top
    mov eax, [exec_slot]
    imul eax, eax, 0x2000
    add eax, PD_BASE
    mov [proc_table + esi + 12], eax    ; page_dir
    mov dword [proc_table + esi + 0], ST_READY
    ; Hintergrund? -> NICHT warten, sofort zum Prompt zurueck
    cmp dword [exec_bg], 0
    jne .bg
    ; Foreground: auf Kind-exit warten
    mov eax, WAIT_CHILD
    call block
.bg:
    mov dword [esp + 28], 0
    jmp syscall_dispatch.ret
.nf:
    mov dword [esp + 28], -1
    jmp syscall_dispatch.ret

do_exit:
    mov eax, [current]
    imul eax, eax, PCB_SIZE
    mov dword [proc_table + eax + 0], ST_UNUSED
    mov eax, WAIT_CHILD
    call wakeup
    call schedule
    jmp resume_current

; ============================================================================
; setup_paging: kernel_pt + NPROC Adressraeume (Schleife)
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

    xor esi, esi                        ; Slot-Index
.slot:
    ; UPT[slot] = PD_BASE + slot*0x2000 + 0x1000
    mov eax, esi
    imul eax, eax, 0x2000
    add eax, PD_BASE + 0x1000
    mov [tmp_upt], eax
    mov edi, eax
    call clear_page
    ; UPT[0] = CODE[slot] | 7 ; UPT[1] = STACK[slot] | 7
    mov eax, esi
    imul eax, eax, 0x10000
    add eax, CODE_BASE
    or  eax, 0x007
    mov ebx, [tmp_upt]
    mov [ebx + 0], eax
    mov eax, esi
    imul eax, eax, 0x10000
    add eax, CODE_BASE + 0x1000
    or  eax, 0x007
    mov [ebx + 4], eax
    ; UPT[3] = ARGS[slot] | 7  (virt 0x803000 -> Args-Page)
    mov eax, esi
    imul eax, eax, 0x10000
    add eax, CODE_BASE + 0x3000
    or  eax, 0x007
    mov [ebx + 12], eax
    ; PD[slot] = PD_BASE + slot*0x2000
    mov eax, esi
    imul eax, eax, 0x2000
    add eax, PD_BASE
    mov [tmp_pd], eax
    mov edi, eax
    call clear_page
    mov ebx, [tmp_pd]
    mov dword [ebx + 0], KERNEL_PT | 0x003
    mov eax, [tmp_upt]
    or  eax, 0x007
    mov [ebx + 8], eax                  ; PDE[2] -> UPT
    inc esi
    cmp esi, NPROC
    jb .slot
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
    call scroll
    mov edx, ROWB * 24
.s:
    mov [cursor], edx
    pop edx
    pop ebx
    pop eax
    ret

scroll:
    push eax
    push ecx
    push esi
    push edi
    cld
    mov esi, VGA + ROWB
    mov edi, VGA
    mov ecx, (ROWB * 24) / 4
    rep movsd
    mov edi, VGA + ROWB * 24
    mov ecx, ROWB / 4
    xor eax, eax
    rep stosd
    pop edi
    pop esi
    pop ecx
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
    mov eax, kbd_handler
    mov word [idt + 0x21*8 + 0], ax
    mov word [idt + 0x21*8 + 2], 0x08
    mov byte [idt + 0x21*8 + 4], 0x00
    mov byte [idt + 0x21*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x21*8 + 6], ax
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
scancode_to_ascii:
    db 0, 0, '1','2','3','4','5','6','7','8','9','0','-','=', 0x08, 0x09
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 0x0D, 0, 'a','s'
    db 'd','f','g','h','j','k','l', 0x3B, 0x27, 0x60, 0, 0x5C, 'z','x','c','v'
    db 'b','n','m', 0x2C, '.', '/', 0, '*', 0, ' '

; Shift-Variante (US-Layout): Symbole + Grossbuchstaben. & liegt auf Shift+7.
scancode_to_ascii_shift:
    db 0, 0, '!','@','#','$','%','^','&','*','(',')','_','+', 0x08, 0x09
    db 'Q','W','E','R','T','Y','U','I','O','P','{','}', 0x0D, 0, 'A','S'
    db 'D','F','G','H','J','K','L',':','"','~', 0, '|','Z','X','C','V'
    db 'B','N','M','<','>','?', 0, '*', 0, ' '

attr               db WHITE
cursor             dd 0
current            dd 0
shift_state        db 0
line_len           db 0
line_buffer        times 128 db 0
inode_table_sector dd 0
found_inode        dd 0
saved_size         dd 0
saved_zones        times 7 dd 0
io_dst             dd 0
io_rem             dd 0
io_idx             dd 0
exec_slot          dd 0
exec_bg            dd 0
exec_cmdline       dd 0
exec_cmdlen        dd 0
fname_buf          times 16 db 0
tmp_upt            dd 0
tmp_pd             dd 0
proc_table         times NPROC*PCB_SIZE db 0

align 16
shell_image:
    incbin "shell.bin"
shell_image_end:

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
