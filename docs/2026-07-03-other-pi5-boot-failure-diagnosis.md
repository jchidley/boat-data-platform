# Other Pi 5 boot failure diagnosis - 2026-07-03

## Reported symptom

The other Pi 5 shows only the red power LED:

- no green ACT LED activity reported;
- no serial output reported;
- SD card had previously been prepared on `pi5nvme` for verbose serial boot output.

## SD card state from previous inspection

When the SD card was attached to `pi5nvme`, it looked structurally bootable:

- boot FAT partition present and readable;
- root ext4 partition present and clean;
- boot FAT dirty bit was fixed;
- `cmdline.txt` root `PARTUUID` matched the SD root partition;
- Pi 5 kernels/DTBs were present;
- serial output was enabled in boot config and kernel command line.

Serial diagnostic changes made previously:

- `enable_uart=1`
- `uart_2ndstage=1`
- kernel consoles on `ttyAMA10`, `serial0`, and `tty1`
- gettys enabled for `ttyAMA10` and `serial0`
- quiet/splash removed; `systemd.show_status=1 loglevel=7` added

## Current check from `pi5nvme`

At the time of this follow-up, the SD card is not attached to `pi5nvme`; only the NVMe boot disk is visible. So I cannot re-check or rewrite the card until it is reinserted.

`pi5nvme` currently sees the MasterBus USB Link again, but the MasterBus bridge remains stopped/disabled. The raw importer remains inactive and disabled.

## Interpretation

If the other Pi 5 truly gives red LED only, with no ACT flicker and no UART output, it is failing before Linux and probably before the SD card's boot config/kernel command line are used.

That makes the serial changes on the SD card unlikely to help unless the bootloader is at least reading the card.

Most likely causes, in order:

1. power supply/cable issue;
2. SD card not being detected by that Pi 5: seating, contacts, slot fault;
3. corrupted/misconfigured Pi 5 EEPROM bootloader;
4. Pi 5 hardware fault.

## Next decisive test

Use a dedicated Raspberry Pi 5 bootloader recovery SD card:

- Raspberry Pi Imager -> Misc utility images -> Raspberry Pi 5 Bootloader -> SD Card Boot.
- Boot the failed Pi 5 with only power + recovery SD attached.

Expected result if the Pi, PSU, and SD slot are basically alive:

- green ACT activity;
- HDMI green screen if a display is connected.

If the recovery SD also gives red LED only/no ACT/no serial, the evidence strongly points to power, SD slot, or board hardware failure rather than this operating-system SD card.

## Do not overwrite the prepared OS SD

The OS SD previously checked on `pi5nvme` looked bootable. Use a spare card for EEPROM recovery if possible.
