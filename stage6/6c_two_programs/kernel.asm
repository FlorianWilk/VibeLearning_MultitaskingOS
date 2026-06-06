; ============================================================================
; 6c kernel.asm  --  Scheduler fuer zwei GETRENNTE Programme
; ----------------------------------------------------------------------------
; AENDERUNG zu 6b: statt eines gemeinsamen Blobs mit zwei Einsprungpunkten
; (= Threads) laden wir jetzt zwei eigenstaendige Programme an getrennte
; Adressen:  proc_a.bin -> 0x40000,  proc_b.bin -> 0x50000.
; Jedes Programm hat eigenen Code + eigene Daten. Der Scheduler ist identisch.
;
; Das ist die Vereinigung von 1f (Software-Switch via ESP) und Etappe 4
; (Userspace). Der Unterschied zu 1f: die Tasks laufen in Ring 3, also muss
; bei jedem Switch zusaetzlich TSS.ESP0 auf den Kernel-Stack des neuen
; Prozesses zeigen (dorthin pusht die CPU beim naechsten IRQ/Syscall).
;
; Pro Prozess gibt es ZWEI Stacks:
;   - User-Stack  (Ring 3, fuer den Prozess-Code)
;   - Kernel-Stack(Ring 0, fuer IRQ/Syscall-Kontext dieses Prozesses)
;
; Beim Init bauen wir auf jedem Kernel-Stack einen "Fake"-Kontext, der so
; aussieht, als waere der Prozess gerade von einem Timer-IRQ aus Ring 3
; unterbrochen worden -- dann startet popa+iret ihn ganz normal.
;
; Non-preemptive Kernel: Timer (0x20) UND Syscall (0x80) sind Interrupt Gates
; (IF=0 im Handler). Waehrend eines Syscalls feuert also kein Timer -> der
; gesicherte Kontext beim Switch ist immer ein sauberer Ring-3-Kontext.
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
PROC_A_LOAD  equ 0x40000               ; proc_a.bin hierhin
PROC_B_LOAD  equ 0x50000               ; proc_b.bin hierhin

USTACK_A     equ 0x80000
USTACK_B     equ 0x70000
KSTACK_A     equ 0x9F000
KSTACK_B     equ 0x9D000

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
    mov dword [tss_main + 8], 0x10        ; SS0 = Kernel-Daten
    mov ax, 0x28
    ltr ax

    ; ---- PIC + IDT -----------------------------------------------------
    call pic_remap
    mov al, 0xFE                           ; nur Timer (IRQ0)
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al
    call idt_setup
    lidt [idt_descriptor]

    mov esi, msg_status
    call screen_puts

    ; ---- Programm A laden -> 0x40000 -----------------------------------
    mov esi, proc_a_image
    mov edi, PROC_A_LOAD
    mov ecx, proc_a_image_end - proc_a_image
    cld
    rep movsb

    ; ---- Programm B laden -> 0x50000 -----------------------------------
    mov esi, proc_b_image
    mov edi, PROC_B_LOAD
    mov ecx, proc_b_image_end - proc_b_image
    rep movsb

    ; ---- Fake-Kernel-Stack fuer Prozess 0 (proc_a) ---------------------
    mov eax, PROC_A_LOAD                    ; entry = Lade-Adresse (org passt)
    mov ebx, USTACK_A
    mov edi, KSTACK_A
    call build_kstack
    mov [saved_esp + 0], eax
    mov dword [kstack_top + 0], KSTACK_A

    ; ---- Fake-Kernel-Stack fuer Prozess 1 (proc_b) ---------------------
    mov eax, PROC_B_LOAD
    mov ebx, USTACK_B
    mov edi, KSTACK_B
    call build_kstack
    mov [saved_esp + 1*4], eax
    mov dword [kstack_top + 1*4], KSTACK_B

    ; ---- Prozess 0 starten ---------------------------------------------
    mov dword [current], 0
    mov dword [tss_main + 4], KSTACK_A      ; ESP0 fuer ersten IRQ/Syscall
    mov esp, [saved_esp + 0]
    popa
    iret                                    ; -> Ring 3, proc_a

; ============================================================================
; build_kstack  --  legt einen "wie unterbrochen"-Kontext auf einen Kernel-Stack
;   eax = User-Einsprung (EIP), ebx = User-Stack-Top, edi = Kernel-Stack-Top
;   Rueckgabe: eax = gesicherter Kernel-ESP (zeigt auf den pusha-Bereich)
;
;   Layout (hohe -> niedrige Adresse):  iret-Frame (Ring 3) + pusha-Bereich
;     SS=0x23, ESP=user, EFLAGS=0x202, CS=0x1B, EIP=entry, dann 8x 0 (pusha)
; ============================================================================
build_kstack:
    mov edx, edi
    sub edx, 4
    mov dword [edx], 0x23                   ; SS  (User-Daten | RPL 3)
    sub edx, 4
    mov [edx], ebx                          ; ESP (User-Stack)
    sub edx, 4
    mov dword [edx], 0x202                  ; EFLAGS (IF=1)
    sub edx, 4
    mov dword [edx], 0x1B                   ; CS  (User-Code | RPL 3)
    sub edx, 4
    mov [edx], eax                          ; EIP (Einsprung)
    mov ecx, 8                              ; pusha-Bereich (edi,esi,...,eax)
.zero:
    sub edx, 4
    mov dword [edx], 0
    loop .zero
    mov eax, edx                            ; gesicherter ESP
    ret

; ============================================================================
; timer_handler (IRQ0 / 0x20)  --  DER preemptive Task-Switch
;   Kontext: CPU kam aus Ring 3, hat auf den Kernel-Stack des laufenden
;   Prozesses (ESP0) den iret-Frame gepusht. pusha legt die GP-Regs dazu.
;   Dann: ESP sichern, Prozess wechseln, ESP + ESP0 des neuen laden, popa, iret.
; ============================================================================
timer_handler:
    pusha
    mov eax, [current]
    mov [saved_esp + eax*4], esp           ; Kontext des Alten sichern (= ESP)

    mov al, 0x20                           ; EOI an den PIC
    out 0x20, al

    mov eax, [current]                     ; current neu laden (al war EOI)
    xor eax, 1                             ; round-robin: 0<->1
    mov [current], eax

    mov esp, [saved_esp + eax*4]           ; Kontext des Neuen laden (= ESP)
    mov ebx, [kstack_top + eax*4]          ; TSS.ESP0 = sein Kernel-Stack-Top
    mov [tss_main + 4], ebx                ;   (fuer den NAECHSTEN Eintritt)
    popa
    iret                                    ; -> Ring 3, anderer Prozess

; ============================================================================
; syscall_dispatch (int 0x80)  --  nur sys_write (Nr 4) in 6b
; ============================================================================
syscall_dispatch:
    pusha
    cmp eax, 4
    je .write
    popa
    iret
.write:
    mov byte [attr], YELLOW
    mov esi, ecx                           ; buf
    mov ecx, edx                           ; len
.next:
    test ecx, ecx
    jz .done
    lodsb
    call screen_putc
    dec ecx
    jmp .next
.done:
    mov byte [attr], WHITE
    popa
    iret

; ============================================================================
; screen_putc (al)  --  mit Zeilenumbruch und Wraparound (sonst laeuft der
; Cursor ueber den VGA-Speicher hinaus und ueberschreibt RAM!)
; ============================================================================
screen_putc:
    push eax
    push edx
    mov ah, [attr]
    mov edx, [cursor]
    mov [VGA + edx], ax
    add edx, 2
    cmp edx, SCREEN
    jb .ok
    mov edx, ROWB * 2                      ; wrap zurueck auf Zeile 2
.ok:
    mov [cursor], edx
    pop edx
    pop eax
    ret

screen_puts:
    push eax
.l:
    lodsb
    test al, al
    jz .d
    cmp al, 10
    je .nl
    call screen_putc
    jmp .l
.nl:
    push edx
    mov eax, [cursor]
    xor edx, edx
    push ebx
    mov ebx, ROWB
    div ebx
    inc eax
    mul ebx
    mov [cursor], eax
    pop ebx
    pop edx
    jmp .l
.d:
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
    ; Vektor 0x20 = Timer, Interrupt Gate DPL=0 (0x8E)
    mov eax, timer_handler
    mov word [idt + 0x20*8 + 0], ax
    mov word [idt + 0x20*8 + 2], 0x08
    mov byte [idt + 0x20*8 + 4], 0x00
    mov byte [idt + 0x20*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x20*8 + 6], ax
    ; Vektor 0x80 = Syscall, Interrupt Gate DPL=3 (0xEE) -- aus Ring 3 rufbar,
    ; aber IF=0 im Handler (non-preemptive kernel)
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
msg_status db '6c: zwei GETRENNTE Programme (proc_a/proc_b), preemptiv:', 10, 10, 0

attr       db WHITE
cursor     dd ROWB * 2                     ; Start: Zeile 2
current    dd 0
saved_esp  dd 0, 0                         ; gesicherter Kernel-ESP je Prozess
kstack_top dd 0, 0                         ; Kernel-Stack-Top je Prozess

align 16
proc_a_image:
    incbin "proc_a.bin"
proc_a_image_end:

align 16
proc_b_image:
    incbin "proc_b.bin"
proc_b_image_end:

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
