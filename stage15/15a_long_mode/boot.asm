; ============================================================================
; 15a -- "Wechsel in den Long Mode" (64-bit)
; ----------------------------------------------------------------------------
; Bis Stage 14 lief alles im 32-bit Protected Mode -- Linus' 386-Welt von 1991.
; Der naechste Schritt der echten Hardware-Geschichte: AMD64 (2003), 64-bit.
;
; Anders als der Sprung Real -> Protected (1c) braucht Long Mode ZWINGEND Paging,
; BEVOR der erste 64-bit-Befehl laeuft. Die Reihenfolge ist daher:
;   1. A20-Gate oeffnen
;   2. 4-Level-Pagetables bauen (PML4 -> PDPT -> PD), erste 2 MB identity-mappen
;   3. CR3 = PML4 ; CR4.PAE = 1
;   4. EFER.LME = 1   (Long Mode Enable, MSR 0xC0000080)
;   5. CR0: PE und PG zugleich  -> CPU geht in Long Mode (Compatibility)
;   6. Far Jump in einen Code-Deskriptor mit L-Bit  -> echter 64-bit-Modus
;
; Beweis: 64-bit-Code, der die Register r8/r9 benutzt -- die gibt es im 32-bit-
; Modus gar nicht. Erscheint Text am Schirm, laufen wir wirklich in 64-bit.
; ============================================================================

bits 16
org  0x7C00

PML4 equ 0x1000
PDPT equ 0x2000
PD   equ 0x3000

start:
    cli                         ; ohne IDT wuerde jeder Interrupt sofort faulten
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; ---- 1. A20-Gate (Adressleitung 20) freischalten ------------------------
    in  al, 0x92
    or  al, 2
    out 0x92, al

    ; ---- 2. Pagetables bauen ------------------------------------------------
    ; Erst die drei Tabellen-Seiten (0x1000..0x3FFF) auf 0 setzen -- RAM ist
    ; nicht garantiert leer, und gesetzte "Present"-Bits in Resten waeren fatal.
    cld
    mov di, PML4
    xor eax, eax
    mov cx, 0x0C00              ; 3 Seiten * 1024 dwords
    rep stosd

    ; PML4[0] -> PDPT, PDPT[0] -> PD  (je present + writable)
    mov dword [PML4], PDPT | 0x3
    mov dword [PDPT], PD   | 0x3
    ; PD[0]: eine 2-MB-Grosspage (PS-Bit) bei phys 0 -> identity-map 0..2 MB
    ; (deckt Code @0x7C00, Pagetables und VGA @0xB8000 ab)
    mov dword [PD], 0x00000083   ; present | write | PS(0x80)

    ; ---- 3. CR3 + PAE -------------------------------------------------------
    mov eax, PML4
    mov cr3, eax
    mov eax, cr4
    or  eax, 0x20              ; CR4.PAE
    mov cr4, eax

    ; ---- 4. EFER.LME setzen (Long Mode Enable) ------------------------------
    mov ecx, 0xC0000080        ; IA32_EFER
    rdmsr
    or  eax, 0x100             ; LME (Bit 8)
    wrmsr

    ; ---- 5. GDT laden, dann PE+PG zugleich ----------------------------------
    lgdt [gdt_descriptor]
    mov eax, cr0
    or  eax, 0x80000001        ; PG (Bit 31) | PE (Bit 0)
    mov cr0, eax

    ; ---- 6. Far Jump in 64-bit-Code (Deskriptor mit L-Bit) ------------------
    jmp 0x08:long_start

; ----------------------------------------------------------------------------
bits 64
long_start:
    mov ax, 0x10               ; Daten-Selektoren (in 64-bit weitgehend flach)
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0x90000

    ; Beweis: r8/r9 existieren NUR in Long Mode. Wir schreiben msg ueber sie.
    mov r8, msg
    mov r9, 0xB8000
.print:
    mov al, [r8]
    test al, al
    jz .done
    mov ah, 0x1F              ; weiss auf blau
    mov [r9], ax
    inc r8
    add r9, 2
    jmp .print
.done:
    hlt
    jmp .done

msg db "Long Mode aktiv -- 64-bit, r8/r9 in Benutzung", 0

; ============================================================================
; GDT -- im Long Mode minimal: Null + 64-bit-Code (L-Bit!) + Daten.
; Basis/Limit werden im 64-bit-Modus ignoriert; entscheidend ist nur das L-Bit
; im Code-Deskriptor, das die CPU in den echten 64-bit-Modus schaltet.
; ============================================================================
gdt_start:
    dq 0                       ; Null-Deskriptor
gdt_code:                      ; 0x08 -- 64-bit Code
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b               ; present, ring0, code, exec/read
    db 10101111b               ; G=1, D=0, L=1 (Long!), limit hi
    db 0x00
gdt_data:                      ; 0x10 -- Daten
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b               ; present, ring0, data, read/write
    db 11001111b
    db 0x00
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

times 510-($-$$) db 0
dw 0xAA55
