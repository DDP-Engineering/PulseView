PulseView / sigrok-cli for the Hantek DSO-3062L and ALIENTEK ATK DL16
Linux x86_64 AppImage - built 66540df
======================================================================

Source revision: 66540df

Fully self-contained: Qt5, glib, boost, libftdi, libusb, hidapi, libzip and
python3 are all bundled inside the AppImage itself. Nothing needs to be
installed - no apt, no network, no root.

The x86_64 build targets 64-bit Intel/AMD Linux systems with glibc 2.35
or newer, including Ubuntu 22.04 and Debian 12 (Bookworm).

sigrok-cli runs with no host libraries at all. PulseView additionally needs
the host's own graphics driver (libGL and an X11/Wayland display) - that is
deliberate and universal to AppImages: those libraries have to match the
kernel driver, so bundling them breaks hardware acceleration. Any machine
with a screen already has them.

Run:
  chmod +x PulseView-x86_64.AppImage
  ./PulseView-x86_64.AppImage                    # GUI
  ./PulseView-x86_64.AppImage --cli --driver hantek-dso3062l --scan
  ./PulseView-x86_64.AppImage --cli --driver atk-dl16 --scan

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
  revision 66540df. There is no separate written offer to make: the
  source is published alongside the binary.
