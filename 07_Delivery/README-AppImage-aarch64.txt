PulseView / sigrok-cli for the Hantek DSO-3062L and ALIENTEK ATK DL16
Linux aarch64 AppImage - built b6d0e8e-dirty
======================================================================

Source revision: b6d0e8e-dirty

Fully self-contained: Qt5, glib, boost, libftdi, libusb, hidapi, libzip and
python3 are all bundled inside the AppImage itself. Nothing needs to be
installed - no apt, no network, no root.

The aarch64 build targets the Raspberry Pi 4 and 5 on a 64-bit OS
(Raspberry Pi OS Bookworm or newer, Ubuntu 22.04 or newer). A 32-bit OS
cannot run it.

sigrok-cli runs with no host libraries at all. PulseView additionally needs
the host's own graphics driver (libGL and an X11/Wayland display) - that is
deliberate and universal to AppImages: those libraries have to match the
kernel driver, so bundling them breaks hardware acceleration. Any machine
with a screen already has them.

Run:
  chmod +x PulseView-aarch64.AppImage
  ./PulseView-aarch64.AppImage                    # GUI
  ./PulseView-aarch64.AppImage --cli --driver hantek-dso3062l --scan
  ./PulseView-aarch64.AppImage --cli --driver atk-dl16 --scan

Device access (once, needs root - the one thing that cannot be bundled,
being a kernel-level permission rather than a library):
  sudo cp 60-sigrok-instruments.rules /etc/udev/rules.d/
  sudo udevadm control --reload && sudo udevadm trigger
  (add yourself to the plugdev group if needed, then re-login)

Capabilities and notes are identical to the Windows build; see the project
protocol reference. Use -O srzip (not CSV) for triggered captures.
