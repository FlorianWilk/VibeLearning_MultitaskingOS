; ============================================================================
; 14a write.asm  --  schreibt Text in eine existierende Datei
; ----------------------------------------------------------------------------
;   write <datei> <text>
; Liest die cmdline (0x803000): erstes Wort "write" ueberspringen, zweites Wort
; = Dateiname, Rest der Zeile = Text. Ruft writefile(name, text, len).
; Overwrite-Modell: die Datei muss bereits existieren (siehe mkdisk: notiz.txt).
; ============================================================================

bits 32
org  0x800000

SYS_EXIT      equ 1
SYS_WRITE     equ 4
SYS_WRITEFILE equ 16
USER_DATA     equ 0x23
ARGS          equ 0x803000

_start:
    mov ax, USER_DATA
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov esi, ARGS
    ; Programmnamen ("write") bis Space ueberspringen
.skipcmd:
    mov al, [esi]
    test al, al
    jz .err
    inc esi
    cmp al, ' '
    jne .skipcmd
    ; esi -> Dateiname; ebx merken (copy_name im Kernel stoppt beim Space)
    mov ebx, esi
    cmp byte [esi], 0
    je .err
    ; bis zum naechsten Space (Ende des Dateinamens)
.skipname:
    mov al, [esi]
    test al, al
    jz .err                          ; kein Text angegeben
    inc esi
    cmp al, ' '
    jne .skipname
    ; esi -> Text. Laenge bis 0 messen
    mov ecx, esi
    xor edx, edx
.len:
    mov al, [esi]
    test al, al
    jz .doit
    inc esi
    inc edx
    jmp .len
.doit:
    mov eax, SYS_WRITEFILE
    int 0x80                          ; ebx=name, ecx=text, edx=len
    test eax, eax
    js .err
    mov ecx, okmsg
    mov edx, oklen
    jmp .out
.err:
    mov ecx, errmsg
    mov edx, errlen
.out:
    mov eax, SYS_WRITE
    mov ebx, 1
    int 0x80
    mov eax, SYS_EXIT
    xor ebx, ebx
    int 0x80

okmsg  db 'geschrieben', 0x0A
oklen  equ $ - okmsg
errmsg db 'write: <datei> <text> (datei muss existieren)', 0x0A
errlen equ $ - errmsg
