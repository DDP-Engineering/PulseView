# Documentation

Project-level documentation and reference material.

## Documents

- [Environment_Setup.md](Environment_Setup.md) - prerequisites, the two host
  roles, the toolchain image, and every build command.
- [Testing.md](Testing.md) - running the test suite, what each test proves, and
  how to write a new one.
- [Code_Style.md](Code_Style.md) - code and documentation style, and the
  copyright header every new first-party file carries.

## Reference material

Vendor material lives with the device it belongs to, not here. The Hantek SDK,
instrument manual and driver package are in
`04_HardwareDocu/Hantek_DSO3062L/`, alongside the protocol reference and command
catalogue recovered from them. The vendor material is an input to that work, not
an authority on it - what the driver actually sends, and which opcodes are safe,
is what `04_HardwareDocu/<device>/` records.
