; ============================================================================
; 8a kernel.asm  --  Kernel fuer die User-Shell (mit sys_read)
; ----------------------------------------------------------------------------
; Stellt die Umgebung fuer eine Ring-3-Shell bereit:
;   - Paging: die Shell laeuft isoliert bei virt 0x800000 (eigener Adressraum)
;   - Tastatur-IRQ fuellt einen Kernel-Zeilenpuffer (mit Echo + Backspace)
;   - Syscalls:  1=exit  3=read(buf,max)  4=write(buf,len)
;
; sys_read ist der neue, interessante Syscall: er BLOCKIERT (sti + hlt-Schleife),
; bis der Tastatur-Handler eine ganze Zeile gesammelt und Enter gesehen hat,
; und kopiert sie dann in den User-Puffer. Ein klassischer blockierender Syscall.
;
; Kein Timer/Scheduler in 8a -- die Shell ist der einzige Prozess.
; ============================================================================

bits 32
org  0x10000

VGA          equ 0xB8000
WHITE        equ 0x0F
GREEN        equ 0x0A
COLS         equ 80
ROWB         equ COLS * 2
SCREEN       equ ROWB * 25

BOOT_STACK   equ 0x90000
SHELL_KSTACK equ 0x9F000

KERNEL_PT    equ 0x101000
PD_SHELL     equ 0x102000
USER_PT      equ 0x104000
CODE_SHELL   equ 0x200000           ; physischer Frame fuer den Shell-Code
STACK_SHELL  equ 0x201000           ; physischer Frame fuer den User-Stack

USER_VIRT    equ 0x800000           ; virtuelle Adresse (org der shell.asm)
USTACK_VIRT  equ 0x802000

SYS_EXIT     equ 1
SYS_READ     equ 3
SYS_WRITE    equ 4

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

    ; ---- Shell-Code an physischen Frame kopieren -----------------------
    mov esi, shell_image
    mov edi, CODE_SHELL
    mov ecx, shell_image_end - shell_image
    cld
    rep movsb

    ; ---- Paging einschalten --------------------------------------------
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
; setup_paging: kernel_pt (identity 4 MB), user_pt (0x800000/0x801000), pd
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
    mov dword [USER_PT + 0*4], CODE_SHELL  | 0x007
    mov dword [USER_PT + 1*4], STACK_SHELL | 0x007

    mov edi, PD_SHELL
    call clear_page
    mov dword [PD_SHELL + 0*4], KERNEL_PT | 0x003     ; identity
    mov dword [PD_SHELL + 2*4], USER_PT   | 0x007     ; 0x800000-Region
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
; Tastatur-Handler (IRQ1): sammelt eine Zeile, echot live, Enter -> line_ready
; ============================================================================
kbd_handler:
    pusha
    cmp byte [line_ready], 1       ; vorige Zeile noch nicht abgeholt? ignorieren
    je .eoi
    in al, 0x60
    test al, 0x80                  ; break-Code?
    jnz .eoi
    cmp al, 0x39
    ja .eoi
    movzx ebx, al
    mov al, [scancode_to_ascii + ebx]
    test al, al
    jz .eoi
    cmp al, 0x0D                   ; Enter?
    je .enter
    cmp al, 0x08                   ; Backspace?
    je .bs
    movzx ecx, byte [line_len]     ; normales Zeichen anhaengen
    cmp ecx, 127
    jae .eoi
    mov [line_buffer + ecx], al
    inc byte [line_len]
    call screen_putc               ; live-Echo
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
; Syscall-Dispatcher (int 0x80): pusha, dann eax = Nummer
;   Rueckgabewert wird in den gesicherten eax-Slot [esp+28] geschrieben.
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

; ---- write(ebx=fd, ecx=buf, edx=len) -> screen ----------------------------
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

; ---- read(ebx=buf, ecx=maxlen) -> eax=len (blockiert bis Enter) -----------
do_read:
    sti                            ; Interrupts AN, damit die Tastatur feuert
.wait:
    hlt
    cmp byte [line_ready], 0
    je .wait
    cli
    movzx edx, byte [line_len]     ; tatsaechliche Laenge
    cmp edx, ecx                   ; auf maxlen begrenzen
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
    mov [esp + 28], edx            ; return-Wert (Laenge) -> User-eax
    jmp syscall_dispatch.ret

; ---- exit(ebx=code): in 8a haelt das System an ----------------------------
do_exit:
    cli
    mov esi, msg_halt
    call screen_puts
.dead:
    hlt
    jmp .dead

; ============================================================================
; screen_putc (al) -- mit Newline, Backspace, Wraparound (von 2c)
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
    mov word [VGA + edx], 0x0F20    ; Space
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

; scroll_up: Zeilen 1..24 hoch, letzte leeren
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
    ; 0x21 Tastatur, Interrupt Gate DPL=0
    mov eax, kbd_handler
    mov word [idt + 0x21*8 + 0], ax
    mov word [idt + 0x21*8 + 2], 0x08
    mov byte [idt + 0x21*8 + 4], 0x00
    mov byte [idt + 0x21*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x21*8 + 6], ax
    ; 0x80 Syscall, Interrupt Gate DPL=3
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
msg_halt   db 0x0A, '[shell hat exit gerufen -- system haelt]', 0

scancode_to_ascii:
    db 0, 0, '1','2','3','4','5','6','7','8','9','0','-','=', 0x08, 0x09
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 0x0D, 0, 'a','s'
    db 'd','f','g','h','j','k','l', 0x3B, 0x27, 0x60, 0, 0x5C, 'z','x','c','v'
    db 'b','n','m', 0x2C, '.', '/', 0, '*', 0, ' '

cursor     dd 0
line_len   db 0
line_ready db 0
line_buffer times 128 db 0

align 16
shell_image:
    incbin "shell.bin"
shell_image_end:

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
