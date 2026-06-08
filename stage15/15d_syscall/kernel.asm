; ============================================================================
; 15d kernel.asm  --  syscall / sysret (der moderne 64-bit-Syscall)
; ----------------------------------------------------------------------------
; Statt "int 0x80" (Stage 4) nutzt x86-64 die dedizierten Instruktionen
; SYSCALL / SYSRET -- deutlich schneller, weil kein IDT-Lookup noetig ist.
; Konfiguriert wird das ueber Model-Specific Registers (MSRs):
;   EFER.SCE   System Call Enable
;   STAR       Kernel- und User-Segment-Selektoren (feste GDT-Anordnung!)
;   LSTAR      64-bit-Adresse des Handlers
;   SFMASK     RFLAGS-Bits, die SYSCALL beim Eintritt loescht (hier: IF)
;
; Ablauf der Demo:
;   Kernel (Ring 0) -> iretq -> user_code (Ring 3) -> SYSCALL -> Handler
;   (Ring 0) druckt einen String -> SYSRET -> zurueck in Ring 3.
;
; SYSCALL rettet RIP nach RCX und RFLAGS nach R11; SYSRET stellt sie wieder her.
; Wichtig: SYSCALL laedt RSP NICHT um -- der Handler wechselt selbst auf den
; Kernel-Stack (sonst liefe Ring 0 auf dem User-Stack).
; ============================================================================

bits 64
org  0x10000

VGA        equ 0xB8000
USER_STACK equ 0x80000
KERN_STACK equ 0x90000

kernel_start:
    mov rsp, KERN_STACK

    mov rsi, msg_status
    xor rdi, rdi
    call print_string

    ; ---- MSRs konfigurieren -------------------------------------------------
    mov ecx, 0xC0000080        ; EFER: SCE setzen (LME bleibt vom Boot)
    rdmsr
    or  eax, 1
    wrmsr

    mov ecx, 0xC0000081        ; STAR: [63:48]=0x10 (SYSRET-Basis),
    mov edx, 0x00100008        ;       [47:32]=0x08 (SYSCALL-Basis)
    xor eax, eax
    wrmsr

    mov ecx, 0xC0000082        ; LSTAR = Handler-Adresse (64-bit)
    mov rax, syscall_handler
    mov rdx, rax
    shr rdx, 32
    wrmsr                      ; eax=low32, edx=high32

    mov ecx, 0xC0000084        ; SFMASK: IF loeschen bei SYSCALL-Eintritt
    mov eax, 0x200
    xor edx, edx
    wrmsr

    ; ---- Wechsel nach Ring 3 per iretq --------------------------------------
    push 0x18 | 3              ; SS  = User-Daten, RPL 3
    mov  rax, USER_STACK
    push rax                   ; RSP
    push 0x202                 ; RFLAGS (IF=1, reserviertes Bit 1)
    push 0x20 | 3             ; CS  = User-Code, RPL 3
    mov  rax, user_code
    push rax                   ; RIP
    iretq

; ----------------------------------------------------------------------------
; Ring 3: ruft den Print-Syscall (Nr 1) mit rsi = String.
; ----------------------------------------------------------------------------
user_code:
    mov rax, 1
    mov rsi, umsg
    syscall
    ; Wieder hier = SYSRET hat nach Ring 3 zurueckgekehrt. Beweis: Ring 3
    ; schreibt jetzt SELBST (die Seite ist user-beschreibbar gemappt).
    mov rsi, umsg2
    mov rdi, 480
    call print_string
.hang:
    jmp .hang

; ----------------------------------------------------------------------------
; SYSCALL-Handler (Ring 0). rax = Nummer, rsi = Argument.
; ----------------------------------------------------------------------------
syscall_handler:
    mov [saved_rsp], rsp       ; vom User-Stack auf den Kernel-Stack wechseln
    mov rsp, KERN_STACK
    push rcx                   ; RCX (Rueckkehr-RIP) + R11 (RFLAGS) retten,
    push r11                   ;   SYSRET braucht sie unveraendert
    ; Nr 1 = String aus rsi in Zeile 2 ausgeben
    mov rdi, 320
    call print_string
    pop r11
    pop rcx
    mov rsp, [saved_rsp]
    o64 sysret

; ----------------------------------------------------------------------------
print_string:
    push rax
.next:
    lodsb
    test al, al
    jz .done
    mov [VGA + rdi], al
    mov byte [VGA + rdi + 1], 0x0F
    add rdi, 2
    jmp .next
.done:
    pop rax
    ret

; ----------------------------------------------------------------------------
msg_status db '15d 64-bit syscall/sysret', 0
umsg       db 'Ring0-Handler: syscall empfangen', 0
umsg2      db 'Ring3 nach sysret: zurueck im Userspace', 0
saved_rsp  dq 0
