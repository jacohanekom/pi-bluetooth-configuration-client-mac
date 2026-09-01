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
and walks through a wizard: pick a WiFi network, enter its password,
confirm eth0's local network (gateway IP + DHCP range), then finish --
no SSH, no keyboard on the Pi.

Built with SwiftUI + CoreBluetooth, packaged with plain Swift Package
Manager (no Xcode project).

This is a one-shot provisioning flow, not a managed session: the Pi
reboots itself a few seconds after **Finish** or a reset (see the
daemon's README, "One-shot provisioning and reboot behavior"). This app
doesn't try to keep managing anything over the network once that
happens -- once setup is finished, it just shows the WiFi and local
network details plus a **Reset** button, and treats the BLE disconnect
that follows the reboot as expected, not an error.

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
3. **If setup already finished on this Pi**, you land straight on the
   details view: WiFi network/IP, the local network's gateway IP + DHCP
   range, whatever's currently allocated to devices plugged into
   `eth0`, and a **Reset** button. Skip to step 8.
4. **Otherwise**, a wizard starts automatically:
   - It scans for networks right away (spinner, no button to press).
   - Pick one from the list, or **Enter Network Manually** for a hidden
     network.
5. Enter the password (leave blank for an open network) and click
   **Connect**. A status line shows live progress
   (`connecting` → `connected`/`failed`); on failure, edit and retry, or
   **◀** back to the network list to try a different one.
6. Once WiFi joins, the wizard moves to **Local Network Configuration**:
   `eth0` already has a working gateway IP and DHCP server (it's always
   on, from the moment the Pi first boots -- see the daemon's README,
   "Ethernet direct-connect"), prefilled here so you can just confirm
   it, or change the IP/DHCP range if you'd like something different.
7. Click **Finish**. This is what actually concludes setup and reboots
   the Pi a few seconds later -- the BLE connection dropping is
   expected, not an error. Reconnecting afterward lands on the details
   view from step 3.
8. **Reset** removes the network the Pi last configured and reboots it
   the same way (this sends the same `forget` command the daemon's GATT
   protocol always had -- "Reset" is just how this app labels it). Only
   shown once setup has finished: resetting only makes sense once
   there's something to reset. Local network settings aren't touched by
   Reset and become editable again once the wizard restarts.

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
