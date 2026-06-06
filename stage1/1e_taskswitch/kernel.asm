; ============================================================================
; 1e kernel.asm  --  Hardware-Task-Switching: Linus' erstes Programm
; ----------------------------------------------------------------------------
; Zwei Tasks laufen "gleichzeitig": Task A schreibt 'A', Task B schreibt 'B'.
; Der Timer-Interrupt (1d) schaltet bei jedem Tick per 386-Hardware-Task-
; Switching zwischen ihnen um. Ergebnis: abwechselnde Bloecke aus A und B.
;
; Das TSS (Task State Segment) ist eine 104-Byte-Struktur mit dem kompletten
; CPU-Zustand einer Task. Ein "jmp" auf einen TSS-Selektor laesst die CPU den
; aktuellen Zustand ins alte TSS sichern und den neuen aus dem Ziel-TSS laden.
; Die CPU erledigt das Umschalten also selbst -- das ist der "Hardware"-Teil.
;
; GDT-Selektoren in diesem Schritt:
;   0x08 Code   0x10 Daten   0x18 TSS-main   0x20 TSS-A   0x28 TSS-B
; (Die 0x20 als GDT-Selektor hat nichts mit dem Timer-VEKTOR 0x20 in der IDT
;  zu tun -- GDT und IDT sind getrennte Tabellen.)
; ============================================================================

bits 32
org  0x10000

VGA          equ 0xB8000
STACK_MAIN   equ 0x90000        ; Stacks liegen im freien RAM (nicht im Binary)
STACK_A      equ 0x80000
STACK_B      equ 0x70000
DELAY        equ 0x00300000     ; Bremse pro Zeichen, damit man die Bloecke sieht

kernel_start:
    ; ---- TSS-Basisadressen in die GDT-Deskriptoren patchen ----------------
    ; Die Adressen stehen erst zur Laufzeit als Zahl fest; NASM kann sie im
    ; bin-Format nicht in den Deskriptor bit-zerlegen. Also tun wir es hier.
    mov ebx, tss_main
    mov edi, gdt_tss_main
    call set_tss_base
    mov ebx, tss_a
    mov edi, gdt_tss_a
    call set_tss_base
    mov ebx, tss_b
    mov edi, gdt_tss_b
    call set_tss_base

    ; ---- eigene, vollstaendige GDT laden (mit den TSS-Eintraegen) ----------
    lgdt [gdt_descriptor]
    jmp 0x08:.reload_cs         ; Far Jump laedt CS aus der neuen GDT
.reload_cs:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, STACK_MAIN

    mov esi, msg_status         ; Statuszeile oben
    mov edi, 0
    call print_string

    call pic_remap              ; IRQs -> 0x20..0x2F (wie 1d)
    call idt_setup              ; Timer-Vektor 0x20 -> timer_handler
    lidt [idt_descriptor]

    mov al, 0xFE                ; nur IRQ0 (Timer) zulassen
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    ; ---- Task-Register auf das main-TSS setzen ----------------------------
    ; Beim ersten Task-Switch braucht die CPU ein TSS, in das sie den aktuellen
    ; (Kernel-)Zustand sichern kann. Das ist tss_main -- danach nie mehr genutzt.
    mov ax, 0x18
    ltr ax

    mov byte [current], 0       ; Task A laeuft als erste

    ; ---- manueller erster Task-Switch zu Task A ---------------------------
    ; Interrupts sind hier noch aus (cli aus boot.asm). Task A startet mit
    ; EFLAGS=0x202 aus seinem TSS, d.h. IF=1 -> ab dann feuert der Timer.
    jmp 0x20:0                  ; Hardware-Switch zu TSS-A

.never:
    hlt                         ; wird nie erreicht
    jmp .never

; ============================================================================
; Task A und Task B
; Beide schreiben ihr Zeichen ueber putchar an die gemeinsame Cursor-Position
; und bremsen dann kurz. Der Timer schaltet mitten in der Schleife um.
; ============================================================================
task_a:
.loop:
    mov al, 'A'
    mov ah, 0x0A                ; hellgruen
    call putchar
    mov ecx, DELAY
.delay:
    dec ecx
    jnz .delay
    jmp .loop

task_b:
.loop:
    mov al, 'B'
    mov ah, 0x0F               ; weiss
    call putchar
    mov ecx, DELAY
.delay:
    dec ecx
    jnz .delay
    jmp .loop

; ----------------------------------------------------------------------------
; putchar: al = Zeichen, ah = Attribut. Schreibt an [cursor], rueckt vor,
; wickelt am Schirmende auf Zeile 2 zurueck.
; ----------------------------------------------------------------------------
putchar:
    push edi
    mov edi, [cursor]
    mov [VGA + edi], al
    mov [VGA + edi + 1], ah
    add edi, 2
    cmp edi, 80*25*2           ; Schirmende (80x25, 2 Byte/Zelle)?
    jb .store
    mov edi, 80*2*2            ; ja: zurueck auf Zeile 2
.store:
    mov [cursor], edi
    pop edi
    ret

; ============================================================================
; Timer-Handler: schaltet bei jedem Tick zur jeweils anderen Task.
; pusha/popa sichern die Register der unterbrochenen Task, damit der Handler
; sie nicht verfaelscht (EOI nutzt al!). Der far jmp loest den Hardware-Switch
; aus; beim spaeteren Zurueckswitchen laeuft der Handler ab .done weiter.
; ============================================================================
timer_handler:
    pusha
    mov al, 0x20               ; EOI an den Master-PIC
    out 0x20, al
    cmp byte [current], 0
    je .to_b
    ; current == 1 (B lief) -> zu Task A
    mov byte [current], 0
    jmp 0x20:0                 ; Hardware-Switch zu TSS-A
    jmp .done
.to_b:
    mov byte [current], 1
    jmp 0x28:0                 ; Hardware-Switch zu TSS-B
.done:
    popa
    iret

; ----------------------------------------------------------------------------
; PIC umprogrammieren (identisch zu 1d)
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; IDT-Eintrag fuer Vektor 0x20 (Timer) -> timer_handler (Interrupt-Gate)
; ----------------------------------------------------------------------------
idt_setup:
    mov eax, timer_handler
    mov word [idt + 0x20*8 + 0], ax
    mov word [idt + 0x20*8 + 2], 0x08
    mov byte [idt + 0x20*8 + 4], 0x00
    mov byte [idt + 0x20*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x20*8 + 6], ax
    ret

; ----------------------------------------------------------------------------
; set_tss_base: ebx = TSS-Adresse, edi = Adresse des GDT-Deskriptors.
; Verteilt die 32-Bit-Basis auf die drei Basis-Felder des Deskriptors.
; ----------------------------------------------------------------------------
set_tss_base:
    mov [edi + 2], bx          ; Basis 0..15
    shr ebx, 16
    mov [edi + 4], bl          ; Basis 16..23
    mov [edi + 7], bh          ; Basis 24..31
    ret

; ----------------------------------------------------------------------------
; print_string: esi = 0-terminiert, edi = VGA-Offset, Attribut weiss
; ----------------------------------------------------------------------------
print_string:
    push eax
.next:
    lodsb
    test al, al
    jz .done
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], 0x0F
    add edi, 2
    jmp .next
.done:
    pop eax
    ret

; ============================================================================
; Daten
; ============================================================================
msg_status db '1e: Task A (gruen) + Task B (weiss), umgeschaltet vom Timer', 0
current    db 0                ; 0 = Task A laeuft, 1 = Task B
cursor     dd 80*2*2          ; Schreibposition, Start: Zeile 2

; ============================================================================
; TSS-Strukturen (je 104 Byte). Vorbelegt: EIP, EFLAGS, ESP, Segment-Selektoren.
; ============================================================================
%macro DEFINE_TSS 3            ; %1=label %2=entry-EIP %3=stack-top
align 4
%1:
    dd 0                       ; 0x00 LINK
    dd 0                       ; 0x04 ESP0
    dd 0                       ; 0x08 SS0
    dd 0, 0, 0, 0              ; 0x0C ESP1/SS1/ESP2/SS2
    dd 0                       ; 0x1C CR3 (kein Paging)
    dd %2                      ; 0x20 EIP  (Einsprungpunkt der Task)
    dd 0x202                   ; 0x24 EFLAGS (IF=1 -> Interrupts an)
    dd 0, 0, 0, 0             ; 0x28 EAX/ECX/EDX/EBX
    dd %3                      ; 0x38 ESP
    dd 0, 0, 0               ; 0x3C EBP/ESI/EDI
    dd 0x10                    ; 0x48 ES
    dd 0x08                    ; 0x4C CS
    dd 0x10                    ; 0x50 SS
    dd 0x10                    ; 0x54 DS
    dd 0x10                    ; 0x58 FS
    dd 0x10                    ; 0x5C GS
    dd 0                       ; 0x60 LDT
    dd 0                       ; 0x64 trap/iomap
%endmacro

DEFINE_TSS tss_main, 0, 0       ; nur Save-Ziel fuer den ersten Switch
DEFINE_TSS tss_a, task_a, STACK_A
DEFINE_TSS tss_b, task_b, STACK_B

; ============================================================================
; GDT mit Code, Daten und drei TSS-Deskriptoren
; ============================================================================
%macro TSS_DESC 0             ; 8-Byte-Deskriptor, Typ 0x89; Basis = 0 (Laufzeit-Patch)
    dw 0x67                    ; Limit = 103
    dw 0x0000                  ; Basis 0..15  (set_tss_base fuellt das)
    db 0x00                    ; Basis 16..23
    db 0x89                    ; present, 32-bit TSS (available)
    db 0x00                    ; Granularitaet/Limit-high = 0
    db 0x00                    ; Basis 24..31
%endmacro

align 8
gdt_start:
    dq 0                       ; 0x00 Null
    ; 0x08 Code
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10011010b
    db 11001111b
    db 0x00
    ; 0x10 Daten
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 10010010b
    db 11001111b
    db 0x00
gdt_tss_main:  TSS_DESC        ; 0x18
gdt_tss_a:     TSS_DESC        ; 0x20
gdt_tss_b:     TSS_DESC        ; 0x28
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; ----------------------------------------------------------------------------
; IDT: 256 Eintraege (nur Vektor 0x20 wird gefuellt)
; ----------------------------------------------------------------------------
align 8
idt:
    times 256*8 db 0
idt_end:

idt_descriptor:
    dw idt_end - idt - 1
    dd idt
