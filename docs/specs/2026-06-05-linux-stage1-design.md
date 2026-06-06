# Linux nachbauen — Etappe 1: Der A/B-Task-Switcher

Ziel des Gesamtprojekts: Linus Torvalds' echtes Vorgehen von 1991 Schritt für
Schritt nachvollziehen — vom CPU-Experiment bis zum frühen Kernel.

## Roadmap

```
Etappe 1   A/B-Task-Switcher        Linus' allererstes Programm ("Just for Fun")
Etappe 2   Treiber: Tastatur+Bildschirm   -> Richtung Terminal-Emulator
Etappe 3a  Disk-Treiber
Etappe 3b  Minix-Dateisystem (read-only zuerst)
```

Jede Etappe bekommt ihr eigenes Mini-Design. Dieses Dokument betrifft nur Etappe 1.

## Etappe 1 — Ziel

Linus' Experiment exakt nachbauen: zwei Tasks, per **386-Hardware-Task-Switching
(TSS)** abwechselnd, getrieben vom **Timer-Interrupt**. Task A schreibt `A`,
Task B schreibt `B` direkt in den VGA-Textspeicher (0xB8000). Ergebnis: `ABAB...`

Das ist kein Betriebssystem, sondern ein Programm zum Verstehen der CPU:
Protected Mode, Interrupts, Task-Switching. Genau Linus' tatsächliche Motivation.

## Mikro-Schritte (jeder einzeln in QEMU lauffähig)

```
1a  Bootsektor lebt      BIOS lädt 512B nach 0x7C00, gibt ein Zeichen aus
1b  VGA direkt           ins Textbuffer 0xB8000 schreiben (Real Mode)
1c  Protected Mode       A20, GDT, PE-Bit, Far Jump -> 32-bit Code
1d  Timer-Interrupt      IDT + PIC (8259) umprogrammieren, IRQ0 tickt
1e  Hardware-Task-Switch 2x TSS, Timer schaltet A<->B um   <- Etappe 1 fertig
```

## Werkzeuge

- Assembler: **NASM** (Intel-Syntax), reiner Assembler, kein C.
- Boot: **eigener Bootsektor von Floppy** (kein GRUB) — wie Linus' bootsect.s.
- Emulator: `qemu-system-i386 -fda floppy.img` (`-enable-kvm` für Tempo).

## Struktur

```
linux_understanding/
  README.md         Lernpfad + Notizen zu Linus' echtem Vorgehen
  Makefile          baut Floppy-Image, startet QEMU, Screenshot
  stage1/
    boot.asm        Bootsektor: Kernel nachladen, Real->Protected Mode
    kernel.asm      GDT, IDT, PIC, 2x TSS, Timer-Handler, Task A/B
```

## Boot-Ablauf

```
BIOS --(Sektor 0)--> 0x7C00  boot.asm
   |  A20 an, GDT laden, PE=1, far jump
   v
Protected Mode (32-bit)  kernel.asm
   |  IDT + PIC, TSS_A & TSS_B anlegen, Timer scharf, sti
   v
Timer-IRQ ~55ms --> task switch (jmp TSS-Selektor)
   v
Task A: 'A' @0xB8000  <-Timer->  Task B: 'B'
```

## Test / Verifikation

- Headless: QEMU-Monitor `screendump out.ppm` zieht VGA-Screenshot; prüfen, dass
  `ABAB...` erscheint — ohne Fenster.
- Frühe Schritte (1a): zusätzlich serielle Debug-Ausgabe.

## Bewusst weggelassen (YAGNI)

Kein Paging, kein Scheduler mit Prioritäten, keine Ring-3-Trennung, keine
C-Runtime. C kommt frühestens in Etappe 2/3 — dort stieg auch Linus auf gcc um.
