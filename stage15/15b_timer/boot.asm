; ============================================================================
; 15b boot.asm  --  Long-Mode-Bootloader + Kernel-Nachlader
; ----------------------------------------------------------------------------
; Wie 1d (Real Mode laedt den Kernel von Floppy), aber statt nach Protected
; Mode geht es nach LONG MODE (64-bit) -- das Setup aus 15a. Danach Sprung in
; den nachgeladenen 64-bit-Kernel bei 0x10000.
; ============================================================================

bits 16
org  0x7C00

KERNEL_LOAD_SEG equ 0x1000      ; 0x1000:0 -> phys 0x10000
KERNEL_ENTRY    equ 0x10000
KERNEL_SECTORS  equ 17
PML4 equ 0x1000
PDPT equ 0x2000
PD   equ 0x3000

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; ---- Kernel laden: Sektoren 2.. nach 0x1000:0 (BIOS, Real Mode) ---------
    mov ax, KERNEL_LOAD_SEG
    mov es, ax
    xor bx, bx
    mov ah, 0x02
    mov al, KERNEL_SECTORS
    mov ch, 0
    mov cl, 2
    mov dh, 0
    int 0x13
    jc  disk_error
    xor ax, ax
    mov es, ax                  ; es zurueck auf 0 fuer die Pagetable-Writes

    ; ---- A20 ----------------------------------------------------------------
    in  al, 0x92
    or  al, 2
    out 0x92, al

    ; ---- 4-Level-Pagetables (identity 0..2 MB via 2-MB-Page) ----------------
    cld
    mov di, PML4
    xor eax, eax
    mov cx, 0x0C00
    rep stosd
    mov dword [PML4], PDPT | 0x3
    mov dword [PDPT], PD   | 0x3
    mov dword [PD], 0x00000083

    ; ---- CR3, PAE, EFER.LME, PG+PE ------------------------------------------
    mov eax, PML4
    mov cr3, eax
    mov eax, cr4
    or  eax, 0x20
    mov cr4, eax
    mov ecx, 0xC0000080
    rdmsr
    or  eax, 0x100
    wrmsr
    lgdt [gdt_descriptor]
    mov eax, cr0
    or  eax, 0x80000001
    mov cr0, eax
    jmp 0x08:long_entry

disk_error:
    mov ax, 0xB800
    mov es, ax
    mov word [es:0], 0x4F45     ; rotes 'E'
.die:
    hlt
    jmp .die

; ----------------------------------------------------------------------------
bits 64
long_entry:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x90000
    mov rax, KERNEL_ENTRY
    jmp rax                     ; in den 64-bit-Kernel

; ============================================================================
; GDT: Null + 64-bit-Code (L-Bit) + Daten
; ============================================================================
gdt_start:
    dq 0
gdt_code:                       ; 0x08
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 10101111b               ; G=1, L=1 (Long)
    db 0x00
gdt_data:                       ; 0x10
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b
    db 11001111b
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

times 510-($-$$) db 0
dw 0xAA55
