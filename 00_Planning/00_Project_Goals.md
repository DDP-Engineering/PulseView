# Project goals: Hantek DSO3062L integration for PulseView

## Objective

Create an integration that makes the Hantek DSO3062L available in
[PulseView](https://sigrok.org/wiki/PulseView), the Qt-based sigrok user
interface for logic analyzers, oscilloscopes, and mixed-signal instruments.

The integration should use the Hantek DSO3062L SDK as the authoritative source
for device capabilities and should follow the extension points and conventions
of the sigrok/PulseView ecosystem.

## Functional scope

### Logic-analyzer mode

- Discover and expose supported digital channels.
- Enable and disable individual digital channels.
- Configure digital-channel threshold settings where supported by the device.
- Configure simple triggers.
- Configure complex triggers, subject to the trigger expressions and capture
  modes supported by both the SDK and the sigrok integration layer.

### Oscilloscope mode

- Discover and expose supported analog channels.
- Enable and disable individual analog channels.
- Set the acquisition timebase.
- Set volts per division for each applicable analog channel.
- Configure oscilloscope triggering.

### Additional SDK capabilities

Identify every relevant Hantek DSO3062L SDK capability and integrate the
capabilities that are useful, stable, and compatible with the PulseView/sigrok
architecture. Examples may include acquisition controls, coupling, probe
settings, sample-rate configuration, device status, calibration, and waveform
transfer; the final list must be based on the actual SDK documentation and
device testing.

## Platforms and delivery

- Target Windows and Linux deployments where the Hantek SDK, USB transport,
  build dependencies, and sigrok integration path permit it.
- Treat Linux support as a feasibility and validation objective until the SDK
  license, binary availability, dependencies, and device operation have been
  confirmed on Linux.
- Provide repeatable scripts to build and assemble delivery artifacts for each
  supported platform.
- Document prerequisites, build inputs, output locations, and verification
  steps for every delivery script.

## Acceptance direction

The integration is complete only when a connected DSO3062L can be used from
PulseView to perform the supported logic-analyzer and oscilloscope operations,
with device-backed validation recorded for each platform. Unsupported SDK
features, platform limitations, and any feature gaps between the SDK and
sigrok/PulseView must be explicitly documented.

## Initial investigation

Before implementation, confirm:

1. The SDK's supported operating systems, license terms, device protocol, and
   redistributable dependencies.
2. The appropriate sigrok integration layer and its capability model.
3. The DSO3062L's actual channel, trigger, threshold, timebase, and voltage
   configuration limits.
4. A reproducible Windows build and the viability of an equivalent Linux build.
