; ============================================================================
; 1d boot.asm  --  Bootsektor + Kernel-Nachlader
; ----------------------------------------------------------------------------
; Ab jetzt wird der Code groesser als 512 Byte (die IDT allein ist 2 KB). Der
; Bootsektor macht daher nur noch zwei Dinge:
;   1. den Kernel von der Floppy nachladen (BIOS int 0x13, noch im Real Mode)
;   2. in den Protected Mode wechseln und in den Kernel springen
; Genau diese Trennung hatte auch Linus: "bootsect" laedt "system".
;
; VERGLEICH zu 1c: Der Protected-Mode-Teil (A20, GDT, PE-Bit, Far Jump) ist
; identisch. NEU ist nur der Disk-Load davor und der Sprung in den Kernel.
; ============================================================================

bits 16
org  0x7C00

KERNEL_LOAD_SEG equ 0x1000      ; Real-Mode-Segment 0x1000 -> phys. 0x10000
KERNEL_ENTRY    equ 0x10000     ; lineare Adresse im Protected Mode
KERNEL_SECTORS  equ 17          ; so viele 512B-Sektoren laden (passt auf 1 Track)

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00              ; kleiner Real-Mode-Stack unter dem Bootcode

    ; ---- Kernel laden: Sektoren 2.. von Floppy nach ES:BX = 0x1000:0x0000 ---
    mov ax, KERNEL_LOAD_SEG
    mov es, ax
    xor bx, bx
    mov ah, 0x02               ; BIOS: Sektoren lesen
    mov al, KERNEL_SECTORS
    mov ch, 0                  ; Zylinder 0
    mov cl, 2                  ; ab Sektor 2 (Sektor 1 = dieser Bootsektor)
    mov dh, 0                  ; Kopf 0
    ; DL = Boot-Laufwerk, vom BIOS gesetzt -- nicht anfassen
    int 0x13
    jc  disk_error            ; Carry-Flag gesetzt = Lesefehler

    ; ---- Protected Mode (wie in 1c) ----
    in  al, 0x92               ; A20-Gate
    or  al, 2
    out 0x92, al
    lgdt [gdt_descriptor]      ; GDT laden
    mov eax, cr0              ; PE-Bit setzen
    or  eax, 1
    mov cr0, eax
    jmp 0x08:pm_entry          ; Far Jump in 32-bit

disk_error:
    mov ax, 0xB800             ; rotes 'E' oben links, dann anhalten
    mov es, ax
    mov word [es:0], 0x4F45
.die:
    hlt
    jmp .die

; ----------------------------------------------------------------------------
bits 32
pm_entry:
    mov ax, 0x10               ; Datensegmente -> Daten-Selektor
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000
    jmp 0x08:KERNEL_ENTRY      ; in den nachgeladenen Kernel springen

; ============================================================================
; Minimal-GDT (Null / Code / Daten) -- identisch zu 1c
; ============================================================================
gdt_start:
    dq 0
gdt_code:                      ; 0x08
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 11001111b
    db 0x00
gdt_data:                      ; 0x10
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
