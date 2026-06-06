; ============================================================================
; 7a kernel.asm  --  Paging einschalten
; ----------------------------------------------------------------------------
; Wir aktivieren die Speicher-Uebersetzung des 386. Ab jetzt sind Adressen im
; Code "virtuell" und werden von der Hardware ueber zwei Tabellen in physische
; Adressen uebersetzt.
;
; Aufbau:
;   - Page Directory (1024 Eintraege a 4 Byte) bei phys. 0x100000
;   - Page Table 0  -> identity-mappt die ersten 4 MB (0..0x3FFFFF)
;                      damit Kernel/Stacks/VGA an Ort und Stelle bleiben
;   - Page Table 2  -> EIN Eintrag: virtuelle 0x800000 -> physische 0xB8000(VGA)
;
;   Page Directory:
;     PDE[0] -> Page Table 0   (deckt virtuelle 0x000000..0x3FFFFF)
;     PDE[2] -> Page Table 2   (deckt virtuelle 0x800000..0xBFFFFF)
;
; Beweis: Wir schreiben einen Text einmal direkt nach 0xB8000 (identity) und
; einmal nach 0x800000. Letzteres landet physisch bei 0xB8000 -- also auf dem
; Bildschirm, obwohl die Adresse voellig woanders zeigt. Das IST Paging.
;
; Eintrags-Flags: Bit 0 = Present, Bit 1 = Read/Write -> 0x003.
; ============================================================================

bits 32
org  0x10000

VGA       equ 0xB8000
WHITE     equ 0x0F
YELLOW    equ 0x0E
GREEN     equ 0x0A
ROWB      equ 80 * 2

; Page-Strukturen im RAM ab 1 MB (liegen selbst in den identity-gemappten 4 MB)
PAGE_DIR  equ 0x100000
PT0       equ 0x101000          ; identity 0..4 MB
PT2       equ 0x102000          ; Alias fuer 0x800000

VGA_ALIAS equ 0x800000          ; virtuelle Adresse, die wir auf VGA mappen

kernel_start:
    mov esp, 0x90000

    ; ---- Page Table 0: identity-map 0..4 MB ----------------------------
    mov edi, PT0
    mov eax, 0x00000003          ; phys 0, Present|RW
    mov ecx, 1024
.fill0:
    mov [edi], eax
    add eax, 0x1000              ; naechster 4-KB-Frame
    add edi, 4
    loop .fill0

    ; ---- Page Table 2: nur Eintrag 0 -> VGA ----------------------------
    ; virtuelle 0x800000: Dir-Index = 2, Table-Index = 0, Offset = 0
    mov edi, PT2
    mov eax, VGA | 0x003         ; phys 0xB8000, Present|RW
    mov [edi], eax
    ; restliche Eintraege bleiben 0 (not present) -- fuer die Demo ok

    ; ---- Page Directory ------------------------------------------------
    ; erst alles auf 0 (not present)
    mov edi, PAGE_DIR
    xor eax, eax
    mov ecx, 1024
.clrpd:
    mov [edi], eax
    add edi, 4
    loop .clrpd
    ; PDE[0] -> PT0,  PDE[2] -> PT2
    mov dword [PAGE_DIR + 0*4], PT0 | 0x003
    mov dword [PAGE_DIR + 2*4], PT2 | 0x003

    ; ---- CR3 setzen + Paging einschalten -------------------------------
    mov eax, PAGE_DIR
    mov cr3, eax
    mov eax, cr0
    or  eax, 0x80000000          ; CR0.PG = Bit 31
    mov cr0, eax
    ; ab hier sind alle Adressen virtuell (aber identity, also unveraendert)

    ; ---- Beweis 1: normaler Zugriff auf 0xB8000 (identity) -------------
    mov esi, msg_ident
    mov edi, VGA + ROWB * 2
    mov ah, WHITE
    call print_at

    ; ---- Beweis 2: Zugriff auf virtuelle 0x800000 ----------------------
    ; Diese Adresse zeigt NICHT auf physisch 0x800000, sondern auf 0xB8000.
    ; Also erscheint der Text auf dem Schirm, eine Zeile tiefer.
    mov esi, msg_alias
    mov edi, VGA_ALIAS + ROWB * 4
    mov ah, GREEN
    call print_at

    ; Header
    mov esi, msg_status
    mov edi, VGA
    mov ah, YELLOW
    call print_at

.hang:
    hlt
    jmp .hang

; ============================================================================
; print_at: esi = String, edi = (virtuelle) Zieladresse, ah = Attribut
; ============================================================================
print_at:
    push eax
    push edi
.next:
    lodsb
    test al, al
    jz .done
    mov [edi], al
    mov [edi + 1], ah
    add edi, 2
    jmp .next
.done:
    pop edi
    pop eax
    ret

msg_status db '7a: Paging aktiv (CR0.PG=1)', 0
msg_ident  db 'Zeile via 0xB8000  (identity-gemappt)', 0
msg_alias  db 'Zeile via 0x800000 (auf VGA gemappt!) <- DAS ist Paging', 0
