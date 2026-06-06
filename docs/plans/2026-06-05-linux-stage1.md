# Etappe 1: A/B-Task-Switcher — Implementierungsplan

> **Für agentische Worker:** Ausführung Schritt für Schritt. Bare-Metal-Assembler:
> „Test" = in QEMU booten und VGA-Ausgabe prüfen (Screenshot oder serielle Ausgabe).

**Ziel:** Linus' erstes Programm nachbauen — zwei Tasks per 386-Hardware-Task-
Switching, getrieben vom Timer-IRQ, schreiben abwechselnd `A`/`B` auf den Schirm.

**Ansatz:** Eigener Bootsektor (NASM, Intel-Syntax) bootet von Floppy, wechselt in
Protected Mode, richtet IDT/PIC/TSS ein. Aufbau in 5 einzeln lauffähigen Schritten.

**Tech:** NASM, qemu-system-i386, GNU make. Reiner Assembler, kein C.

---

## Dateien

```
linux_understanding/
  README.md         Lernpfad + Notizen zu Linus' Vorgehen
  Makefile          Floppy bauen, QEMU starten, Screenshot
  stage1/
    boot.asm        Bootsektor: nachladen, Real->Protected Mode
    kernel.asm      GDT, IDT, PIC, 2x TSS, Timer-Handler, Task A/B
```

Verifikations-Hilfe (alle Schritte): QEMU headless starten, Screenshot ziehen:
```
qemu-system-i386 -fda floppy.img -display none \
  -monitor stdio <<< 'screendump out.ppm'
```
Frühe Schritte zusätzlich: `-serial stdio` für Debug-Bytes.

---

### Task 1a: Bootsektor lebt

**Dateien:** Create `stage1/boot.asm`, `Makefile`, `README.md`

- [ ] **Schritt 1: boot.asm** — 512B, `org 0x7C00`, BIOS-Teletype `int 0x10`
  (AH=0x0E) gibt z.B. `'L'` aus, dann `hlt`/Endlosschleife. Boot-Signatur
  `dw 0xAA55` an Offset 510 (`times 510-($-$$) db 0`).
- [ ] **Schritt 2: Makefile** — `nasm -f bin boot.asm -o boot.bin`; Floppy:
  `dd if=/dev/zero of=floppy.img bs=512 count=2880`, dann `boot.bin` in Sektor 0.
- [ ] **Schritt 3: Build** — `make`. Erwartung: `floppy.img` (1.44MB) entsteht.
- [ ] **Schritt 4: Run** — `qemu-system-i386 -fda floppy.img`. Erwartung: `L`
  oben links auf dem Schirm.
- [ ] **Schritt 5:** README mit Schritt-Notiz ergänzen.

### Task 1b: VGA direkt beschreiben

**Dateien:** Modify `stage1/boot.asm`

- [ ] **Schritt 1:** Statt BIOS-Teletype direkt in VGA-Textpuffer schreiben:
  Segment 0xB800, Offset 0 → Byte = ASCII, Byte+1 = Attribut (z.B. 0x0A grün).
  ```nasm
  mov ax, 0xB800
  mov es, ax
  mov word [es:0], 0x0A41   ; 'A' grün
  ```
- [ ] **Schritt 2: Run** — Erwartung: grünes `A` oben links. Beweist direkte
  Bildschirmkontrolle ohne BIOS — das Fundament für Task A/B.

### Task 1c: Protected Mode

**Dateien:** Modify `stage1/boot.asm`; Create `stage1/kernel.asm`

- [ ] **Schritt 1: Kernel nachladen** — vor Moduswechsel mit `int 0x13` (AH=0x02)
  weitere Sektoren ab Sektor 2 nach z.B. 0x1000 laden (kernel.asm landet dort).
- [ ] **Schritt 2: A20-Gate** aktivieren (Fast-A20 via Port 0x92: `in al,0x92;
  or al,2; out 0x92,al`).
- [ ] **Schritt 3: GDT** — drei Einträge: Null, Code (base 0, limit 4G, 0x9A,
  0xCF), Daten (0x92, 0xCF). `lgdt [gdt_descriptor]`.
- [ ] **Schritt 4: Moduswechsel** — `mov eax,cr0; or eax,1; mov cr0,eax`, dann
  `jmp 0x08:protected_start` (Far Jump leert die Prefetch-Pipeline).
- [ ] **Schritt 5: 32-bit** — Datensegmente auf 0x10 setzen, Stack setzen, nach
  kernel.asm springen. kernel.asm schreibt 32-bit ein Zeichen nach 0xB8000.
- [ ] **Schritt 6: Run** — Erwartung: Zeichen erscheint, kein Reboot-Loop
  (Triple-Fault). Beweist: wir sind im 32-bit Protected Mode.

### Task 1d: Timer-Interrupt

**Dateien:** Modify `stage1/kernel.asm`

- [ ] **Schritt 1: IDT** — 256 Einträge (8B), Interrupt-Gate für Vektor 0x20
  (IRQ0) auf den Timer-Handler. `lidt [idt_descriptor]`.
- [ ] **Schritt 2: PIC remappen** — 8259 Master/Slave per ICW1–4 (Ports
  0x20/0x21, 0xA0/0xA1) auf Vektoren 0x20–0x2F (sonst kollidiert IRQ0 mit
  CPU-Exception 8). Nur IRQ0 demaskieren (`mov al,0xFE; out 0x21,al`).
- [ ] **Schritt 3: Timer-Handler** — erhöht einen Zähler / schreibt rotierendes
  Zeichen nach 0xB8000, sendet EOI (`mov al,0x20; out 0x20,al`), `iret`.
- [ ] **Schritt 4:** `sti`, dann Endlosschleife `hlt`.
- [ ] **Schritt 5: Run** — Erwartung: sichtbar laufender Zähler/Blinken. Beweist:
  IRQ0 feuert periodisch.

### Task 1e: Hardware-Task-Switch A/B

**Dateien:** Modify `stage1/kernel.asm`

- [ ] **Schritt 1: Zwei TSS** — je ein 104-Byte TSS für Task A und Task B; EIP,
  ESP, EFLAGS, CS/DS/SS-Selektoren, CR3 vorbelegen. Eigene Stacks je Task.
- [ ] **Schritt 2: TSS-Deskriptoren** in die GDT (Typ 0x89, available 32-bit
  TSS). Selektoren z.B. 0x18 (A), 0x20 (B).
- [ ] **Schritt 3: Task A / Task B** — Endlosschleifen: A schreibt `'A'`, B
  schreibt `'B'` nach 0xB8000 (fortlaufende Position).
- [ ] **Schritt 4: Initial-Task laden** — `ltr` mit Selektor von Task A, in Task A
  starten.
- [ ] **Schritt 5: Timer-Handler → Task-Switch** — bei jedem Tick `jmp far`
  auf den jeweils anderen TSS-Selektor (Hardware-Task-Switch sichert/lädt den
  kompletten CPU-Zustand). EOI nicht vergessen.
- [ ] **Schritt 6: Run** — Erwartung: `ABABAB...` füllt den Schirm. **Etappe 1
  fertig — Linus' erstes Programm läuft.**
- [ ] **Schritt 7:** README mit dem fertigen Ergebnis + kurzer Erklärung des
  Hardware-Task-Switchings ergänzen.

---

## Hinweis zur Ausführung

Der vollständige, getestete Assembler-Code entsteht pro Schritt bei der Ausführung
und wird sofort in QEMU verifiziert — bei Bare-Metal ist iteratives Testen am
echten (emulierten) Prozessor der einzige verlässliche Weg. Jeder Schritt wird
erklärt, damit Linus' Denkweise nachvollziehbar bleibt.
