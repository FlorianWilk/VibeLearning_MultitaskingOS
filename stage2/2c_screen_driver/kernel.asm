; ============================================================================
; 2c kernel.asm  --  Bildschirm-Treiber, sauber vom Tastatur-Treiber getrennt
; ----------------------------------------------------------------------------
; AENDERUNG zu 2b:
;   kbd_handler schreibt NICHT mehr selbst nach VGA. Er uebersetzt nur noch
;   (Scancode -> ASCII) und ruft screen_putc(al) auf. Der Bildschirm-Treiber
;   ist die EINZIGE Stelle, die 0xB8000 und den Cursor anfasst.
;
;   screen_putc interpretiert ASCII:
;     0x0D Enter      -> Cursor auf Anfang der naechsten Zeile
;     0x08 Backspace  -> Cursor zurueck, dort Space schreiben
;     >=0x20 printable -> Zeichen schreiben, Cursor vor
;     anderes (Tab, ...) -> ignorieren
;   Erreicht der Cursor das Schirmende, wird der Inhalt um eine Zeile
;   nach oben gescrollt (Statuszeile in Zeile 0 bleibt stehen).
;
; Damit haetten wir das Treiber-Prinzip auf der einfachsten Stufe: Trennung
; nach Verantwortung. Der Bildschirm-Treiber waere austauschbar (z.B. spaeter
; ein serieller statt VGA), ohne dass die Tastatur etwas merkt.
; ============================================================================

bits 32
org  0x10000

VGA    equ 0xB8000
WHITE  equ 0x0F
COLS   equ 80
ROWS   equ 25
ROWB   equ COLS * 2        ; Bytes pro Zeile
SCREEN equ ROWB * ROWS

kernel_start:
    mov esp, 0x90000

    mov esi, msg_status
    mov edi, 0
    call print_string

    call pic_remap
    call idt_setup
    lidt [idt_descriptor]

.flush:                    ; Tastatur-Puffer leeren (siehe 2b)
    in al, 0x64
    test al, 1
    jz .flushed
    in al, 0x60
    jmp .flush
.flushed:

    mov al, 0xFD           ; nur IRQ1 (Tastatur) frei
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al

    sti
.idle:
    hlt
    jmp .idle

; ============================================================================
; Tastatur-Treiber: Scancode lesen, uebersetzen, an Bildschirm-Treiber geben
; ============================================================================
kbd_handler:
    pusha
    in al, 0x60
    test al, 0x80              ; break-Code? -> ignorieren
    jnz .eoi
    cmp al, 0x39
    ja .eoi
    movzx ebx, al
    mov al, [scancode_to_ascii + ebx]
    test al, al                ; unbelegt in der Tabelle?
    jz .eoi
    call screen_putc           ; <-- der Aufruf an den Bildschirm-Treiber
.eoi:
    mov al, 0x20
    out 0x20, al
    popa
    iret

; ============================================================================
; Bildschirm-Treiber
; ============================================================================
; screen_putc: al = ASCII-Zeichen. Interpretiert Enter/BS, schreibt, scrollt.
; ----------------------------------------------------------------------------
screen_putc:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    cmp al, 0x0D               ; Enter?
    je .enter
    cmp al, 0x08               ; Backspace?
    je .bksp
    cmp al, 0x20               ; nicht druckbar -> ignorieren
    jb .done

    ; ---- normales Zeichen schreiben + Cursor vor ----
    mov edi, [cursor]
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], WHITE
    add edi, 2
    jmp .check_wrap

.enter:
    ; Cursor auf Anfang der naechsten Zeile: cursor -= (cursor mod ROWB); += ROWB
    mov eax, [cursor]
    xor edx, edx
    mov ecx, ROWB
    div ecx                   ; edx = cursor mod ROWB
    mov edi, [cursor]
    sub edi, edx              ; Zeilenanfang
    add edi, ROWB             ; naechste Zeile
    jmp .check_wrap

.bksp:
    mov edi, [cursor]
    cmp edi, ROWB             ; nicht in/ueber die Statuszeile loeschen
    jbe .done
    sub edi, 2
    mov byte [VGA + edi], ' '
    mov byte [VGA + edi + 1], WHITE
    mov [cursor], edi
    jmp .done

.check_wrap:
    cmp edi, SCREEN           ; ueber das Schirmende hinaus?
    jb .store
    call scroll_up
    mov edi, ROWB * (ROWS - 1) ; Cursor auf Anfang der letzten Zeile
.store:
    mov [cursor], edi
.done:
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ----------------------------------------------------------------------------
; scroll_up: Inhalt der Zeilen 2..24 eine Zeile nach oben kopieren,
;            letzte Zeile leeren. Zeile 0 (Statuszeile) bleibt stehen.
; ----------------------------------------------------------------------------
scroll_up:
    push eax
    push ecx
    push esi
    push edi
    cld
    mov esi, VGA + ROWB * 2      ; Quelle: Zeile 2
    mov edi, VGA + ROWB * 1      ; Ziel:   Zeile 1
    mov ecx, (ROWB * (ROWS - 2)) / 4
    rep movsd                    ; 23 Zeilen hochschieben
    mov edi, VGA + ROWB * (ROWS - 1)  ; letzte Zeile leeren
    mov ecx, ROWB / 4
    xor eax, eax
    rep stosd
    pop edi
    pop esi
    pop ecx
    pop eax
    ret

; ----------------------------------------------------------------------------
; PIC / IDT (Vektor 0x21) / print_string  -- identisch zu 2b
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
    mov eax, kbd_handler
    mov word [idt + 0x21*8 + 0], ax
    mov word [idt + 0x21*8 + 2], 0x08
    mov byte [idt + 0x21*8 + 4], 0x00
    mov byte [idt + 0x21*8 + 5], 0x8E
    shr eax, 16
    mov word [idt + 0x21*8 + 6], ax
    ret

print_string:
    push eax
.next:
    lodsb
    test al, al
    jz .done
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], WHITE
    add edi, 2
    jmp .next
.done:
    pop eax
    ret

; ============================================================================
; Daten / Scancode-Tabelle (wie 2b)
; ============================================================================
scancode_to_ascii:
    db 0, 0, '1','2','3','4','5','6','7','8','9','0','-','=', 0x08, 0x09
    db 'q','w','e','r','t','y','u','i','o','p','[',']', 0x0D, 0, 'a','s'
    db 'd','f','g','h','j','k','l', 0x3B, 0x27, 0x60, 0, 0x5C, 'z','x','c','v'
    db 'b','n','m', 0x2C, '.', '/', 0, '*', 0, ' '

msg_status db '2c terminal -- Enter = neue Zeile, Backspace = loeschen', 0
cursor     dd ROWB              ; Start: Zeile 1 (Zeile 0 = Statuszeile)

align 8
idt:
    times 256*8 db 0
idt_end:

idt_descriptor:
    dw idt_end - idt - 1
    dd idt
