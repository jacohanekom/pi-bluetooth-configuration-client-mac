# pi-bluetooth-configuration-client-mac

A small macOS app to configure WiFi on a Raspberry Pi running
[pi-bluetooth-configuration](https://github.com/jacohanekom/pi-bluetooth-configuration-alpine)
over Bluetooth LE, using the Mac's own Bluetooth adapter. Scans for the
Pi, pairs, lets you pick or type a network, and shows live connect status
-- no SSH, no keyboard on the Pi.

Built with SwiftUI + CoreBluetooth, packaged with plain Swift Package
Manager (no Xcode project).

## Requirements

- macOS 13 (Ventura) or later, with Bluetooth on
- A Pi running `pi-bluetooth-configuration`, advertising and reachable

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

1. Launch the app. It scans automatically for devices advertising
   `pi-bluetooth-configuration`'s GATT service and lists them.
2. Click a device to connect.
3. The first read/write triggers macOS's normal Bluetooth pairing --
   the Pi's agent uses "Just Works" pairing (`NoInputNoOutput`, since a
   headless Pi has no display/keyboard), so there's no PIN to confirm;
   macOS pairs and encrypts the link automatically. See the daemon's
   README for what that trade-off does and doesn't protect against.
4. Optionally click **Scan Networks** and tap a result to fill in the
   SSID field, or just type the SSID directly.
5. Enter the password (leave blank for an open network) and click
   **Connect**.
6. Watch the status line -- it updates live via GATT notifications as
   the Pi progresses through `connecting` → `connected` (with the
   assigned IP) or `failed` (with an error message).
7. **Forget** clears whatever network the Pi last configured through
   this daemon.

## GATT protocol

Talks directly to the same custom 128-bit-UUID service documented in
[pi-bluetooth-configuration-alpine's README](https://github.com/jacohanekom/pi-bluetooth-configuration-alpine#gatt-service) --
`Models.swift` in this repo has the exact UUIDs and JSON shapes. This
client doesn't add any protocol of its own; it's a thin CoreBluetooth
front end for that GATT service.

## Known limitations (v1)

- One connection at a time -- connecting to a new device disconnects
  the previous one.
- No persisted list of previously-seen Pis; every launch re-scans.
- Pairing/bonding state is entirely macOS's own Bluetooth stack's
  business -- this app doesn't manage the system pairing list. If a Pi
  gets reflashed/re-keyed, remove the stale pairing from
  **System Settings → Bluetooth** if reconnecting ever fails oddly.
- Not code-signed or notarized; Gatekeeper may warn if you ever
  distribute the built binary outside of building it yourself.
