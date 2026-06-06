# Wiedereinstieg-Cheatsheet

Technische Referenz fuer dieses Projekt. Ergaenzt `README.md` (erzaehlt den Weg)
und die Specs in `docs/specs/`.

## Bauen & Testen

```
make STAGE=<name> all       # baut build/<name>/floppy.img (+ disk.img wenn mkdisk.sh)
make STAGE=<name> run       # QEMU-Fenster (-boot a)
make STAGE=<name> term      # VGA-Text im Terminal (-curses); beenden: Alt+2, quit
make STAGE=<name> serial    # COM1 ans Host-Terminal
make STAGE=<name> shot      # headless -> build/<name>/out.png  (zum Ansehen!)
make clean
```

- `STAGE` = Verzeichnisname unter `stage*/` (z.B. `13b_cat_ls`). Default oben im Makefile.
- Jede Stage liegt in `stageN/<schritt>/` mit `boot.asm` (+ `kernel.asm`, ggf.
  `user.asm`/`proc_*.asm`/`shell.asm`/weitere Programme, `mkdisk.sh`). Alle
  `.asm` ausser boot/kernel werden zu `.bin` und vom Kernel per `incbin` oder
  von `mkdisk.sh` ins Disk-Image gepackt.
- **Verifikation immer per `shot`** und das PNG mit dem Read-Tool ansehen.
- Headless-Test mit Tastatur: QEMU `-monitor stdio`, `sendkey <taste>` schicken,
  dann `screendump x.ppm`; `&` = `sendkey shift-7`. Disk: `-hda build/<name>/disk.img`.
- Debug: `-d int -no-reboot` zeigt Interrupt-Vektoren/Faults. `v=0e` Page-Fault
  (CR2=Adresse), `v=0d` GP (errcode = Selektor/IDT-Index), `v=08` Double, Triple.

## Aktueller Stand (alle fertig)

```
1  CPU: Boot, Protected Mode, IDT/PIC, Hardware- (1e) + Software-Task-Switch (1f)
2  Treiber: Tastatur, VGA, Serial (bidirektional)
3  Disk (ATA-PIO) + Minix-FS lesen (cat /hello.txt)
4  Userspace: Ring 3, GDT/TSS, int 0x80, write/exit
5  init von Disk laden
6  praeemptives Multitasking (HW-TSS + Software)
7  Paging (virtuelle Adressraeume, Isolation)
8  User-Shell (spawn-Modell, exec von Disk)        [altes Single-Task-Modell]
9  Heap (sbrk), readfile (Polling)
10 ECHTER Kernel: Scheduler mit Zustaenden + blockierende IRQ-I/O (KBD, Disk)
11 Datei-Schreiben: ATA-Write IRQ, Minix writefile (Overwrite-Modell)
12 Shell auf Multitasking-Kernel: exec+wait (12a), Hintergrund & + Shift (12b)
13 Argument-Passing (13a, echo), ls + cat (13b)
14 write-Befehl: kwrite+writefile zurueckportiert (14a Overwrite); echtes
   Datei-Anlegen via imap/zmap-Allokation + dirent (14b)
```

Neueste/relevanteste Stage: **stage14/14b_create** (vollstaendigster Kernel +
Shell, Dateien anlegen + lesen + schreiben). Davon ausgehend weiterbauen.

## Konventionen im aktuellen Kernel (Stage 12/13)

**Syscalls (int 0x80, Nummer in eax, Args ebx/ecx/edx):**
```
1  exit(code)
3  read(buf, maxlen) -> len        blockierend (Tastatur)
4  write(buf, len)                 nach VGA
11 exec(name, len, bg)             bg=edx (0=foreground/wait, 1=background)
13 readfile(name, buf) -> size     ganze Datei laden
16 writefile(name, buf, size)      anlegen ODER ueberschreiben (14b; 14a nur Overwrite)
17 listdir(buf) -> len             Dateinamen newline-getrennt
```
(Frueher zusaetzlich: 12 sbrk, 14 readdisk, 15 writedisk -- je nach Stage.
In 14a aktiv: 1,3,4,11,13,16,17.)

**Virtuelle Adressen (alle Programme, je eigener Adressraum):**
```
0x800000  Code (org der proc-asm)        0x801000  User-Stack (top 0x802000)
0x803000  Args-Page (cmdline)            0x804000  Daten-/Puffer-Page (cat/ls buf)
```

**Physisches Layout (Stage 12/13, NPROC=4 Slots):**
```
0x10000   Kernel                         0x90000   Boot-Stack
0x101000  kernel_pt (identity 0-4MB)
0x110000  PD[i] = 0x110000 + i*0x2000;  UPT[i] = +0x1000
0x200000  CODE[i] = 0x200000 + i*0x10000 ; STACK=+0x1000, ARGS=+0x3000, DATA=+0x4000
0x9F000   KSTACK[i] = 0x9F000 - i*0x1000
```

**PCB (proc_table, PCB_SIZE=20):** +0 state(0=UNUSED/1=READY/2=RUNNING/3=BLOCKED),
+4 saved_esp, +8 kstack_top, +12 page_dir(CR3), +16 wait_reason.

**Scheduler/Kontextwechsel:** einheitlich `popa; iret` (resume_current). iret
waehlt am gespeicherten CS automatisch Ring0->Ring0 (3 Werte) oder ->Ring3 (5).
`block(eax=reason)` baut Ring-0-iret-Frame (-> .resume -> ret). `wakeup(eax=reason)`.
WAIT_KBD=1, WAIT_DISK=2, WAIT_CHILD=3.

## Wichtige Bugs/Patterns (NICHT nochmal reinlaufen)

- **Timer im Idle:** timer_handler darf nur umschalten wenn current==RUNNING;
  sonst (current BLOCKED, in schedules hlt-Schleife) ueberschreibt er den
  saved_esp des Blockierten + nested Stack. Fix: `cmp RUNNING; jne .justret`.
- **IRQ-Maskierung bei Polling:** wer Disk pollt, muss IRQs maskieren, sonst
  feuert IRQ14 (Vektor 0x76 im BIOS-Default / 0x2e nach Remap) ohne Handler -> GP.
- **mkdisk Inode-Offset:** Inodes sind 1-indexiert -> Inode N bei `(N-1)*32`,
  NICHT `N*32`. (Klassischer Fehler, schon zweimal passiert.)
- **CR0.PG setzen nicht vergessen** nach setup_paging + cr3-load.
- **Disk-IRQ liest in Kernel-Puffer** (disk_kbuf, identity), nicht direkt in den
  User-Puffer -- der IRQ kann in fremdem CR3 feuern. User-Kopie nach dem Wecken.
- **Programme klein halten:** grosse Puffer NICHT ins Binary (`times N db 0`),
  sondern feste gemappte Adresse nutzen (0x804000 Daten-Page). Sonst Binary > 1 Zone.
- **'&' braucht Shift** (Shift+7); Tastatur hat seit 12b Shift-Support
  (scancode_to_ascii_shift, shift_state).
- **mkdisk imap/zmap Byte-Overflow:** `(1<<nused)-1` passt nur fuer nused<=8 in
  ein Byte. Ab 9 Dateien (14a) Bits ueber mehrere Bytes verteilen (divmod 8).
- **Disk-IRQ read vs write:** Handler unterscheidet per `disk_op`-Flag -- bei
  Write-Complete NICHT `insw` (keine Daten da). kread setzt 0, kwrite setzt 1.
- **cmdline 0-terminieren:** `read` liefert nur die Laenge, terminiert NICHT.
  Shell muss `linebuf[len]=0` setzen, sonst liest `copy_name` (laengen-ignorant,
  stoppt erst bei Space/Ctrl) bei kurzem Befehl nach langem die Reste mit
  (z.B. "ls" nach "write neu.txt..." -> "lsite" -> nicht gefunden). [14b-Fund,
  latent seit 13b]
- **zmap-Bit k -> Zone FIRST_DATA+k-1** (bit0 Sentinel, bit1 root). imap bit
  k = Inode k. mkdisk setzt nur die `nused` belegten Bits (Rest 0=frei), sonst
  findet die Allokation (alloc_inode/alloc_zone) keine freien Slots.

## Naechste Schritte (Optionen)

Shell-Ausbau: `wc`, `jobs`/Exit-Meldung fuer Background, Pipes (`ls | cat`),
`rm` (Datei loeschen: imap/zmap-Bits freigeben + dirent leeren -- Gegenstueck
zu 14b). Schreiben/Anlegen/Lesen stehen (14b). 14b-Limit: neue Datei = 1 Zone
(max 1024 Byte); Mehrzonen-Anlage waere der naechste FS-Schritt.

ODER pausiertes Grossprojekt: **self-hosting C-Subset-Compiler** (Spec:
`docs/specs/2026-06-05-self-hosting-compiler-design.md`). Modell:
C-Subset -> Bytecode -> Mini-VM (c4-Stil), v0-Compiler in Rust auf dem Host
(rustc 1.75 da). OS-Basis (Heap, FS-read/write, MT-Kernel) steht komplett.
Reihenfolge: Bytecode-VM -> v0-Compiler (Rust) -> Compiler in C-Subset -> self-host.

## Arbeitsweise (vom User bestaetigt)

Deutsch, nuechtern/rational, knappe .md. Mikro-Schritte, jeder per `shot`
verifiziert, an Checkpoints innehalten + erklaeren (nicht vorpreschen). Sauber +
minimal, kein Cargo-Cult; lieber "richtig" bauen wenn lehrreich (z.B. IRQ-I/O
statt Polling). Kernel bleibt Assembler; Rust nur auf dem Host. Kein Git-Repo.
```
