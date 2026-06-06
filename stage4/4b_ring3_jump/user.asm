; ============================================================================
; 4b user.asm  --  Erstes Programm in Ring 3 (Userspace)
; ----------------------------------------------------------------------------
; Diese Datei wird SEPARAT zu user.bin assembliert und vom Kernel per
; `incbin "user.bin"` eingebettet. Der Kernel kopiert das Binary zur
; Laufzeit nach 0x40000 und springt per iret-Trick hinein.
;
; Wir laufen jetzt in Ring 3:
;   - in/out/cli/sti/hlt sind verboten (waeren GP-Faults)
;   - aber: VGA-Zugriff klappt, weil unser User-Daten-Segment Limit=4GB hat.
;     (In einem echten OS wuerde Paging das verhindern. Wir kommen dahin.)
;
; Das einzige, was wir tun: einen festen Text in einer festen Zeile anzeigen.
; Erscheint er, hat der Kernel-Sprung nach Ring 3 funktioniert.
; ============================================================================

bits 32
org  0x40000                  ; Kernel kopiert uns hierhin

USER_DATA equ 0x23            ; User-Daten-Selektor mit RPL=3 (0x20 | 3)
VGA       equ 0xB8000
YELLOW    equ 0x0E
ROWB      equ 80 * 2

user_entry:
    ; iret hat nur CS, SS, EIP, ESP, EFLAGS gesetzt -- DS/ES/FS/GS sind noch
    ; auf den Kernel-Werten. Damit waere jeder Speicherzugriff GP-Fault.
    ; Erste Pflicht: Datensegmente auf User-Daten umstellen.
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; Beweis: ich bin Ring 3, und schreibe nach VGA (geht, weil flat segment)
    mov esi, msg
    mov edi, ROWB * 8
.print:
    lodsb
    test al, al
    jz .done
    mov [VGA + edi], al
    mov byte [VGA + edi + 1], YELLOW
    add edi, 2
    jmp .print

.done:
    ; Endlosschleife. Achtung: KEIN hlt! hlt ist Ring-0-Befehl -> GP-Fault.
.hang:
    jmp .hang

msg db 'Hallo aus Ring 3! Ich bin ein User-Programm.', 0
