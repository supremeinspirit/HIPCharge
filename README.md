# HIPCharge

A small launch daemon for rootless-jailbroken iOS 15+ devices. It turns **Simulate HIP** on while the device is charging and off again when it's unplugged. Each change also posts a Notification Center banner.

## How it works

- `hipchargd` listens for power-source changes through `IOPSNotificationCreateRunLoopSource`.
- When the charging state changes, it updates the Simulate HIP preference through SystemConfiguration (`SCPreferences`).
- It posts the banner from the daemon itself, using iOS's own charge-awareness notification section, so it doesn't inject anything into SpringBoard.

## Install

Download the `.deb` from [Releases](../../releases) and install it with your package manager, or run:

```sh
dpkg -i com.flo.hipcharge_*_iphoneos-arm64.deb
```

The `postinst` script loads the daemon right away, and `prerm` unloads it when you remove the package.

## Build (on device)

You need `clang`, `ldid`, `dpkg-deb`, and an iPhoneOS SDK at `/var/jb/usr/share/SDKs/iPhoneOS.sdk` (or pass `SDK=...`).

```sh
make deb
```

## Credits

Simulate HIP is the `simulateHip` key in `OSThermalStatus.plist`, the same setting [Battman](https://github.com/Torrekie/Battman) toggles.
