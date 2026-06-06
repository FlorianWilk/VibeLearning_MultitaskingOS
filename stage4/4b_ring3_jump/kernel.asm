; ============================================================================
; 4b kernel.asm  --  Sprung nach Ring 3 mit dem iret-Trick
; ----------------------------------------------------------------------------
; AENDERUNG zu 4a: nach ltr kopieren wir das eingebettete user.bin nach
; USER_ENTRY und springen per iret hinein. Die CPU "kehrt zurueck" in einen
; Modus, in dem sie nie war.
;
; Der iret-Trick:
;   Normalerweise endet ein Interrupt-Handler mit iret und die CPU laedt
;   EIP/CS/EFLAGS/ESP/SS vom Stack. Wir bauen DIESEN Stack-Frame selbst und
;   fuehren iret aus -- die CPU merkt nicht, dass kein echter Interrupt war.
;
;   Stack vor iret (oben):
;     SS       = 0x23           (User-Daten | RPL=3)
;     ESP      = USER_STACK_TOP
;     EFLAGS   = 0x202          (IF=1 -> Interrupts an)
;     CS       = 0x1B           (User-Code | RPL=3)
;     EIP      = USER_ENTRY
;
;   Die CPU sieht "iret aus Ring 0 in einen Ring-3-Frame": switcht den Ring,
;   wechselt zugleich auf den User-Stack (nicht nur EIP/CS!), laedt EFLAGS.
; ============================================================================

bits 32
org  0x10000

VGA          equ 0xB8000
WHITE        equ 0x0F
YELLOW       equ 0x0E
COLS         equ 80
ROWB         equ COLS * 2
KERNEL_STACK equ 0x90000
USER_ENTRY   equ 0x40000           ; hierhin kopieren wir user.bin
USER_STACK   equ 0x80000           ; User-Stack-Top (waechst nach unten)

kernel_start:
    mov esp, KERNEL_STACK

    ; ---- GDT/TSS wie in 4a einrichten ----------------------------------
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
    mov dword [tss_main + 4], KERNEL_STACK
    mov dword [tss_main + 8], 0x10
    mov ax, 0x28
    ltr ax

    mov esi, msg_status
    mov edi, 0
    call print_string

    ; ---- User-Programm an USER_ENTRY kopieren --------------------------
    mov esi, user_image
    mov edi, USER_ENTRY
    mov ecx, user_image_end - user_image
    cld
    rep movsb

    mov esi, msg_jump
    mov edi, ROWB * 2
    call print_string

    ; ---- iret-Trick: Stack-Frame bauen, dann iret ----------------------
    push dword 0x23                ; SS  (User-Daten, RPL=3)
    push dword USER_STACK          ; ESP
    push dword 0x202               ; EFLAGS (IF=1, Reserved-Bit 1 = 1)
    push dword 0x1B                ; CS  (User-Code, RPL=3)
    push dword USER_ENTRY          ; EIP
    iret

    ; ---- Wird NIE erreicht ---------------------------------------------
.hang:
    hlt
    jmp .hang

; ============================================================================
; print_string mit \n-Unterstuetzung
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
msg_status db '4b: Kernel-Setup OK', 0
msg_jump   db 'Springe nach Ring 3 (iret-Trick) -> User-Programm uebernimmt:', 0

; ============================================================================
; Das eingebettete User-Programm. NASM legt die Bytes hier ab; rep movsb
; kopiert sie zur Laufzeit nach USER_ENTRY.
; ============================================================================
align 16
user_image:
    incbin "user.bin"
user_image_end:

; ============================================================================
; GDT, TSS  -- identisch zu 4a
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

align 4
tss_main:
    times 104 db 0
