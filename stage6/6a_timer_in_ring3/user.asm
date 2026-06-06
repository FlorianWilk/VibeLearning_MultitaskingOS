; ============================================================================
; 6a user.asm  --  Ring-3-Prozess, der einfach "lebt"
; ----------------------------------------------------------------------------
; Dieses Programm dreht endlos einen Spinner (| / - \) an einer festen
; Bildschirmposition. Es ist das Lebenszeichen: solange sich der Spinner
; bewegt, laeuft der User-Code. Gleichzeitig zeigt der Kernel-Timer-Handler
; oben einen Tick-Zaehler. Beide bewegen sich => der Timer unterbricht den
; User-Code und kehrt sauber zu ihm zurueck.
;
; (Direkt-VGA statt sys_write, um in 6a den Fokus auf die Timer-Mechanik zu
;  legen. In Ring 3 erlaubt, weil unser User-Segment flach ist (Limit 4 GB).)
; ============================================================================

bits 32
org  0x40000

USER_DATA equ 0x23
VGA       equ 0xB8000
CYAN      equ 0x0B
SPINPOS   equ (12 * 80 + 40) * 2     ; Mitte des Schirms

user_entry:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    xor ebx, ebx                     ; Spinner-Index
.loop:
    mov eax, ebx
    and eax, 3
    mov al, [spinner + eax]
    mov ah, CYAN
    mov [VGA + SPINPOS], ax

    inc ebx
    mov ecx, 0x00400000              ; Bremse, damit man's sieht
.delay:
    dec ecx
    jnz .delay
    jmp .loop

spinner db '|/-\'
