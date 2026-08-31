# pi-bluetooth-configuration-client-mac

A small macOS app to configure WiFi on a Raspberry Pi running
[pi-bluetooth-configuration](https://github.com/jacohanekom/pi-bluetooth-configuration-alpine)
over Bluetooth LE, using the Mac's own Bluetooth adapter. Scans for the
Pi, connects (no pairing -- see Security below), lets you pick or type a
network, and shows live connect status -- no SSH, no keyboard on the Pi.

Built with SwiftUI + CoreBluetooth, packaged with plain Swift Package
Manager (no Xcode project).

The Raspberry Pi 3's onboard Bluetooth chip shares a single antenna with
its WiFi radio, so BLE connections routinely drop once the Pi's WiFi is
actively passing traffic -- a hardware limitation of that chip, not a
bug in this app or the daemon. So this app hands off: once the Pi
reports a connected state with an IP address (still over BLE, since
that's the only channel that exists at that point), it switches to
polling the Pi's plain TCP control interface on the LAN for everything
else, and a subsequent BLE disconnect is treated as expected rather than
an error. See `NetworkControlClient.swift` and the daemon's README
("WiFi/Bluetooth coexistence and the TCP handoff").

## Security

There is no pairing, encryption, or authentication anywhere in this
flow -- not on the BLE service, not on the TCP handoff. WiFi SSID and
password cross BLE in the clear to any device that connects while the
Pi is advertising. This was a deliberate choice made after BLE
pairing/bonding proved unreliable on the Pi 3's hardware (see the
daemon's README, "Security model", for the full reasoning). Use this
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

1. Launch the app. It scans automatically for devices advertising
   `pi-bluetooth-configuration`'s GATT service and lists them.
2. Click a device to connect -- no pairing step, connecting is enough
   (see Security above for what that trades away). If the link drops
   unexpectedly (the Pi 3's Bluetooth hardware has known stability
   issues independent of pairing), the app retries automatically (up to
   3 times, 1s apart) before surfacing an error.
3. Optionally click **Scan Networks** and tap a result to fill in the
   SSID field, or just type the SSID directly.
4. Enter the password (leave blank for an open network) and click
   **Connect**.
5. Watch the status line -- it updates live via GATT notifications as
   the Pi progresses through `connecting` → `connected` (with the
   assigned IP) or `failed` (with an error message).
6. Once `connected` with an IP shows up, the small badge above the
   status line switches from "Managing over Bluetooth" to "Managing
   over WiFi (ip)" -- the app has handed off to the Pi's TCP control
   interface at that point, polling it every 2s. A BLE disconnect after
   this point is normal (see above) and won't reset the UI.
7. **Forget** clears whatever network the Pi last configured through
   this daemon, over whichever channel (BLE or network) is currently
   active.

## Protocols

Two, matching whichever channel is active -- see
[pi-bluetooth-configuration-alpine's README](https://github.com/jacohanekom/pi-bluetooth-configuration-alpine)
for both in full:

- **GATT** (`Models.swift` has the exact UUIDs/JSON shapes) -- used from
  first connection until the Pi reports an IP.
- **TCP** (`NetworkControlClient.swift`) -- one JSON object per line,
  same commands (`status`/`scan`/`scanresults`/`connect`/`forget`) as
  the BLE Command characteristic, just addressed at the Pi's IP on port
  `8567` instead of via GATT. Unauthenticated, same as the daemon side --
  see its README before relying on this on an untrusted network.

## Known limitations (v1)

- One connection at a time -- connecting to a new device disconnects
  the previous one (and tears down any active network handoff first).
- No persisted list of previously-seen Pis; every launch re-scans.
- No pairing/encryption at all -- see Security above.
- Not code-signed or notarized; Gatekeeper may warn if you ever
  distribute the built binary outside of building it yourself.
- The network handoff polls status every 2s rather than pushing updates
  -- if the Pi's IP changes (DHCP renewal to a different address) while
  connected, the app won't notice; disconnect and reconnect via BLE.
