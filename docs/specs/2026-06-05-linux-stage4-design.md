# Etappe 4 -- Userspace + Syscalls (Ring 3, int 0x80)

Ziel: ein "User-Programm" ausserhalb des Kernels laufen lassen (Ring 3) und ihm
nur ueber Syscalls Zugriff auf Hardware/Bildschirm geben. Das ist die Stunde, in
der aus einem "selbstgeschriebenen Kernel" ein UNIX-aehnliches System wird.

## Konzept

```
   Ring 0 (Kernel)                 Ring 3 (User)
   ────────────────                ──────────────
   GDT, IDT, Treiber               nur eigener Code
   I/O-Ports                       int/out -> Exception
   Hardware-IRQs                   muss um alles bitten
       ▲                                │
       │                                │
       │  int 0x80 (Syscall)            │
       └────────────────────────────────┘
         eax = Nummer
         ebx, ecx, edx = Args
```

## Mikro-Schritte

```
4a  User-GDT + TSS       User-Code (0x18, DPL=3), User-Daten (0x20, DPL=3)
                         TSS mit ESP0 = Kernel-Stack-Top, ltr.
                         Verifikation: ltr ohne Crash, Kernel laeuft weiter.

4b  Sprung nach Ring 3   user.asm = endlose Schleife; per incbin ins Kernel.
                         iret-Trick: Stack mit SS/ESP/EFLAGS/CS/EIP fuettern,
                         dann iret -> CPU wechselt nach Ring 3.
                         Verifikation: User-Programm laeuft (sichtbar an
                         Speicher-Watch oder Trick: vor Schleife auf VGA
                         schreiben -- KLAPPT NICHT in Ring 3, weil VGA-Schreib
                         in Ring 3 erlaubt ist solange Segment Limit reicht).
                         Stattdessen: in/out vorm Loop -> Exception (Beweis!).

4c  int 0x80 Handler     IDT-Eintrag 0x80 mit DPL=3 (sonst kein Aufruf aus
                         User-Ring). Dispatcher: eax = Syscall-Nummer,
                         Routing-Tabelle, push/pop ueblich.
                         Verifikation: User ruft int 0x80, Kernel zeigt "got
                         syscall N=X eax=Y" und kehrt zurueck.

4d  sys_write + sys_exit sys_write(buf, len) -> screen_putc loop
                         sys_exit(code)      -> Kernel zeigt Exit-Code, hlt
                         User-Programm:
                           write(1, "Hallo aus Ring 3!\n", 18)
                           exit(0)
                         Verifikation: Text erscheint auf VGA, Kernel beendet
                         User sauber.
```

## Designentscheidungen

- **User-Programm wird ins Kernel eingebettet** (`incbin "user.bin"`). Halte
  Etappe 4 fokussiert auf Ring-Wechsel + Syscalls. Laden aus Datei kommt in
  Etappe 5 (knuepft an Etappe 3 Minix-FS an).
- **Ein TSS pro CPU** (Linux-Modell). Wir benutzen nicht das 1e-Hardware-Task-
  Switching mehr -- das TSS dient nur als Speicher fuer ESP0.
- **Linux-Syscall-Konvention**: eax=Nummer, ebx/ecx/edx=Args. Genau die alte
  i386-Linux-Konvention (`int 0x80`).
- **Flache Adressraum-Aufteilung**: kein Paging, keine getrennten User/Kernel-
  Adressraeume. Wir nutzen Segment-Limits zur Trennung -- d.h. User-Segment hat
  auch Limit 4 GB (wie Kernel). Schutz kommt aus Ring/DPL, nicht Paging.

## Bewusst weggelassen (YAGNI)

Paging, fork/exec, Signale, mehrere Prozesse, ELF-Loader, vfork, Job-Control.
Alles Etappe 5+ oder spaeter. Etappe 4 = Ein Userspace, ein Programm.
