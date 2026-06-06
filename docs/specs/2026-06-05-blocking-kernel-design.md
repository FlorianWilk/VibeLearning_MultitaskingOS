# Echter Kernel: Multitasking + blockierende IRQ-I/O

Umstellung vom "ein Task, synchrone Polling-Syscalls"-Modell auf das klassische
Unix-Modell: blockierende Syscalls legen den PROZESS schlafen, nie die CPU. Der
Scheduler laeuft derweil andere Prozesse; ein IRQ weckt den schlafenden Prozess.

Geht der Compiler-Roadmap voraus -- erst der richtige Kernel, dann VM/Compiler.

## Architektur (baut auf Etappe 6 / Scheduler auf)

```
   Prozess A: read() -> Kernel: A=BLOCKED, schedule()
                                  Prozess B rechnet
   Ereignis (IRQ) -> wakeup(A): A=READY -> laeuft beim naechsten schedule()
```

- Prozess-Tabelle (PCB je Prozess): state (READY/RUNNING/BLOCKED), saved_esp,
  kstack_top, page_dir (CR3), wait_reason.
- schedule(): naechsten READY waehlen, Kontext + CR3 + TSS.ESP0 wechseln.
  Kein READY -> Idle (hlt, IF=1).
- block(reason): aktueller Prozess BLOCKED, schedule().
- wakeup(reason): passende Prozesse -> READY.
- IRQ-Treiber: IRQ14 (Disk) -> wakeup(DISK); IRQ1 (Tastatur) -> wakeup(KBD).

## Mikro-Schritte

```
10a  Scheduler mit Zustaenden   Prozess-Tabelle, READY/BLOCKED, schedule, Idle.
                                Demo: 2 Prozesse preemptiv (ABAB), tabellenbasiert.
10b  Blockierende Tastatur      sys_read blockiert (block(KBD)); IRQ1 weckt bei
                                Enter. Demo: B zaehlt sichtbar weiter, waehrend A
                                auf Eingabe wartet -> CPU nicht verschwendet.
10c  Blockierende Disk-I/O      ATA-IRQ14-Treiber: read blockiert (block(DISK)),
                                IRQ14 liefert Daten + wakeup. Demo: B zaehlt,
                                waehrend A von Disk liest.
```

## Beweis-Idee (10b/10c)

Zwei Prozesse: A macht den blockierenden Syscall, B zaehlt einen sichtbaren
Zaehler. Waehrend A blockiert ist, steigt B's Zaehler weiter -> die CPU ist
nicht in einer Poll-Schleife gefangen. Das ist der Unterschied zu Etappe 9.

## Bewusst weggelassen (YAGNI)

Prioritaeten, fairer Scheduler, mehrere Wartebedingungen pro Prozess, sleep mit
Timeout. Round-robin + ein wait_reason reicht.
