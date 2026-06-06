; ============================================================================
; 1f kernel.asm  --  SOFTWARE-Task-Switching (Variante zu 1e)
; ----------------------------------------------------------------------------
; Gleiche Demo wie 1e_taskswitch (Task A schreibt 'A', Task B 'B', Timer-
; getrieben), ABER ohne die 386-Spezialitaet TSS. Wir sichern und laden den
; Kontext von Hand mit normalen Befehlen (pusha/popa) -- so wie Linux es seit
; jeher macht und wie es auf JEDER CPU funktioniert.
;
; Die Kernidee:
;   Ein "Kontext" ist nur ein Satz Register + ein Stack. Wenn ein Interrupt
;   kommt, liegen EIP/CS/EFLAGS schon auf dem Stack der laufenden Task. Wir
;   legen mit pusha die GP-Register obendrauf -- jetzt steht der KOMPLETTE
;   Kontext auf diesem Stack. Merken wir uns nur dessen ESP, koennen wir durch
;   simples Umschalten von ESP die Task wechseln. popa + iret laedt den
;   Kontext der anderen Task und springt hinein.
;
; VERGLEICH zu 1e_taskswitch (Hardware): Dort gab es TSS-Strukturen, TSS-
; Deskriptoren in einer erweiterten GDT, ltr und einen far jmp auf einen TSS-
; Selektor. Hier faellt das ALLES weg -- wir nutzen sogar die GDT aus boot.asm
; unveraendert weiter. Der Switch ist nur: ESP merken, ESP laden.
; ============================================================================

bits 32
org  0x10000

VGA        equ 0xB8000
STACK_MAIN equ 0x90000
STACK_A    equ 0x80000
STACK_B    equ 0x70000
DELAY      equ 0x00300000

kernel_start:
    mov esp, STACK_MAIN        ; GDT/Segmente kommen unveraendert aus boot.asm

    mov esi, msg_status
    mov edi, 0
    call print_string

    call pic_remap
    call idt_setup
    lidt [idt_descriptor]

    mov al, 0xFE               ; nur IRQ0 (Timer) zulassen
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    ; ---- fuer beide Tasks einen "wie unterbrochen" aussehenden Stack bauen --
    mov eax, task_a
    mov ebx, STACK_A
    call build_stack
    mov [saved_esp + 0], eax   ; gemerkter ESP von Task A

    mov eax, task_b
    mov ebx, STACK_B
    call build_stack
    mov [saved_esp + 4], eax   ; gemerkter ESP von Task B

    ; ---- Task A starten: ihren praeparierten Kontext laden ----------------
    mov dword [current], 0
    mov esp, [saved_esp + 0]
    popa                       ; GP-Register von A (alle 0)
    iret                       ; laedt EIP=task_a, CS, EFLAGS(IF=1) -> A laeuft

; ============================================================================
; Task A und Task B -- identisch zur Hardware-Variante
; ============================================================================
task_a:
.loop:
    mov al, 'A'
    mov ah, 0x0A               ; hellgruen
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

putchar:
    push edi
    mov edi, [cursor]
    mov [VGA + edi], al
    mov [VGA + edi + 1], ah
    add edi, 2
    cmp edi, 80*25*2
    jb .store
    mov edi, 80*2*2
.store:
    mov [cursor], edi
    pop edi
    ret

; ============================================================================
; Timer-Handler: DAS ist der Software-Task-Switch. Kein TSS, nur Stack-Umschalten.
; ============================================================================
timer_handler:
    pusha                      ; GP-Register der laufenden Task auf ihren Stack
    mov eax, [current]
    mov [saved_esp + eax*4], esp   ; aktuellen Stack-Zeiger merken (= Kontext)
    xor eax, 1                 ; zur anderen Task umschalten (0<->1)
    mov [current], eax
    mov esp, [saved_esp + eax*4]   ; Stack der neuen Task laden = Kontextwechsel
    mov al, 0x20               ; EOI an den PIC
    out 0x20, al
    popa                       ; GP-Register der neuen Task wiederherstellen
    iret                       ; EIP/CS/EFLAGS der neuen Task -> hineinspringen

; ----------------------------------------------------------------------------
; build_stack: legt auf einem frischen Stack einen Frame an, der so aussieht,
; als waere die Task gerade von einem Timer-Interrupt unterbrochen worden.
; Dadurch koennen popa + iret sie spaeter ganz normal "fortsetzen".
;   Eingang: eax = Einsprung-EIP, ebx = Stack-Top
;   Ausgang: eax = gemerkter ESP (Zeiger auf den Frame)
;
;   Stack-Layout (hohe -> niedrige Adresse), passend zu pusha/iret:
;     EFLAGS, CS, EIP        <- von iret geladen
;     EAX,ECX,EDX,EBX,ESP,EBP,ESI,EDI = 0   <- von popa geladen
; ----------------------------------------------------------------------------
build_stack:
    mov edx, ebx
    sub edx, 4
    mov dword [edx], 0x202     ; EFLAGS (IF=1 -> Interrupts an)
    sub edx, 4
    mov dword [edx], 0x08      ; CS (Code-Selektor aus boot.asm)
    sub edx, 4
    mov [edx], eax             ; EIP = Einsprungpunkt
    mov ecx, 8                 ; 8 Nuller fuer die pusha-Register
.zero:
    sub edx, 4
    mov dword [edx], 0
    loop .zero
    mov eax, edx               ; gemerkter ESP zeigt auf den untersten Eintrag
    ret

; ----------------------------------------------------------------------------
; PIC / IDT / print_string -- identisch zu 1d/1e
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

idt_setup:
    mov eax, timer_handler
    mov word [idt + 0x20*8 + 0], ax
    mov word [idt + 0x20*8 + 2], 0x08
    mov byte [idt + 0x20*8 + 4], 0x00
    mov byte [idt + 0x20*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x20*8 + 6], ax
    ret

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
msg_status db '1f (software switch): Task A (gruen) + Task B (weiss)', 0
current    dd 0               ; 0 = Task A, 1 = Task B
cursor     dd 80*2*2
saved_esp  dd 0, 0            ; gemerkter Stack-Zeiger je Task [A, B]

align 8
idt:
    times 256*8 db 0
idt_end:

idt_descriptor:
    dw idt_end - idt - 1
    dd idt
