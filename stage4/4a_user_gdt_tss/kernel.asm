; ============================================================================
; 4a kernel.asm  --  GDT erweitern + TSS einrichten (Vorbereitung Userspace)
; ----------------------------------------------------------------------------
; Bevor wir in 4b nach Ring 3 wechseln koennen, brauchen wir drei Dinge:
;
;   1) User-Segmente in der GDT (DPL=3 statt DPL=0)
;        0x18 User-Code  -- gleich wie Kernel-Code, aber DPL=3
;        0x20 User-Daten -- gleich wie Kernel-Daten, aber DPL=3
;
;   2) Ein TSS (Task State Segment) mit ESP0 und SS0.
;        Wenn ein User-Programm spaeter per IRQ oder int 0x80 in den Kernel
;        wechselt, holt sich die CPU AUTOMATISCH den Kernel-Stack aus dem TSS.
;        Ohne korrektes TSS -> beim ersten User->Kernel-Wechsel Triple-Fault.
;
;   3) ltr (Load Task Register): sagt der CPU, welches TSS gilt.
;
; Wir benutzen das TSS hier NICHT zum Hardware-Task-Switching (wie in 1e).
; Nur als Speicher fuer den Kernel-Stack-Pointer. Genau das Linux-Modell.
;
; Beweis dass alles ueberlebt: nach ltr erscheint die Statusmeldung. Bei
; einem Fehler waere stattdessen Reboot-Loop.
; ============================================================================

bits 32
org  0x10000

VGA          equ 0xB8000
WHITE        equ 0x0F
YELLOW       equ 0x0E
COLS         equ 80
ROWB         equ COLS * 2
KERNEL_STACK equ 0x90000

kernel_start:
    mov esp, KERNEL_STACK

    ; ---- TSS-Adresse in den TSS-Deskriptor patchen ----------------------
    ; NASM kann im bin-Format keine Label-Adresse zur Assemble-Zeit in einen
    ; Deskriptor zerlegen -- also tun wir es hier.
    mov ebx, tss_main
    mov edi, gdt_tss
    mov [edi + 2], bx           ; Basis 0..15
    shr ebx, 16
    mov [edi + 4], bl           ; Basis 16..23
    mov [edi + 7], bh           ; Basis 24..31

    ; ---- Neue GDT laden -------------------------------------------------
    lgdt [gdt_descriptor]

    ; Far Jump laedt CS aus der neuen GDT (Selektor ist 0x08, gleich wie zuvor).
    jmp 0x08:.cs_reloaded
.cs_reloaded:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; ---- TSS initialisieren ---------------------------------------------
    ; Wir brauchen nur ESP0 (Offset 4) und SS0 (Offset 8). Alles andere = 0.
    mov dword [tss_main + 4], KERNEL_STACK
    mov dword [tss_main + 8], 0x10        ; Kernel-Daten-Selektor

    ; ---- Task Register laden --------------------------------------------
    ; ltr akzeptiert nur einen TSS-Deskriptor mit Typ 0x89 (available).
    ; Nach ltr ist der Deskriptor 0x8B (busy) -- normal.
    mov ax, 0x28
    ltr ax

    ; ---- Wenn wir hier sind, hat ltr ueberlebt --------------------------
    mov esi, msg_status
    mov edi, 0
    call print_string

    mov esi, msg_gdt
    mov edi, ROWB * 2
    call print_string

.hang:
    hlt
    jmp .hang

; ============================================================================
; print_string  --  esi = null-terminiert, edi = VGA-Offset; \n = neue Zeile
; ============================================================================
print_string:
    push eax
    push edx
    push ebx
.next:
    lodsb
    test al, al
    jz .done
    cmp al, 10
    je .nl
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], WHITE
    add edi, 2
    jmp .next
.nl:
    mov eax, edi
    xor edx, edx
    mov ebx, ROWB
    div ebx
    inc eax
    mul ebx
    mov edi, eax
    jmp .next
.done:
    pop ebx
    pop edx
    pop eax
    ret

; ============================================================================
; Daten
; ============================================================================
msg_status db '4a: GDT erweitert, TSS geladen (ltr OK)', 0
msg_gdt:
    db 'GDT-Layout:', 10
    db '  0x00 NULL', 10
    db '  0x08 Kernel-Code  (DPL=0)', 10
    db '  0x10 Kernel-Daten (DPL=0)', 10
    db '  0x18 User-Code    (DPL=3)   <- NEU', 10
    db '  0x20 User-Daten   (DPL=3)   <- NEU', 10
    db '  0x28 TSS                    <- NEU', 0

; ============================================================================
; GDT mit User-Segmenten und TSS
; ============================================================================
align 8
gdt_start:
    dq 0                              ; 0x00 NULL

    ; 0x08 Kernel-Code (wie immer)
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b                       ; P=1 DPL=0 S=1 E=1 RW=1
    db 11001111b
    db 0x00

    ; 0x10 Kernel-Daten (wie immer)
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b                       ; P=1 DPL=0 S=1 E=0 RW=1
    db 11001111b
    db 0x00

    ; 0x18 User-Code (NEU)  -- identisch zu Kernel-Code, nur DPL=3
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 11111010b                       ; P=1 DPL=3 S=1 E=1 RW=1
    db 11001111b
    db 0x00

    ; 0x20 User-Daten (NEU) -- identisch zu Kernel-Daten, nur DPL=3
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 11110010b                       ; P=1 DPL=3 S=1 E=0 RW=1
    db 11001111b
    db 0x00

gdt_tss:                              ; 0x28 TSS-Deskriptor (NEU)
    dw 0x67                            ; Limit = 103 (TSS-Groesse - 1)
    dw 0x0000                          ; Basis 0..15  (Laufzeit-Patch)
    db 0x00                            ; Basis 16..23
    db 0x89                            ; P=1 DPL=0, 32-bit TSS (available)
    db 0x00                            ; Granularitaet/Limit-high = 0
    db 0x00                            ; Basis 24..31
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; ============================================================================
; TSS (104 Byte). Nur ESP0/SS0 gesetzt; alles andere 0.
; ============================================================================
align 4
tss_main:
    times 104 db 0
