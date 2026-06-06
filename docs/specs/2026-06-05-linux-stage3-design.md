# Etappe 3 -- Disk-Treiber + Minix-Dateisystem

Ziel: Wie Linus 1991 vom CPU-Spielzeug zu einem nutzbaren System -- Dateien
lesen koennen. Konkret: am Ende von Etappe 3 zeigt unser Kernel den Inhalt von
`/hello.txt` (auf einer Minix-FS-Disk in QEMU) auf dem VGA-Schirm.

## Architektur

```
                       ┌─────────────────────────────┐
   "hello.txt"      ──►│  Minix-FS-Code (3d..3f)     │
                       │  Superblock, Inodes, Dirs   │
                       └─────────────┬───────────────┘
                                     │ read_block(nr)
                       ┌─────────────▼───────────────┐
                       │  ATA-Disk-Treiber (3a..3b)  │
                       │  read_sector(lba, buf)      │
                       └─────────────┬───────────────┘
                                     │ Port I/O 0x1F0..
                                     ▼
                               IDE-Disk (QEMU)
```

Saubere Schichtung: das FS kennt nur `read_block(nr, buf)`, der Treiber kennt
nur die Hardware-Ports. Genau das Treiber-Prinzip aus Etappe 2.

## Designentscheidungen

- **Hardware:** IDE/ATA-PIO (Linus' Wahl 1991, ohne BIOS, im Protected Mode).
- **FS-Quelle:** zweite IDE-Disk in QEMU (`-hda minix.img`), Boot bleibt Floppy.
- **FS-Format:** Minix v1, 14-Zeichen-Dateinamen, mit `mkfs.minix` erzeugt.
- **Nur Lesen.** Schreiben (Bitmap-Verwaltung) kam bei Linus auch erst spaeter.
- **Kein Pfad-Parsing.** Wir lesen genau eine Datei aus dem Root-Verzeichnis.

## Mikro-Schritte

```
3a  ATA-Disk erkennen     IDENTIFY DEVICE, Modell-String anzeigen
3b  read_sector(lba,buf)  512-Byte-Sektor in den RAM lesen; Sektor 0 dumpen
3c  Minix-Image bauen     Host-Skript baut mit mkfs.minix ein Test-Image
3d  Superblock + Inode-1  Block 1 parsen, Root-Inode finden
3e  Root-Verzeichnis      Inode 1 -> Datenblock -> Dir-Eintraege auflisten
3f  Datei lesen           hello.txt -> Inode -> Datenbloecke -> auf VGA  ZIEL
```

## Verifikation

- 3a: Modell-String der QEMU-Disk erscheint auf VGA.
- 3b: Erste 16 Bytes vom MBR-Bootblock als Hex.
- 3c: `file minix.img` meldet "Minix filesystem v1".
- 3d: Superblock-Felder (n_inodes, n_zones) als Hex angezeigt.
- 3e: Dateinamen aus Root listet, inkl. "hello.txt".
- 3f: Text aus hello.txt steht auf dem VGA-Schirm.

## Bewusst weggelassen (YAGNI)

VFS, mehrere Mountpoints, mehrstufige Pfade, indirekte Block-Pointer (nur
direkte Pointer reichen fuer <7 KB Dateien), Schreiben, Caching.
