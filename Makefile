# ============================================================================
# Konfiguration
# ============================================================================
ASM   := nasm
QEMU  := qemu-system-i386

# Welche Version gebaut/gebootet wird. Ueberschreibbar auf der Kommandozeile:
#   make STAGE=1a_bootsektor run
#   make STAGE=1b_vga_direkt shot
STAGE ?= 14b_create

# Stage-Verzeichnis in stage1/2/3 automatisch finden
SRC   := $(wildcard stage*/$(STAGE))
# eigenes Build-Verzeichnis je Stage (sonst verwechselt make die Artefakte)
BUILD := build/$(STAGE)
IMG   := $(BUILD)/floppy.img

BOOTBIN   := $(BUILD)/boot.bin
# leer, wenn der Schritt keinen Kernel hat (1a-1c); sonst Pfad zur kernel.asm
KERNELSRC := $(wildcard $(SRC)/kernel.asm)
KERNELBIN := $(BUILD)/kernel.bin

# Optional: User-Programme (ab Stage 4). ALLE .asm ausser boot/kernel werden zu
# flachen .bin assembliert, damit der Kernel sie per `incbin "name.bin"`
# einbetten kann (-I $(BUILD)). So sind sowohl user.asm (4d/5/6a/6b) als auch
# mehrere getrennte Programme proc_a.asm/proc_b.asm (6c) abgedeckt.
EXTRASRC := $(filter-out $(SRC)/boot.asm $(SRC)/kernel.asm,$(wildcard $(SRC)/*.asm))
EXTRABIN := $(patsubst $(SRC)/%.asm,$(BUILD)/%.bin,$(EXTRASRC))
ifneq ($(EXTRASRC),)
ASMINC := -I $(BUILD)/
else
ASMINC :=
endif

# user.bin wird zusaetzlich an mkdisk.sh uebergeben (Stage 5: /init.bin)
USERSRC := $(wildcard $(SRC)/user.asm)
USERBIN := $(BUILD)/user.bin

# Optional: per-stage Skript, das eine zusaetzliche Disk (HDD) erzeugt.
# Wird ab Stage 3 verwendet (mkdisk.sh erzeugt z.B. ein Minix-FS-Image).
MKDISK := $(wildcard $(SRC)/mkdisk.sh)
ifneq ($(MKDISK),)
DISK      := $(BUILD)/disk.img
QEMU_DISK := -hda $(DISK)
else
DISK      :=
QEMU_DISK :=
endif

# ============================================================================
# Targets
# ============================================================================

all: $(IMG)

$(BUILD):
	mkdir -p $(BUILD)

# Bootsektor zu flachem Binary assemblieren (kein ELF, reine Bytes)
$(BOOTBIN): $(SRC)/boot.asm | $(BUILD)
	$(ASM) -f bin $(SRC)/boot.asm -o $(BOOTBIN)

# User-Programme (user.asm, proc_*.asm, ...) -> flache .bin via Pattern-Rule.
# boot.bin hat eine eigene Regel; kernel.bin wird inline gebaut -> kein Konflikt.
$(BUILD)/%.bin: $(SRC)/%.asm | $(BUILD)
	$(ASM) -f bin $< -o $@

# 1.44 MB Floppy: Bootsektor in Sektor 0; falls vorhanden Kernel ab Sektor 2.
# EXTRABIN (User-Programme) werden VOR dem Kernel gebaut, damit incbin sie sieht.
$(IMG): $(BOOTBIN) $(KERNELSRC) $(EXTRABIN) | $(BUILD)
	dd if=/dev/zero of=$(IMG) bs=512 count=2880 status=none
	dd if=$(BOOTBIN) of=$(IMG) conv=notrunc status=none
ifneq ($(KERNELSRC),)
	$(ASM) $(ASMINC) -f bin $(SRC)/kernel.asm -o $(KERNELBIN)
	dd if=$(KERNELBIN) of=$(IMG) seek=1 conv=notrunc status=none
endif

# Disk-Image bauen, falls die Stage ein mkdisk.sh mitbringt.
# Wenn die Stage zusaetzlich ein user.asm hat, wird user.bin als $2 an mkdisk
# uebergeben (Stage 5 packt es so als /init.bin in das Minix-FS).
ifneq ($(MKDISK),)
ifneq ($(USERSRC),)
$(DISK): $(MKDISK) $(USERBIN) | $(BUILD)
	$(MKDISK) $(DISK) $(USERBIN)
else
# Kein user.asm: mkdisk bekommt das Build-Verzeichnis und sucht sich die
# noetigen Programm-Binaries selbst (Stage 8b: hello.bin, count.bin).
$(DISK): $(MKDISK) $(EXTRABIN) | $(BUILD)
	$(MKDISK) $(DISK) $(BUILD)
endif
endif

# -boot a = direkt von Floppy booten (kein HDD-Versuch -> keine "Boot failed"-Zeile)

# Interaktiv starten (oeffnet ein QEMU-Fenster)
run: $(IMG) $(DISK)
	$(QEMU) -fda $(IMG) $(QEMU_DISK) -boot a

# Interaktiv IM Terminal (VGA-Text als ASCII). Beenden: Alt+2 -> "quit" -> Enter
# (Alt+1 schaltet zurueck zur Anzeige). Notfalls anderes Terminal: pkill qemu
term: $(IMG) $(DISK)
	$(QEMU) -fda $(IMG) $(QEMU_DISK) -boot a -curses

# Wie term, aber seriellen Port (COM1) ans Host-Terminal koppeln.
# Tippen in QEMU -> erscheint auch im Host (und ab 2e umgekehrt).
# Achtung: stdio kann nur EINS bedienen -- hier nimmt es die Serielle. Daher
# fuer die VGA-Anzeige ein eigenes Fenster (kein -curses).
serial: $(IMG) $(DISK)
	$(QEMU) -fda $(IMG) $(QEMU_DISK) -boot a -serial stdio

# Headless: bootet, zieht nach 2 s einen Screenshot (build/out.png), beendet QEMU
shot: $(IMG) $(DISK)
	{ sleep 2; echo 'screendump $(BUILD)/out.ppm'; sleep 1; echo 'quit'; } | \
	  $(QEMU) -fda $(IMG) $(QEMU_DISK) -boot a -display none -monitor stdio
	convert $(BUILD)/out.ppm $(BUILD)/out.png
	@echo "Screenshot -> $(BUILD)/out.png  (STAGE=$(STAGE))"

clean:
	rm -rf build

.PHONY: all run shot clean
