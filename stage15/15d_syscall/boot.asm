; ============================================================================
; 15d boot.asm  --  Long Mode + GDT mit User-Segmenten (fuer Ring 3 / syscall)
; ----------------------------------------------------------------------------
; Wie 15b, aber zwei Erweiterungen fuer den syscall/sysret-Schritt:
;   - GDT hat jetzt 5 Eintraege in der von SYSCALL/SYSRET verlangten Reihenfolge:
;       0x08 Kernel-Code, 0x10 Kernel-Daten, 0x18 User-Daten, 0x20 User-Code.
;     (SYSCALL nimmt CS=STAR[47:32], SS=+8; SYSRET nimmt CS=STAR[63:48]+16,
;      SS=STAR[63:48]+8 -- daher diese feste Anordnung.)
;   - Pagetables mit User-Bit (Bit 2) auf ALLEN Ebenen, damit Ring-3-Code die
;     identity-gemappten Seiten ueberhaupt betreten darf.
; ============================================================================

bits 16
org  0x7C00

KERNEL_LOAD_SEG equ 0x1000
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
    mov es, ax

    in  al, 0x92
    or  al, 2
    out 0x92, al

    cld
    mov di, PML4
    xor eax, eax
    mov cx, 0x0C00
    rep stosd
    ; User-Bit (0x4) auf allen Ebenen -> Ring 3 darf die Seiten betreten
    mov dword [PML4], PDPT | 0x7
    mov dword [PDPT], PD   | 0x7
    mov dword [PD], 0x00000087   ; present | write | user | PS

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
    mov word [es:0], 0x4F45
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
    jmp rax

; ============================================================================
; GDT -- Reihenfolge ist fuer SYSCALL/SYSRET vorgeschrieben.
; ============================================================================
gdt_start:
    dq 0                         ; 0x00 Null
    dq 0x00AF9A000000FFFF        ; 0x08 Kernel-Code (L=1, DPL=0)
    dq 0x00CF92000000FFFF        ; 0x10 Kernel-Daten (DPL=0)
    dq 0x00CFF2000000FFFF        ; 0x18 User-Daten   (DPL=3)
    dq 0x00AFFA000000FFFF        ; 0x20 User-Code    (L=1, DPL=3)
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

times 510-($-$$) db 0
dw 0xAA55
