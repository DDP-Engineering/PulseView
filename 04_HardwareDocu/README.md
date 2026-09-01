# Hardware documentation

Hardware operating, assembly, interface, and verification documentation.

## Licensing: read this before redistributing anything here

This directory holds two kinds of material with **different owners and
different licences**. They are not interchangeable, and the repository's
top-level licence does not reach both.

### 1. Manufacturer reference material — third-party, not ours to licence

The following are **supplied by the instrument manufacturers**. They are
vendor-issued reference drivers, SDKs and product documentation, redistributed
here unmodified as the reference against which this project's own drivers were
developed and checked.

| Path | What it is |
|---|---|
| `Hantek_DSO3062L/SDK_3062L/` | Hantek's DSO-3062L SDK: `Dll/` (`HTHardDLL.dll`, `HTSoftDll.dll`, `HTDisplayDll.dll`), `HeadFiles/`, `Lib/`, `Code Demo/` (VC, VB and LabVIEW samples) and `Manual/` (the six SDK PDFs). |
| `Hantek_DSO3062L/DSO3062L_Driver.zip` | Hantek's Windows device-driver package for the DSO-3062L. |
| `Hantek_DSO3062L/DSO3062_Manual.pdf` | Hantek's DSO-3062 series product manual. |

**These files are NOT under the GNU General Public License and NOT under the
PolyForm Noncommercial License.** They remain the copyright of their respective
manufacturers and are governed solely by the licence terms those manufacturers
supplied with them. Nothing in `LICENSE.txt`, `LICENSE-PolyForm.txt` or
`LICENSING.md` grants any right to them, and this project grants no such right
either — it has none to grant.

Consequences that matter in practice:

- **Do not treat them as GPL.** They cannot be linked into, bundled with, or
  shipped alongside the GPL binaries in `07_Delivery/`, and they are not part of
  the "corresponding source" for any package. None of the delivered packages
  contains any of this material.
- **Do not assume redistribution is permitted.** If you fork or mirror this
  repository, satisfy yourself of the vendor's terms first; obtain the files
  from the manufacturer if in doubt.
- **They are reference only.** No code from these SDKs was copied into this
  project's drivers. The drivers were written from protocol behaviour observed
  on the wire and verified against real hardware; see the analysis documents
  below.

### 2. This project's own protocol analysis — GPL-3.0-or-later

| Path | What it is |
|---|---|
| `Hantek_DSO3062L/Command_Catalogue.md` | Opcode catalogue recovered by this project. |
| `Hantek_DSO3062L/Protocol_Reference.md` | Wire-protocol reference for the DSO-3062L. |
| `ATK_DL16/Protocol_Extraction.md` | Protocol extraction notes for the ALIENTEK ATK DL16. |

These are original work, written to document the GPL drivers in
`05_Software/libsigrok/src/hardware/`, and are licensed under the GNU General
Public License v3.0 or later along with them. See [`LICENSE.txt`](../LICENSE.txt)
and [`LICENSING.md`](../LICENSING.md).

## Device safety

The drivers never write calibration, flash or EEPROM. The protocol references
above record what each opcode does and which ones were deliberately left alone.
