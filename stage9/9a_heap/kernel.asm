; ============================================================================
; 9a kernel.asm  --  Heap (sys_sbrk) im User-Adressraum
; ----------------------------------------------------------------------------
; Erweitert den User-Adressraum um einen Heap-Bereich. Bisher hatte ein
; Programm nur Code- und Stack-Page; jetzt mappen wir zusaetzlich mehrere
; Heap-Pages bei virt 0x900000. sys_sbrk teilt davon Stueck fuer Stueck aus.
;
; (Vorgemappter Heap statt dynamischem Page-Mapping -- minimal. Das reicht fuer
;  den Compiler/VM spaeter; ein echter on-demand-Heap waere mehr Aufwand.)
;
; Syscalls:  1=exit  4=write(buf,len)  12=sbrk(inc)->alte brk
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
HEAP_FRAME0  equ 0x300000           ; 8 Heap-Frames: 0x300000..0x307000

USER_VIRT    equ 0x800000
USTACK_VIRT  equ 0x802000
HEAP_VIRT    equ 0x900000           ; Heap beginnt hier (virtuell)
HEAP_PAGES   equ 8

SYS_EXIT     equ 1
SYS_WRITE    equ 4
SYS_SBRK     equ 12

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
    mov dword [tss_main + 4], USER_KSTACK
    mov dword [tss_main + 8], 0x10
    mov ax, 0x28
    ltr ax

    call idt_setup
    lidt [idt_descriptor]

    ; ---- Code an seinen Frame kopieren ---------------------------------
    mov esi, user_image
    mov edi, CODE_FRAME
    mov ecx, user_image_end - user_image
    cld
    rep movsb

    ; ---- Paging + Heap einschalten -------------------------------------
    call setup_paging
    mov eax, PD_USER
    mov cr3, eax
    mov eax, cr0
    or  eax, 0x80000000
    mov cr0, eax

    ; brk initialisieren
    mov dword [brk], HEAP_VIRT

    ; ---- User starten --------------------------------------------------
    mov esp, USER_KSTACK
    push dword 0x23
    push dword USTACK_VIRT
    push dword 0x202
    push dword 0x1B
    push dword USER_VIRT
    iret

; ============================================================================
; setup_paging: kernel_pt (identity), user_pt (Code, Stack, Heap-Pages)
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

    mov edi, USER_PT
    call clear_page
    mov dword [USER_PT + 0*4], CODE_FRAME  | 0x007    ; 0x800000
    mov dword [USER_PT + 1*4], STACK_FRAME | 0x007    ; 0x801000

    ; Heap-Pages: virt 0x900000.. -> user_pt[256..]; phys HEAP_FRAME0..
    ; (0x900000 >> 12) & 0x3FF = 0x100 = 256
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
    mov dword [PD_USER + 2*4], USER_PT   | 0x007      ; deckt 0x800000-0xBFFFFF
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
; Syscall-Dispatcher
; ============================================================================
syscall_dispatch:
    pusha
    cmp eax, SYS_WRITE
    je do_write
    cmp eax, SYS_SBRK
    je do_sbrk
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

; sbrk(ebx=increment) -> eax = alte brk-Grenze
do_sbrk:
    mov eax, [brk]                 ; alte Grenze
    add ebx, eax
    mov [brk], ebx                 ; neue Grenze
    mov [esp + 28], eax            ; return alte Grenze
    jmp syscall_dispatch.ret

do_exit:
    cli
    mov esi, msg_halt
    call screen_puts
.dead:
    hlt
    jmp .dead

; ============================================================================
; screen_putc / screen_puts (mit Newline + Wrap)
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
; Daten
; ============================================================================
msg_halt db 0x0A, '[exit -- system haelt]', 0
cursor   dd 0
brk      dd 0

align 16
user_image:
    incbin "user.bin"
user_image_end:

; ============================================================================
; GDT + IDT + TSS
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
