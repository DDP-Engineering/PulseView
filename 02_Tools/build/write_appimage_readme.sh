#!/usr/bin/env bash
# Copyright (c) 2026 DDP Engineering
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
# See the LICENSE.txt file for full license details.
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

[ "$#" -eq 4 ] || {
    echo "usage: write_appimage_readme.sh OUT_FILE ARCH APPIMAGE_NAME REVISION" >&2
    exit 2
}

OUT_FILE="$1"
ARCH="$2"
NAME="$3"
REV="$4"

case "${ARCH}" in
    x86_64)
        COMPATIBILITY="The x86_64 build targets 64-bit Intel/AMD Linux systems with glibc 2.35
or newer, including Ubuntu 22.04 and Debian 12 (Bookworm)."
        ;;
    aarch64)
        COMPATIBILITY="The aarch64 build targets the Raspberry Pi 4 and 5 on a 64-bit OS
(Raspberry Pi OS Bookworm or newer, Ubuntu 22.04 or newer). A 32-bit OS
cannot run it."
        ;;
    *)
        echo "unsupported AppImage README architecture: ${ARCH}" >&2
        exit 2
        ;;
esac

cat > "${OUT_FILE}" <<RM
PulseView / sigrok-cli for the Hantek DSO-3062L and ALIENTEK ATK DL16
Linux ${ARCH} AppImage - built ${REV}
======================================================================

Source revision: ${REV}

Fully self-contained: Qt5, glib, boost, libftdi, libusb, hidapi, libzip and
python3 are all bundled inside the AppImage itself. Nothing needs to be
installed - no apt, no network, no root.

${COMPATIBILITY}

sigrok-cli runs with no host libraries at all. PulseView additionally needs
the host's own graphics driver (libGL and an X11/Wayland display) - that is
deliberate and universal to AppImages: those libraries have to match the
kernel driver, so bundling them breaks hardware acceleration. Any machine
with a screen already has them.

Run:
  chmod +x ${NAME}
  ./${NAME}                    # GUI
  ./${NAME} --cli --driver hantek-dso3062l --scan
  ./${NAME} --cli --driver atk-dl16 --scan

Device access (once, needs root - the one thing that cannot be bundled,
being a kernel-level permission rather than a library):
  sudo cp 60-sigrok-instruments.rules /etc/udev/rules.d/
  sudo udevadm control --reload && sudo udevadm trigger
  (add yourself to the plugdev group if needed, then re-login)

Capabilities and notes are identical to the Windows build; see the project
protocol reference. Use -O srzip (not CSV) for triggered captures.

License:
  PulseView, sigrok-cli, libsigrok and libsigrokdecode are free software
  under the GNU General Public License, version 3 or later. This AppImage
  also bundles Qt, glib, boost, libftdi, libusb, hidapi, libzip and CPython,
  each under its own license; the full texts ship inside the image.

  The complete corresponding source for everything in this AppImage - the
  sigrok stack, this project's drivers and decoders, and the build scripts
  that produced it - is the repository this package was built from, at
  revision ${REV}. There is no separate written offer to make: the
  source is published alongside the binary.
RM
