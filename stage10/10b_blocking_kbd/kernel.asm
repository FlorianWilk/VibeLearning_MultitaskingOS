; ============================================================================
; 10b kernel.asm  --  Blockierende Tastatur (echte Sleep/Wakeup)
; ----------------------------------------------------------------------------
; sys_read legt den Prozess schlafen (block), statt zu pollen. Der Scheduler
; laeuft derweil andere Prozesse. Der Tastatur-IRQ weckt den Schlaefer bei Enter.
;
; Einheitlicher Kontext-Wechsel ueber resume_current (popa + iret):
;   - vom Timer pausierter User-Prozess: gespeichertes CS = Ring 3 -> iret 5 Werte
;   - von block() pausierter Kernel-Pfad: wir bauen CS = Ring 0 -> iret 3 Werte
;   iret waehlt anhand des gespeicherten CS automatisch das Richtige.
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
WAIT_KBD     equ 1

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
SYS_READ     equ 3
SYS_WRITE    equ 4

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
    mov al, 0xFC                       ; Timer (IRQ0) + Tastatur (IRQ1) frei
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al
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

; ============================================================================
; resume_current: laedt Kontext von current, popa, iret (einheitlicher Wieder-
; eintritt fuer timer- UND block-pausierte Prozesse)
; ============================================================================
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

; ============================================================================
; Timer-Handler -> praeemptiver Switch
; ============================================================================
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
; Tastatur-Handler (IRQ1): Zeile sammeln, bei Enter wakeup(KBD)
; ============================================================================
kbd_handler:
    pusha
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
    cmp ecx, 63
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
    call wakeup                    ; wartenden Leser wecken
    jmp .eoi
.bs:
    cmp byte [line_len], 0
    je .eoi
    dec byte [line_len]
    mov al, 0x08
    mov byte [attr], WHITE
    call screen_putc
.eoi:
    mov al, 0x20
    out 0x20, al
    popa
    iret

; ============================================================================
; block(eax = reason): aktuellen Prozess schlafen legen, weiterschalten.
;   Baut einen Ring-0-iret-Frame, damit resume_current ihn spaeter ueber
;   popa+iret an .resume fortsetzt -> ret zum Aufrufer (do_read).
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
    mov [proc_table + ebx + 16], eax       ; wait_reason
    call schedule
    jmp resume_current
.resume:
    ret

; ============================================================================
; wakeup(eax = reason): alle BLOCKED-Prozesse mit diesem reason -> READY
; ============================================================================
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

; ============================================================================
; schedule: naechsten READY waehlen (round-robin), current+RUNNING setzen.
; (In 10b ist proc_b immer READY -> Idle-Zweig wird nie erreicht.)
; ============================================================================
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
    ; niemand READY: warten bis ein IRQ jemanden weckt
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
; Syscall: write / read / exit
; ============================================================================
syscall_dispatch:
    pusha
    cmp eax, SYS_WRITE
    je do_write
    cmp eax, SYS_READ
    je do_read
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

; read(ebx=buf, ecx=maxlen) -> eax=len ; blockiert bis Enter
do_read:
    mov eax, WAIT_KBD
    call block                          ; schlafen bis Tastatur-IRQ weckt
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
    mov [esp + 28], edx                  ; return len
    jmp syscall_dispatch.ret

do_exit:
    cli
.dead:
    hlt
    jmp .dead

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
msg_status db '10b: proc_b zaehlt, proc_a wartet blockierend auf Tastatur:', 0x0A, 0x0A, 0

scancode_to_ascii:
    db 0, 0, '1','2','3','4','5','6','7','8','9','0','-','=', 0x08, 0x09
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 0x0D, 0, 'a','s'
    db 'd','f','g','h','j','k','l', 0x3B, 0x27, 0x60, 0, 0x5C, 'z','x','c','v'
    db 'b','n','m', 0x2C, '.', '/', 0, '*', 0, ' '

attr        db WHITE
cursor      dd ROWB * 2
current     dd 0
line_len    db 0
line_buffer times 64 db 0
proc_table  times NPROC*PCB_SIZE db 0

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
