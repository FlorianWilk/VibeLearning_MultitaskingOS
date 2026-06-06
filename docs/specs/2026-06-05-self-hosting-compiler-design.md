# Self-Hosting C-Subset-Compiler im eigenen OS

Ziel: Ein Compiler fuer ein C-Subset, der IM OS laeuft und sich selbst (sowie
andere Programme) uebersetzen kann. Minimaler Weg: Compiler erzeugt Bytecode,
eine Mini-VM im OS fuehrt ihn aus (Vorbild: c4 "C in four functions").

## Gesamtarchitektur

```
   OS (Assembler-Kernel, Etappen 1-8)
     + File-Syscalls (open/create/read/write/close) + Minix-FS-Write
     + Heap-Syscall (sbrk) + User-Allocator
        │
   VM (natives OS-Programm, Assembler): laedt .bc, interpretiert Bytecode,
       leitet Bytecode-"Syscalls" an OS-Syscalls weiter
        │
   compiler.bc  (Compiler, geschrieben in C-Subset, als Bytecode)
       laeuft in der VM, liest *.c -> schreibt *.bc
        │
   SELF-HOSTING: VM fuehrt compiler.bc aus -> kompiliert compiler.c -> compiler.bc
                 (Output == Input-Compiler = Beweis)
```

Rust-Rolle: der **v0-Bootstrap-Compiler** laeuft auf dem HOST (in Rust), nicht
im OS. Er uebersetzt das C-Subset einmalig zu Bytecode, um den in-OS-Compiler
zu erzeugen. Danach wird er nicht mehr gebraucht.

## Sprache (C-Subset, c4-Niveau)

Typen: `int`, `char`, Pointer. Konstrukte: Funktionen, `if`/`while`/`return`,
lokale+globale Variablen, Zuweisung, Arithmetik/Vergleiche, Funktionsaufrufe,
String-Literale. KEIN: structs, typedef, float, preprocessor (ausser evtl.
simpel), switch. Genug, um den Compiler selbst zu schreiben.

## Bytecode (Stack-Maschine, ~30 Opcodes, c4-VM-Stil)

LEA/IMM/JMP/JSR/BZ/BNZ/ENT/ADJ/LEV/LI/LC/SI/SC/PSH + OR/AND/.../ADD/SUB/MUL/DIV
+ "Syscall"-Opcodes: OPEN/READ/WRIT/CLOS/MALC/EXIT/PUTC. Flacher Speicher
(Code/Data/Stack), von der VM via OS-Heap angefordert.

## Roadmap (jede ist eine eigene grosse Etappe)

```
9   OS-Erweiterung    File-Syscalls (open/create/read/write/close),
                      Minix-FS schreiben, Heap-Syscall (sbrk).
                      Test: ein Programm schreibt eine Datei, ein anderes liest sie.

10  Bytecode-VM       Bytecode-ISA definieren; VM als OS-Programm (Assembler):
                      laedt .bc, interpretiert. Bytecode-Syscalls -> OS-Syscalls.
                      Test: handgeschriebenes .bc ("hello") laeuft in der VM.

11  v0-Compiler       Auf dem Host in Rust: C-Subset -> Bytecode (.bc).
                      Test: hello.c -> hello.bc, laeuft in der VM im OS.

12  Compiler in C-Subset  compiler.c schreiben (uebersetzt C-Subset -> Bytecode),
                      mit v0 zu compiler.bc kompilieren, ins OS laden.
                      Test: compiler.bc kompiliert ein fremdes Programm.

13  Self-Hosting      VM fuehrt compiler.bc aus, kompiliert compiler.c -> compiler.bc.
                      Vergleich Output == der mit v0 erzeugte compiler.bc -> Beweis.
```

## Realismus

Das ist das groesste Teilprojekt. Jede Etappe ist selbst umfangreich
(besonders 11/12). Aber klar zerlegbar wie bisher, mit Verifikation pro Schritt.
Der Kernel bleibt Assembler (minimal, funktioniert). Rust nur auf dem Host.

## Bewusst weggelassen (YAGNI)

Optimierung, nativer Code (wir nehmen Bytecode+VM), structs/float/preprocessor,
robuste Fehlerbehandlung. Erst self-hosting erreichen, dann ggf. erweitern.
