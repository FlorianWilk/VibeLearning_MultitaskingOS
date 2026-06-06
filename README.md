# Bau dein eigenes bootfähiges Multitasking-Betriebssystem — von Grund auf, mit Shell

> Ein **VibeLearning**-Projekt: Schritt für Schritt von Hand gebaut, KI-assistiert,
> mit dem Ziel zu **verstehen** statt nur zu generieren.

Vom Bootsektor bis zur benutzbaren Shell — in reinem x86-Assembler, lauffähig in
QEMU. Wir bauen nach, womit Linus Torvalds 1991 wirklich anfing: nicht mit einem
fertigen "Betriebssystem", sondern mit einem Experiment, um die 386-CPU zu
verstehen — zwei Tasks, die per Hardware-Task-Switching abwechselnd `A` und `B`
auf den Schirm schreiben (siehe seine Autobiografie *"Just for Fun"*). Von dort
aus wächst Schritt für Schritt ein echter Multitasking-Kernel: Treiber, Disk +
Dateisystem, Userspace + Syscalls, Paging, präemptiver Scheduler mit
blockierender IRQ-I/O, und eine Shell mit `ls`, `cat`, `echo`, Dateien anlegen
und Hintergrund-Jobs.

```
┌──────────────────────────────────────────────────────────┐
│  Boot → Protected Mode → IRQs → Treiber → Disk/Minix-FS   │
│  → Userspace/Syscalls → Paging → Scheduler → Shell        │
└──────────────────────────────────────────────────────────┘
```

## Was ist VibeLearning?

"Vibe Coding" heißt: locker mit einem KI-Assistenten drauflosbauen. **VibeLearning**
dreht das Ziel um — nicht möglichst schnell Code *generieren*, sondern den
generierten Code wirklich *verstehen*. Darum besteht dieses Projekt aus winzigen
Schritten, von denen jeder einzeln gebaut, per Screenshot verifiziert und im
README erklärt wird. Man lernt durch Mitbauen und Vergleichen (`diff` zwischen
zwei Schritten), nicht durch Lesen einer fertigen Codebasis.

## Schnellstart

Voraussetzungen: `nasm`, `qemu-system-i386`, `make`, `imagemagick` (für `shot`),
`python3` (für die Disk-Images). Auf Debian/Ubuntu:

```
sudo apt install nasm qemu-system-x86 make imagemagick python3
```

`STAGE` wählt die Version (Default: neueste). Artefakte landen in `build/<stage>/`.

```
make STAGE=14b_create shot   # headless booten -> build/14b_create/out.png ansehen
make STAGE=14b_create run    # interaktiv in einem QEMU-Fenster
make STAGE=1b_vga_direkt run # ganz am Anfang: erstes Lebenszeichen
make clean
```

Reiner Assembler, kein C — wie Linus' erster Code. Statt echter 386-Hardware
emuliert QEMU den PC; statt Diskette ein Floppy-Image. **Code-Kommentare sind auf
Deutsch.** Technische Referenz aller Konventionen (Syscalls, Speicher-Layout,
bekannte Fallstricke): siehe [`CHEATSHEET.md`](CHEATSHEET.md).

## Struktur

Jeder Mikro-Schritt liegt in einem eigenen Verzeichnis, damit alle Versionen zum
Vergleichen erhalten bleiben:

```
stage1/
  1a_bootsektor/boot.asm      BIOS-Ausgabe via int 0x10
  1b_vga_direkt/boot.asm      direkt nach 0xB8000 (Real Mode, Segment:Offset)
  1c_protected_mode/boot.asm  Protected Mode, flache Adressierung
  1d_timer/boot.asm+kernel.asm  Bootsektor laedt Kernel; Timer-IRQ tickt
  1e_taskswitch/...             2 Tasks (A/B) per Hardware-TSS, Timer-getrieben
  1f_software_switch/...        gleiche Demo per SOFTWARE-Switch (pusha/popa)
stage2/
  2a_kbd_interrupt/...          IRQ1, roher Scancode
  2b_scancode_ascii/...         US-Layout-Uebersetzung, Zeichen erscheinen
  2c_screen_driver/...          Bildschirm-Treiber: Cursor, Enter, BS, Scroll
  2d_serial_out/...             zweiter Treiber: kbd -> screen UND serial out
  2e_serial_in/...              UART-IRQ -> screen_putc (bidirektional)
stage3/
  3a_ata_identify/...           ATA IDENTIFY -- Disk-Modell-String
  3b_read_sector/...            read_sector(LBA, buf), Hex-Dump
  3c_minix_image/...            mkdisk.sh baut Minix-v1-Image (Python)
  3d_superblock/...             Superblock-Felder geparst + angezeigt
  3e_root_dir/...               Root-Verzeichnis listet (. .. hello.txt)
  3f_read_file/...               cat /hello.txt -> Inhalt auf VGA
stage4/
  4a_user_gdt_tss/...           GDT mit User-Segmenten + TSS, ltr
  4b_ring3_jump/...             user.asm separat; iret-Trick in Ring 3
  4c_syscall_int80/...          int 0x80 Mechanismus (DPL=3 Trap Gate)
  4d_write_exit/...             sys_write + sys_exit, Unix-style Programm
stage9/
  9a_heap/...                   sys_sbrk, vorgemappter Heap
  9b_file_read/...              readfile-Syscall (Minix, Polling)
stage10/
  10a_scheduler/...             Prozess-Tabelle + Scheduler mit Zustaenden
  10b_blocking_kbd/...          blockierende Tastatur (block/wakeup, IRQ1)
  10c_blocking_disk/...         blockierende Disk-I/O (IRQ14, kein Polling)
stage11/
  11a_ata_write/...             ATA-Write per IRQ (Roundtrip Sektor 5)
  11b_writefile/...             Minix writefile (Overwrite) + readfile
stage12/
  12a_shell_mt/...              Shell auf Multitasking-Kernel, exec+wait
  12b_background/...            Hintergrund-Jobs (&) + Shift-Tastatur
stage13/
  13a_args/...                  Argument-Passing (Args-Page), echo
  13b_cat_ls/...                cat + ls (readfile/listdir-Syscalls)
stage14/
  14a_write/...                 write <datei> <text> (writefile, Overwrite)
  14b_create/...                Dateien anlegen (imap/zmap-Allokation + dirent)
stage5/
  5_load_init/...               /init.bin von Minix-FS laden + Ring-3-Start
stage6/
  6a_timer_in_ring3/...         Timer-IRQ unterbricht Ring 3 sauber (TSS.ESP0)
  6b_two_procs/...              zwei Threads (gemeinsamer Blob), preemptiv
  6c_two_programs/...           zwei getrennte Programme (proc_a/proc_b)
stage7/
  7a_enable_paging/...          Paging an; virt 0x800000 -> phys VGA als Beweis
  7b_two_address_spaces/...     beide @virt 0x800000, getrennte Page-Dirs, CR3
stage8/
  8a_shell_prompt/...           User-Shell (Ring 3) + sys_read, Prompt-Loop
  8b_exec/...                   sys_exec: Programme von Disk starten (hello/count)
```

Ab 1d ist der Code zweigeteilt: `boot.asm` (Nachlader + Moduswechsel) und
`kernel.asm` (das eigentliche Programm, nach 0x10000 geladen).

## Schritte vergleichen

Der Kern der VibeLearning-Idee: was ändert ein Schritt gegenüber dem vorigen?
Z.B. was 1c (Protected Mode) gegenüber 1b ergänzt:

```
diff stage1/1b_vga_direkt/boot.asm stage1/1c_protected_mode/boot.asm
```

## Fortschritt (Etappe 1)

```
[x] 1a  Bootsektor lebt        BIOS laedt 512B nach 0x7C00, gibt 'L' aus
[x] 1b  VGA direkt             ins Textbuffer 0xB8000 schreiben
[x] 1c  Protected Mode         A20, GDT, PE-Bit, Far Jump -> 32-bit
[x] 1d  Timer-Interrupt        IDT + PIC, IRQ0 tickt
[x] 1e  Hardware-Task-Switch   2x TSS, Timer schaltet A<->B  -> ABAB...
[x] 1f  Software-Task-Switch   pusha/popa + ESP umschalten (so wie Linux)

ETAPPE 1 KOMPLETT -- Linus' erstes Programm laeuft.

## Etappe 2 -- Treiber: Tastatur + Bildschirm

```
[x] 2a  Tastatur-Interrupt    IRQ1 freischalten, Scancode lesen
[x] 2b  Scancode -> ASCII     US-Layout-Tabelle, tippbare Zeichen
[x] 2c  Bildschirm-Treiber    Cursor, Enter, Backspace, Scrollen
                              kbd_handler -> screen_putc (Treiber-Trennung)
[x] 2d  serieller Output      zweiter Treiber: kbd -> screen UND serial out
[x] 2e  serieller Input       UART-IRQ -> screen_putc (Linus' Bidirektional)
```

ETAPPE 2 KOMPLETT -- Terminal-Emulator mit zwei Hardware-Quellen (Tastatur +
serieller Port), die ueber zwei IRQs entkoppelt am gleichen Bildschirm-Treiber
muenden. Genau Linus' Modem-Konstellation von 1991.

## Etappe 3 -- Disk + Minix-Dateisystem

```
[x] 3a  ATA IDENTIFY        Disk-Modell-String erkennen
[x] 3b  read_sector         512-Byte-Sektor lesen, Hex-Dump als Beweis
[x] 3c  Minix-Image bauen   Python-Skript schreibt FS-Strukturen als Bytes
                            (kein mount, kein sudo)
[x] 3d  Superblock parsen   n_inodes, n_zones, magic, inode_table_blk
[x] 3e  Root listen         Inode 1 -> Datenblock -> Dir-Eintraege
[x] 3f  cat /hello.txt      Pfad -> Inode -> Datenbloecke -> Inhalt
```

ETAPPE 3 KOMPLETT -- der Kernel liest jetzt echte Dateien von der Disk.

## Etappe 4 -- Userspace + Syscalls

```
[x] 4a  User-GDT + TSS    User-Code(0x18)/Daten(0x20) DPL=3, TSS+ltr
[x] 4b  Sprung nach Ring 3  iret-Trick mit SS/ESP/EFLAGS/CS/EIP
[x] 4c  int 0x80           IDT-Eintrag DPL=3 (Trap Gate), Args ueber Regs
[x] 4d  sys_write + sys_exit  zwei echte Syscalls (Linux-Nummern 4, 1)
                              User-Programm ruft write() + exit(0)
```

ETAPPE 4 KOMPLETT -- Userspace mit Syscalls. Erstes echtes Unix-style-Programm.

## Etappe 9/10 -- Echter Kernel (Heap, blockierende IRQ-I/O)

```
[x] 9a   Heap (sys_sbrk)         vorgemappte Heap-Pages, sbrk teilt aus
[x] 9b   readfile-Syscall        ganze Datei per Minix-Lookup laden (Polling)
[x] 10a  Scheduler+Zustaende     Prozess-Tabelle (READY/RUNNING/BLOCKED)
[x] 10b  Blockierende Tastatur   sys_read schlaeft (block/wakeup), IRQ1 weckt;
                                 proc_b zaehlt weiter, waehrend proc_a wartet
[x] 10c  Blockierende Disk       ATA per IRQ14 statt Polling; block/wakeup
```

ETAPPE 9/10 KOMPLETT -- vom "ein Task, Polling-Syscalls"-Modell zum echten
Unix-Kernel: blockierende Syscalls legen den PROZESS schlafen, nie die CPU.
Einheitlicher Kontextwechsel (popa+iret; iret waehlt Frame-Typ per CS).
Polling war bewusste Vereinfachung; IRQ-I/O lohnt nur mit Multitasking.

## Etappe 11 -- Datei-Schreiben (Compiler-Voraussetzung)

```
[x] 11a  ATA write_sector (IRQ)  WRITE 0x30 + outsw + block(DISK); disk_op-Flag
                                 im IRQ-Handler (READ=insw / WRITE=ack). Roundtrip.
[x] 11b  Minix writefile         Overwrite-Modell: Datei finden, Zonen schreiben
                                 (kwrite), i_size aktualisieren. readfile dazu.
```

ETAPPE 11 KOMPLETT -- OS kann jetzt Dateien lesen UND schreiben. Damit sind alle
OS-Bausteine fuer den self-hosting Compiler da (Heap, FS-read/write, echter
Kernel). Naechster grosser Schritt: Bytecode-VM, dann Compiler.

## Etappe 12 -- Shell auf Multitasking-Kernel + Hintergrund-Jobs

```
[x] 12a  Shell auf MT-Kernel   Shell als Prozess (Slot 0), exec sucht freien
                               Slot, laedt Programm, foreground = wait (block
                               auf Kind-exit). Mehrere Adressraeume.
[x] 12b  Hintergrund-Jobs (&)  Shell parst '&' -> exec ohne wait, Kind laeuft
                               nebenlaeufig. PLUS: Shift-Support fuer Tastatur
                               (& = Shift+7, Grossbuchstaben, Symbole).
```

ETAPPE 12 KOMPLETT -- die Shell laeuft jetzt auf dem echten Multitasking-Kernel:
mehrere Prozesse nebenlaeufig, Foreground (wait) und Hintergrund (&).
Bug-Fund: Timer-IRQ ueberschrieb im Idle den Kontext des blockierten Prozesses
-> timer_handler schaltet nur noch bei state==RUNNING um (sonst nur EOI+iret).

## Etappe 13 -- Argumente + Unix-Programme (ls, cat, echo)

```
[x] 13a  Argument-Passing  exec kopiert cmdline in Args-Page (virt 0x803000);
                           Programm parst selbst. Test: echo gibt Args aus.
[x] 13b  cat + ls          cat <datei> (Argument + readfile-Syscall),
                           ls (listdir-Syscall). Plus Daten-Page (0x804000)
                           fuer Programm-Puffer (statt grosses BSS im Binary).
```

ETAPPE 13 KOMPLETT -- die Shell ist nutzbar: ls, cat <datei>, echo <text>,
hello, count, alles mit & im Hintergrund. Programme sind eigenstaendige
Unix-style Binaries auf der Disk (Unix-Philosophie: keine Builtins ausser
zustandsaendernden wie cd).

## Etappe 14 -- Dateien schreiben und anlegen

```
[x] 14a  write <datei> <text>  kwrite (ATA WRITE 0x30 per IRQ) + Minix writefile
                               aus Etappe 11 in den Multitasking-Kernel
                               zurueckportiert. Overwrite: Datei muss existieren.
[x] 14b  Dateien anlegen       freien Inode (imap) + freie Zone (zmap) allozieren,
                               Directory-Eintrag in root anhaengen. writefile
                               legt jetzt an ODER ueberschreibt.
```

ETAPPE 14 KOMPLETT -- das Minix-FS ist schreibend vollstaendig: `write neu.txt
hallo` legt eine Datei an, `ls` zeigt sie, `cat neu.txt` liest sie. Lehrreicher
Bug dabei (latent seit Etappe 13): `read` liefert nur die Laenge und
terminiert nicht; die Shell muss die Kommandozeile selbst mit 0 abschliessen,
sonst liest die Namens-Extraktion bei einem kurzen Befehl nach einem langen die
Reste mit ("ls" nach "write neu.txt..." wird zu "lsite" -> nicht gefunden).

## Etappe 5 -- Programm aus dem Dateisystem laden

```
[x] 5  /init.bin laden   Kernel liest init.bin per Minix-FS-Lookup von Disk,
                         laedt es nach 0x40000, springt per iret nach Ring 3.
                         Vereint Etappe 3 (Disk+FS) und Etappe 4 (Userspace).
```

ETAPPE 5 KOMPLETT -- das User-Programm steckt nicht mehr im Kernel, sondern
liegt als Datei auf der Disk. Genau wie Linus' /sbin/init.

Lehrreicher Bug dabei: nach iret mit IF=1 nach Ring 3 feuerte ein verwaister
Timer-IRQ ohne IDT-Eintrag -> Triple Fault. Fix: Hardware-IRQs am PIC maskieren.
In Etappe 4 nur per Timing-Glueck nicht aufgetreten (kein Disk-Warten).

## Etappe 6 -- Preemptives Multitasking im Userspace

```
[x] 6a  Timer unterbricht Ring 3   Timer-IRQ aus Ring 3 sauber behandeln
                                   (TSS.ESP0), iret zurueck. Behebt den
                                   Etappe-5-Bug RICHTIG statt zu maskieren.
[x] 6b  Zwei Prozesse preemptiv    zwei Ring-3-Prozesse, je User+Kernel-Stack,
                                   Timer schaltet round-robin. TSS.ESP0 wird
                                   bei jedem Switch aktualisiert. -> ABAB.
                                   (gemeinsamer Blob, 2 Einspruenge = Threads)
[x] 6c  Zwei getrennte Programme   proc_a.bin/proc_b.bin separat assembliert,
                                   an 0x40000/0x50000 geladen. Scheduler
                                   identisch -- nur das Laden aendert sich.
```

ETAPPE 6 KOMPLETT -- echtes Userspace-Multitasking. Wie 1e/1f (ABAB), aber jetzt
mit isolierten Ring-3-Prozessen, die per sys_write arbeiten. Non-preemptive
Kernel (Interrupt Gates: kein Timer waehrend Syscall).

## Etappe 7 -- Paging (virtuelle Adressraeume)

```
[x] 7a  Paging einschalten     Page Directory + Tables, identity-map 4 MB,
                               CR0.PG=1. Beweis: virt 0x800000 -> phys VGA
                               -> Schreiben dorthin erscheint am Schirm.
[x] 7b  Zwei Adressraeume       beide Prozesse @virt 0x800000, eigene Page-Dirs
                               -> verschiedene physische Frames. Timer-Switch
                               laedt CR3 um. Echte Prozess-Isolation.
```

ETAPPE 7 KOMPLETT -- virtueller Speicher. Beide Prozesse benutzen dieselbe
virtuelle Adresse, sind physisch aber getrennt. Der letzte grosse CPU-
Mechanismus. Kernel in beiden Adressraeumen identity-gemappt -> Handler laeuft
ueber den cr3-Wechsel hinweg.

## Etappe 8 -- Die User-Shell (vereint ALLES)

```
[x] 8a  User-Shell + read   Shell als Ring-3-Programm (eigener Adressraum).
                            sys_read blockiert (sti+hlt) bis Enter, Tastatur-IRQ
                            fuellt Kernel-Zeilenpuffer. Prompt -> read -> echo.
[x] 8b  sys_exec            Shell startet Programme von der Minix-Disk. exec
                            laedt ins Kind-Adressraum, 2-Ebenen-Kontextwechsel
                            (exec pausiert Shell, exit weckt sie). Programme:
                            hello, count. Unbekannt -> Fehlermeldung.
```

ETAPPE 8 KOMPLETT -- eine echte interaktive Unix-Shell. Vereint Tastatur (2),
Bildschirm (2), Disk+Minix-FS (3), Userspace+Syscalls (4), Paging-Isolation (7).
Jedes Programm laeuft isoliert bei virt 0x800000 im eigenen Adressraum.
spawn-Modell (kein fork): exec = neuer Adressraum + laden + ausfuehren + zurueck.

Bug-Fund dabei: mkdisk schrieb Inodes bei inode_nr*32 statt (inode_nr-1)*32
(Inodes sind 1-indexiert) -> leerer Inode -> Sektor 0 geladen -> Page Fault.
```

### 1a — Der Bootsektor lebt

Das BIOS bootet nur Sektoren, die mit der Signatur `0x55 0xAA` enden. Unser
512-Byte-Sektor gibt per BIOS-Interrupt (`int 0x10`) ein `L` aus. Das beweist:
unser eigener Code laeuft auf der (emulierten) CPU im 16-bit Real Mode.

### 1b — VGA direkt beschreiben

Statt des BIOS schreiben wir direkt in den VGA-Textspeicher ab `0xB8000`. Jede
Zelle = 2 Byte (ASCII + Farbe). `mov word [es:0], 0x0A41` setzt oben links ein
gruenes `A` -- es ueberschreibt sichtbar das `S` von `SeaBIOS`. Damit beherrschen
wir die Ausgabe ohne jede Software dazwischen; genau das werden Task A/B nutzen.

### 1d — Timer-Interrupt

Der PIT feuert periodisch IRQ0. Wir programmieren den PIC (8259) um, damit IRQ0
auf Vektor 0x20 liegt (sonst Kollision mit CPU-Exceptions), tragen den
`timer_handler` in die IDT ein und schalten mit `sti` scharf. Der Handler zaehlt
einen Tick-Zaehler hoch und sendet EOI an den PIC (ohne EOI tickt es genau
einmal). Beweis: die Hex-Zahl steigt zwischen zwei Screenshots. Ein Interrupt ist
ein erzwungener Kontextwechsel -- die Vorstufe zum Task-Switch in 1e.

### 1e — Hardware-Task-Switch (Linus' erstes Programm)

Zwei Tasks mit je eigenem TSS (104-Byte-Struktur mit dem kompletten CPU-Zustand)
und eigenem Stack. Ein `jmp` auf einen TSS-Selektor laesst die CPU den alten
Zustand sichern und den neuen laden -- Hardware-Task-Switching. Der Timer-Handler
macht bei jedem Tick so einen Switch zur jeweils anderen Task. Ergebnis:
abwechselnde Bloecke aus gruenen `A` (Task A) und weissen `B` (Task B). Genau das
hat Linus 1991 gebaut, um die 386-CPU zu verstehen.

### 1f — Software-Task-Switch (Vergleich)

Gleiche Demo, aber ohne TSS: der Timer-Handler sichert den Kontext mit `pusha`
auf den Stack der Task, merkt sich nur deren ESP, laedt den ESP der anderen Task
und stellt mit `popa` + `iret` deren Kontext her. Kein TSS, keine erweiterte GDT,
kein `ltr` -- die GDT aus boot.asm reicht. So macht es Linux: schneller, und auf
JEDER CPU lauffaehig (TSS gibt es nur auf x86, im 64-bit-Modus gar nicht mehr).

```
diff stage1/1e_taskswitch/kernel.asm stage1/1f_software_switch/kernel.asm
```

### 1c — Protected Mode

Hardware-Task-Switching gibt es nur im Protected Mode. Umschalten: A20-Gate
oeffnen, GDT laden (Null/Code/Daten), PE-Bit in CR0 setzen, Far Jump nach
`0x08:protected_start`. Danach schreibt 32-bit-Code ein weisses `P` auf rot nach
`0xB8000` (flache lineare Adresse). Kein Reboot-Loop = Wechsel erfolgreich. Wir
nutzen das Flat-Memory-Modell (Basis 0, Limit 4 GB) wie Linux.

## Lizenz

[MIT](LICENSE) — frei nutzen, forken, daraus lernen.
