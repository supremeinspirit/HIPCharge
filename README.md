# HIPCharge

Keeps **HIP** (Hot-in-Pocket thermal mitigation) active while the device is charging and returns it to normal when it's unplugged. Each change also posts a Notification Center banner.

## Releases

| File | Jailbreak | iOS | How HIP is forced |
|---|---|---|---|
| `HIPCharge_<version>_rootless_iphoneos-arm64.deb` | rootless (e.g. Dopamine) | 15+ | Turns **Simulate HIP** on/off |
| `HIPCharge_<version>_legacy-rootful_iphoneos-arm.deb` | rootful (e.g. unc0ver, checkra1n) | 12–14 | Small tweak in `thermalmonitord` (needs Substrate/Substitute) |

Tested on iOS 17.3 (rootless), iOS 15.2.1 (rootless) and iOS 13.3 (rootful, iPhone X). On A12 and newer phones running iOS 12–13, the legacy tweak's arm64e slice may not load.

## How it works

- `hipchargd` listens for power-source changes through `IOPSNotificationCreateRunLoopSource` and posts the banner from the daemon itself through iOS's own PowerUI notification section, so it doesn't inject anything into SpringBoard.
- **Rootless (iOS 15+):** sets the `simulateHip` key in `OSThermalStatus.plist` through SystemConfiguration (`SCPreferences`), the same setting [Battman](https://github.com/Torrekie/Battman) toggles. With it on, `thermalmonitord` keeps HIP engaged no matter whether the screen is on or audio is playing. `thermalmonitord` resets the key whenever it restarts, so the daemon re-applies it if that happens while charging.
- **Legacy (iOS 12–14):** these versions have no `simulateHip`. `thermalmonitord` turns HIP off while the screen is on, audio is playing or the device is connected to power. While charging, the `HIPChargeTM` tweak makes those three checks (`-[ContextInPocket backlightIsOn/audioIsOn/connectedExternally]`) report NO, so HIP stays engaged the same way. When unplugged, HIP behaves normally. The methods are looked up by name, without fixed addresses, and the tweak does nothing if they're missing.

## Install

Download the matching `.deb` from [Releases](../../releases) and install it with your package manager, or run:

```sh
dpkg -i HIPCharge_*_rootless_iphoneos-arm64.deb        # rootless, iOS 15+
dpkg -i HIPCharge_*_legacy-rootful_iphoneos-arm.deb    # rootful, iOS 12–14
```

The `postinst` script loads the daemon right away, and `prerm` unloads it when you remove the package. On the legacy package, run `killall thermalmonitord` (or reboot) after installing so the tweak loads.

**Upgrading from 1.4.0:** the package identifier changed in 1.5.0, so remove HIPCharge 1.4.0 first, then install 1.5.0.

## Build (on device)

You need `clang`, `ldid`, `dpkg-deb`, and an iPhoneOS SDK at `/var/jb/usr/share/SDKs/iPhoneOS.sdk` (or pass `SDK=...`).

```sh
make deb          # rootless package
make legacy-deb   # legacy rootful package
```

See [CHANGELOG.md](CHANGELOG.md) for release notes.
