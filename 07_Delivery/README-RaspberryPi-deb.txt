Copyright (c) 2026 DDP Engineering
Licensed under PolyForm Noncommercial 1.0.0 (LICENSE.txt).

PulseView for Raspberry Pi 4/5 - Debian installer
=================================================

Package: pulseview-ddp_0.5.0+gitb6d0e8e.dirty_arm64.deb
Source revision: b6d0e8e-dirty
Architecture: arm64 (64-bit Raspberry Pi OS only)

Install:
  sudo apt install ./pulseview-ddp_0.5.0+gitb6d0e8e.dirty_arm64.deb

Start:
  PulseView from the desktop application menu, or: pulseview
  Command line: sigrok-cli --version

The package installs both project USB drivers, protocol decoders, and udev
rules. It conflicts with Raspberry Pi OS's pulseview and sigrok-cli packages
because it owns the standard command names. The AppImage remains available
when an install-free package is preferred.

Remove:
  sudo apt remove pulseview-ddp
