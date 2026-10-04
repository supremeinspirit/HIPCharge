# Changelog

## 1.5.0

### New
- **Legacy release for rootful iOS 12–14** (`HIPCharge_1.5.0_legacy-rootful_iphoneos-arm.deb`). These iOS versions have no Simulate HIP setting, so a small tweak in `thermalmonitord` (`HIPChargeTM`) keeps HIP engaged while charging, with the screen on or off, including during video and calls. When unplugged, HIP behaves normally. The tweak finds its methods by name and does nothing if they're missing. Built for arm64 and arm64e. Requires Substrate/Substitute.
- Release files now say which jailbreak they're for: `_rootless_` (iOS 15+) and `_legacy-rootful_` (iOS 12–14).

### Fixed
- **No banner on iOS 15 before iOS 16:** the charge-awareness notification section HIPCharge used doesn't exist there. The daemon now falls back to the Optimized Battery Charging section.
- **HIP off after a `thermalmonitord` restart while charging:** `thermalmonitord` resets Simulate HIP whenever it starts (at boot, or after a crash), which left HIP off until the next plug-in. The daemon now notices the restart and turns Simulate HIP back on if the device is charging. Changing it yourself in Battman is still respected.

### Changed
- New package identifier `com.supremeinspirit.hipcharge` (launch daemon `com.supremeinspirit.hipcharge.plist`). **Remove HIPCharge 1.4.0 before installing 1.5.0.**

## 1.4.0
- Banner posted from the daemon through iOS's charge-awareness notification section, without SpringBoard injection.
- Turns Simulate HIP on while charging and off when unplugged (rootless, iOS 15+).
