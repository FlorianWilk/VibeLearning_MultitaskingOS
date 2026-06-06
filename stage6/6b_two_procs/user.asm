; ============================================================================
; 6b user.asm  --  ZWEI Prozesse (eigentlich Threads) in einem Blob
; ----------------------------------------------------------------------------
; Da wir kein Paging haben, teilen sich beide "Prozesse" den Adressraum (Code +
; Daten). Unterschiedlich sind nur ihr EIP (Einsprung) und ihr User-Stack --
; das macht sie zu zwei unabhaengig schedulebaren Ablaeufen (Threads).
;
; Damit der Kernel die zwei Einsprungpunkte kennt, ohne Offsets raten zu
; muessen, beginnt der Blob mit einer kleinen Tabelle:
;     [0x40000] = Adresse von proc_a
;     [0x40004] = Adresse von proc_b
;
; Jeder Prozess ruft in einer Schleife sys_write(sein Zeichen) + bremst kurz.
; Der Timer schaltet zwischen ihnen -> auf dem Schirm entstehen A/B-Bloecke.
; ============================================================================

bits 32
org  0x40000

USER_DATA equ 0x23
DELAY     equ 0x00180000

entry_table:
    dd proc_a
    dd proc_b

; ----------------------------------------------------------------------------
proc_a:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
.loop:
    mov eax, 4                ; sys_write
    mov ebx, 1                ; fd
    mov ecx, char_a           ; Puffer
    mov edx, 1                ; Laenge
    int 0x80
    mov edi, DELAY            ; Bremse (edi, weil ecx/eax Syscall-Regs waren)
.delay:
    dec edi
    jnz .delay
    jmp .loop

; ----------------------------------------------------------------------------
proc_b:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
.loop:
    mov eax, 4
    mov ebx, 1
    mov ecx, char_b
    mov edx, 1
    int 0x80
    mov edi, DELAY
.delay:
    dec edi
    jnz .delay
    jmp .loop

char_a db 'A'
char_b db 'B'
