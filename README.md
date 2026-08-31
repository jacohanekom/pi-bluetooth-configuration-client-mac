# pi-bluetooth-configuration-client-mac

**aipicam configuration** -- a small macOS app to configure WiFi on a
Raspberry Pi running
[pi-bluetooth-configuration](https://github.com/jacohanekom/pi-bluetooth-configuration-alpine)
over Bluetooth LE, using the Mac's own Bluetooth adapter. The repo and
underlying binary/bundle identifier keep their original names; "aipicam
configuration" is the app's display name/branding (`CFBundleName` /
`CFBundleDisplayName` in `Info.plist`) -- what shows in the Dock, window
title bar, and About panel.

Scans for nearby devices (shown by hardware serial number, so multiple
units are distinguishable), connects (no pairing -- see Security below),
walks through a short wizard to scan for and join a WiFi network, and
shows live connect status -- no SSH, no keyboard on the Pi.

Built with SwiftUI + CoreBluetooth, packaged with plain Swift Package
Manager (no Xcode project).

This is a one-shot provisioning flow, not a managed session: the Pi
reboots itself a few seconds after a successful connect or a reset (see
the daemon's README, "One-shot provisioning and reboot behavior"). This
app doesn't try to keep managing anything over the network once that
happens -- once the Pi reports its WiFi is connected, it just shows the
network name and IP plus a **Reset** button, and treats the BLE
disconnect that follows the reboot as expected, not an error.

## Security

There is no pairing, encryption, or authentication anywhere in this
flow. WiFi SSID and password cross BLE in the clear to any device that
connects while the Pi is advertising. This was a deliberate choice made
after BLE pairing/bonding proved unreliable on the Pi 3's hardware (see
the daemon's README, "Security model", for the full reasoning). Use this
only on a trusted home/lab network, during a provisioning window you
control.

## Requirements

- macOS 13 (Ventura) or later, with Bluetooth on
- A Pi running `pi-bluetooth-configuration`, advertising and reachable

## Download a release

Every push builds `pi-bluetooth-configuration-client-mac-macos.zip`
(GitHub Actions artifact; tagged `v*` pushes also attach it to a
[GitHub Release](https://github.com/jacohanekom/pi-bluetooth-configuration-client-mac/releases)).
It's an ad-hoc-signed `.app` -- not notarized, no Developer ID -- so a
browser download will carry the quarantine flag and Gatekeeper will
refuse to open it normally the first time:

```sh
unzip pi-bluetooth-configuration-client-mac-macos.zip
xattr -d com.apple.quarantine pi-bluetooth-configuration-client-mac.app   # or right-click -> Open
open pi-bluetooth-configuration-client-mac.app
```

## Run without building an app bundle (fastest, for development)

```sh
swift build
swift run pi-bluetooth-configuration-client-mac
```

This runs the bare SPM executable, not a `.app`. It still gets a working
Bluetooth permission prompt via `NSBluetoothAlwaysUsageDescription`
embedded directly into the binary's Mach-O `__info_plist` section (see
`Package.swift`) -- CoreBluetooth requires that string to exist
somewhere, bundle or not.

## Build a proper .app bundle

```sh
make app
open pi-bluetooth-configuration-client-mac.app
```

`make app` release-builds the executable, assembles a standard
`Contents/MacOS` + `Contents/Info.plist` bundle
(`scripts/build_app.sh`), and ad-hoc code-signs it (`codesign --sign -`)
so macOS treats every rebuild as the same stable app identity -- without
that, Gatekeeper/TCC would re-prompt for Bluetooth access on every
rebuild, since an unsigned binary's identity is its exact bytes. The
bundle isn't notarized or signed with a real Developer ID, so macOS may
still show an "unidentified developer" warning the first time you open
it (right-click → Open, or allow it in System Settings → Privacy &
Security).

Once built, `pi-bluetooth-configuration-client-mac.app` behaves like any
other Mac app -- it can be dragged into `/Applications`, launched from
Spotlight, etc.

`make run` builds the bundle and opens it in one step. `make clean`
removes both `.build/` and the `.app`.

## Using it

1. Launch the app. It scans automatically for devices advertising the
   WiFi-configuration GATT service and lists them by hardware serial
   number.
2. Click a device to connect -- no pairing step, connecting is enough
   (see Security above for what that trades away). If the link drops
   unexpectedly (the Pi 3's Bluetooth hardware has known stability
   issues independent of pairing), the app retries automatically (up to
   3 times, 1s apart) before surfacing an error.
3. **If the Pi already has WiFi configured**, you land straight on a
   details view: network name, IP address, and a **Reset** button. Skip
   to step 7.
4. **Otherwise**, a short wizard starts automatically:
   - It scans for networks right away (spinner, no button to press).
   - Pick one from the list, or **Enter Network Manually** for a hidden
     network.
5. Enter the password (leave blank for an open network) and click
   **Connect**. A status line shows live progress
   (`connecting` → `connected`/`failed`); on failure, edit and retry, or
   **◀** back to the network list to try a different one.
6. Once connected, the view switches to the same details screen as step
   3 -- network name, IP, and a note that the Pi is about to reboot to
   finish applying the change. The BLE connection dropping a few seconds
   later is expected, not an error.
7. **Reset** removes the network the Pi last configured and reboots it
   the same way (this sends the same `forget` command the daemon's GATT
   protocol always had -- "Reset" is just how this app labels it). Only
   shown once WiFi is actually connected: resetting only makes sense
   once there's something to reset.

## Protocol

Talks directly to the GATT service documented in
[pi-bluetooth-configuration-alpine's README](https://github.com/jacohanekom/pi-bluetooth-configuration-alpine)
-- `Models.swift` has the exact UUIDs and JSON shapes. This client
doesn't add any protocol of its own.

## Known limitations (v1)

- One connection at a time -- connecting to a new device disconnects
  the previous one.
- No persisted list of previously-seen Pis; every launch re-scans.
- No pairing/encryption at all -- see Security above.
- Not code-signed or notarized; Gatekeeper may warn if you ever
  distribute the built binary outside of building it yourself.
