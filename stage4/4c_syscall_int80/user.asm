; ============================================================================
; 4c user.asm  --  Erste echte Syscall-Anfrage aus Ring 3
; ----------------------------------------------------------------------------
; Wir machen jetzt einen Syscall. Konvention (wie Linus' Linux 1991):
;     eax = Syscall-Nummer
;     ebx, ecx, edx, esi, edi = Argumente
;
; Der Trigger ist `int 0x80`. Die CPU wechselt automatisch nach Ring 0
; (Kernel) und ruft den IDT-Handler 0x80. Damit Ring 3 das ueberhaupt darf,
; muss der IDT-Eintrag DPL=3 haben -- darum kuemmert sich der Kernel.
;
; Wir geben 42 als Nummer, plus zwei willkuerliche Argumente. Der Kernel-
; Handler druckt die Werte zur Verifikation.
; ============================================================================

bits 32
org  0x40000

USER_DATA equ 0x23
VGA       equ 0xB8000
YELLOW    equ 0x0E
ROWB      equ 80 * 2

user_entry:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; ---- Vor dem Syscall ------------------------------------------------
    mov esi, msg_before
    mov edi, ROWB * 7
    call print_user

    ; ---- SYSCALL --------------------------------------------------------
    mov eax, 42                  ; Nummer
    mov ebx, 0xCAFE              ; Arg 1
    mov ecx, 0xBABE              ; Arg 2
    int 0x80                     ; Wechsel nach Ring 0 -> Handler -> Rueckkehr

    ; ---- Nach dem Syscall: erscheint nur, wenn der Handler iret macht ---
    mov esi, msg_after
    mov edi, ROWB * 8
    call print_user

.hang:
    jmp .hang

; ----------------------------------------------------------------------------
; print_user: esi = String, edi = VGA-Offset (gelb)
; ----------------------------------------------------------------------------
print_user:
    push eax
.next:
    lodsb
    test al, al
    jz .done
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], YELLOW
    add edi, 2
    jmp .next
.done:
    pop eax
    ret

msg_before db 'User: rufe int 0x80 mit eax=42, ebx=CAFE, ecx=BABE ...', 0
msg_after  db 'User: ... zurueck aus dem Syscall! (iret hat geklappt)', 0
