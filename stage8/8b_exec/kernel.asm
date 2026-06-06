; ============================================================================
; 8b kernel.asm  --  Kernel mit sys_exec: Shell startet Programme von Disk
; ----------------------------------------------------------------------------
; Vereint ALLES:
;   Etappe 2  Tastatur + Bildschirm   (sys_read / screen_putc)
;   Etappe 3  Disk + Minix-FS          (read_sector + load_program)
;   Etappe 4  Userspace + Syscalls     (Ring 3, int 0x80)
;   Etappe 7  Paging                   (Shell + Kind je eigener Adressraum)
;
; exec/exit als 2-Ebenen-Kontextwechsel:
;   sys_exec  laedt das Programm in den Kind-Adressraum (CODE_CHILD), merkt den
;             Shell-Kernel-Stack, wechselt CR3 + ESP0 auf das Kind, iret -> Kind.
;   sys_exit  stellt CR3/ESP0/Stack der Shell wieder her -> Shell laeuft hinter
;             ihrem exec() weiter.
;
; Shell und alle Programme liegen bei DERSELBEN virtuellen Adresse 0x800000,
; sind aber durch getrennte Page Directories voneinander isoliert.
;
; Syscalls:  1=exit  3=read(buf,max)  4=write(buf,len)  11=exec(name,len)
; ============================================================================

bits 32
org  0x10000

VGA          equ 0xB8000
WHITE        equ 0x0F
COLS         equ 80
ROWB         equ COLS * 2
SCREEN       equ ROWB * 25

BOOT_STACK   equ 0x90000
SHELL_KSTACK equ 0x9F000
CHILD_KSTACK equ 0x9D000

KERNEL_PT    equ 0x101000
PD_SHELL     equ 0x102000
PD_CHILD     equ 0x103000
USER_PT_SH   equ 0x104000
USER_PT_CH   equ 0x105000

CODE_SHELL   equ 0x200000
STACK_SHELL  equ 0x201000
CODE_CHILD   equ 0x202000
STACK_CHILD  equ 0x203000

USER_VIRT    equ 0x800000
USTACK_VIRT  equ 0x802000

SYS_EXIT     equ 1
SYS_READ     equ 3
SYS_WRITE    equ 4
SYS_EXEC     equ 11

; ATA-Ports
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

    ; ---- GDT/TSS -------------------------------------------------------
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
    mov dword [tss_main + 4], SHELL_KSTACK
    mov dword [tss_main + 8], 0x10
    mov ax, 0x28
    ltr ax

    ; ---- PIC: nur Tastatur (IRQ1) --------------------------------------
    call pic_remap
    mov al, 0xFD
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al
    call idt_setup
    lidt [idt_descriptor]

    ; ---- Shell-Code an ihren Frame kopieren ----------------------------
    mov esi, shell_image
    mov edi, CODE_SHELL
    mov ecx, shell_image_end - shell_image
    cld
    rep movsb

    ; ---- Paging einschalten (Shell-Adressraum) -------------------------
    call setup_paging
    mov eax, PD_SHELL
    mov cr3, eax
    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax

    ; ---- Shell in Ring 3 starten ---------------------------------------
    mov esp, SHELL_KSTACK
    push dword 0x23
    push dword USTACK_VIRT
    push dword 0x202
    push dword 0x1B
    push dword USER_VIRT
    iret

; ============================================================================
; setup_paging: kernel_pt (identity), je Adressraum user_pt + pd
; ============================================================================
setup_paging:
    ; kernel_pt: identity 0..4 MB
    mov edi, KERNEL_PT
    mov eax, 0x003
    mov ecx, 1024
.kmap:
    mov [edi], eax
    add eax, 0x1000
    add edi, 4
    loop .kmap

    ; Shell-Adressraum
    mov edi, USER_PT_SH
    call clear_page
    mov dword [USER_PT_SH + 0*4], CODE_SHELL  | 0x007
    mov dword [USER_PT_SH + 1*4], STACK_SHELL | 0x007
    mov edi, PD_SHELL
    call clear_page
    mov dword [PD_SHELL + 0*4], KERNEL_PT | 0x003
    mov dword [PD_SHELL + 2*4], USER_PT_SH | 0x007

    ; Kind-Adressraum (Code-Frame wird bei jedem exec neu befuellt)
    mov edi, USER_PT_CH
    call clear_page
    mov dword [USER_PT_CH + 0*4], CODE_CHILD  | 0x007
    mov dword [USER_PT_CH + 1*4], STACK_CHILD | 0x007
    mov edi, PD_CHILD
    call clear_page
    mov dword [PD_CHILD + 0*4], KERNEL_PT | 0x003
    mov dword [PD_CHILD + 2*4], USER_PT_CH | 0x007
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
; Tastatur-Handler (IRQ1)
; ============================================================================
kbd_handler:
    pusha
    cmp byte [line_ready], 1
    je .eoi
    in al, 0x60
    test al, 0x80
    jnz .eoi
    cmp al, 0x39
    ja .eoi
    movzx ebx, al
    mov al, [scancode_to_ascii + ebx]
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
    call screen_putc
    jmp .eoi
.enter:
    mov byte [line_ready], 1
    mov al, 0x0A
    call screen_putc
    jmp .eoi
.bs:
    cmp byte [line_len], 0
    je .eoi
    dec byte [line_len]
    mov al, 0x08
    call screen_putc
.eoi:
    mov al, 0x20
    out 0x20, al
    popa
    iret

; ============================================================================
; Syscall-Dispatcher (int 0x80)
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
    mov esi, ecx
    mov ecx, edx
.next:
    test ecx, ecx
    jz syscall_dispatch.ret
    lodsb
    call screen_putc
    dec ecx
    jmp .next

do_read:
    sti
.wait:
    hlt
    cmp byte [line_ready], 0
    je .wait
    cli
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
    mov byte [line_ready], 0
    mov [esp + 28], edx
    jmp syscall_dispatch.ret

; ---- exec(ebx=name, ecx=len) ----------------------------------------------
do_exec:
    mov esi, ebx                   ; User-Name-Zeiger
    mov ebp, ecx                   ; Laenge merken
    ; exec_name (16 Byte) nullen
    mov edi, exec_name
    mov ecx, 4
    xor eax, eax
    cld
    rep stosd
    ; min(len, 14) Bytes kopieren
    mov ecx, ebp
    cmp ecx, 14
    jbe .lc
    mov ecx, 14
.lc:
    mov edi, exec_name
    cld
    rep movsb                      ; esi(name) -> exec_name

    call load_program              ; -> CODE_CHILD; eax=1 ok / 0 nicht gefunden
    test eax, eax
    jz .notfound

    ; Shell pausieren, Kind starten
    mov [shell_saved_esp], esp     ; Shell-Kernel-Kontext merken
    mov dword [tss_main + 4], CHILD_KSTACK
    mov eax, PD_CHILD
    mov cr3, eax                   ; -> Kind-Adressraum
    mov esp, CHILD_KSTACK
    push dword 0x23
    push dword USTACK_VIRT
    push dword 0x202
    push dword 0x1B
    push dword USER_VIRT
    iret                           ; -> Kind, Ring 3, @ 0x800000

.notfound:
    mov dword [esp + 28], -1       ; eax = -1 an die Shell
    jmp syscall_dispatch.ret

; ---- exit(ebx=code): Kind beendet -> zurueck zur Shell --------------------
do_exit:
    cli
    mov dword [tss_main + 4], SHELL_KSTACK
    mov eax, PD_SHELL
    mov cr3, eax                   ; -> Shell-Adressraum
    mov esp, [shell_saved_esp]     ; Shell-Kernel-Kontext
    mov dword [esp + 28], 0        ; exec() liefert 0 (Erfolg)
    popa
    iret                           ; -> Shell, hinter ihrem exec()

; ============================================================================
; load_program: sucht exec_name im Minix-Root, laedt es nach CODE_CHILD.
;   Rueckgabe: eax = 1 gefunden+geladen, 0 nicht gefunden.
; ============================================================================
load_program:
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
    movzx eax, word [sector_buf + 14]      ; Root i_zone[0]
    shl eax, 1
    mov edi, sector_buf
    call read_sector

    mov esi, sector_buf
    mov edx, 32
.find:
    movzx eax, word [esi]
    test eax, eax
    jz .skip
    push esi
    push eax
    add esi, 2
    call name_matches
    pop eax
    pop esi
    je .found
.skip:
    add esi, 16
    dec edx
    jnz .find
    xor eax, eax
    ret

.found:
    push eax                                ; Inode-Nr
    mov eax, [inode_table_sector]
    mov edi, sector_buf
    call read_sector
    pop eax
    dec eax
    shl eax, 5
    lea esi, [sector_buf + eax]
    movzx eax, word [esi + 14]              ; i_zone[0]
    shl eax, 1                              ; -> Sektor
    mov edi, CODE_CHILD
    call read_sector
    inc eax
    add edi, 512
    call read_sector
    mov eax, 1
    ret

; name_matches: esi = Dir-Name (14 Byte), ZF=1 wenn == exec_name
name_matches:
    push esi
    push edi
    push ecx
    mov edi, exec_name
    mov ecx, 14
    cld
    repe cmpsb
    pop ecx
    pop edi
    pop esi
    ret

; ============================================================================
; read_sector (eax=LBA, edi=Puffer) -- wie Etappe 3
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
; screen_putc / screen_puts / scroll_up (wie 8a)
; ============================================================================
screen_putc:
    push eax
    push ebx
    push edx
    cmp al, 0x0A
    je .nl
    cmp al, 0x08
    je .bs
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
    jmp .wrap
.bs:
    mov edx, [cursor]
    cmp edx, 0
    je .done
    sub edx, 2
    mov word [VGA + edx], 0x0F20
    jmp .store
.wrap:
    cmp edx, SCREEN
    jb .store
    call scroll_up
    mov edx, ROWB * 24
.store:
    mov [cursor], edx
.done:
    pop edx
    pop ebx
    pop eax
    ret

scroll_up:
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

; ============================================================================
; pic_remap / idt_setup
; ============================================================================
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
    mov eax, kbd_handler
    mov word [idt + 0x21*8 + 0], ax
    mov word [idt + 0x21*8 + 2], 0x08
    mov byte [idt + 0x21*8 + 4], 0x00
    mov byte [idt + 0x21*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x21*8 + 6], ax
    mov eax, syscall_dispatch
    mov word [idt + 0x80*8 + 0], ax
    mov word [idt + 0x80*8 + 2], 0x08
    mov byte [idt + 0x80*8 + 4], 0x00
    mov byte [idt + 0x80*8 + 5], 0xEE
    shr eax, 16
    mov word [idt + 0x80*8 + 6], ax
    ret

; ============================================================================
; Daten
; ============================================================================
scancode_to_ascii:
    db 0, 0, '1','2','3','4','5','6','7','8','9','0','-','=', 0x08, 0x09
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 0x0D, 0, 'a','s'
    db 'd','f','g','h','j','k','l', 0x3B, 0x27, 0x60, 0, 0x5C, 'z','x','c','v'
    db 'b','n','m', 0x2C, '.', '/', 0, '*', 0, ' '

cursor             dd 0
line_len           db 0
line_ready         db 0
line_buffer        times 128 db 0
exec_name          times 16 db 0
shell_saved_esp    dd 0
inode_table_sector dd 0

align 16
shell_image:
    incbin "shell.bin"
shell_image_end:

; ============================================================================
; GDT + IDT + TSS + Sektorpuffer
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
