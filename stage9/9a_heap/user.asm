; ============================================================================
; 9a user.asm  --  testet den Heap (sys_sbrk)
; ----------------------------------------------------------------------------
; Fordert per sbrk Speicher an, schreibt einen String hinein, liest ihn zurueck
; und gibt ihn aus. Beweist: der Heap-Bereich ist gemappt, beschreibbar (User)
; und der per sbrk gelieferte Zeiger funktioniert.
;
; Syscalls:  1=exit  4=write(buf,len)  12=sbrk(increment)->alte Grenze
; ============================================================================

bits 32
org  0x800000

SYS_EXIT  equ 1
SYS_WRITE equ 4
SYS_SBRK  equ 12
USER_DATA equ 0x23

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    ; ptr = sbrk(32)
    mov eax, SYS_SBRK
    mov ebx, 32
    int 0x80
    mov edi, eax               ; edi = Heap-Zeiger

    ; String "Heap funktioniert!" hineinkopieren
    mov esi, src
    mov ecx, src_len
    push edi                    ; Zeiger fuer write merken
.copy:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    loop .copy
    pop edi                    ; edi = Anfang des Heap-Strings

    ; aus dem Heap zurueck-lesen und ausgeben
    mov eax, SYS_WRITE
    mov ebx, 1
    mov ecx, edi
    mov edx, src_len
    int 0x80

    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

src db 'Heap funktioniert! (via sbrk)', 0x0A
src_len equ $ - src
