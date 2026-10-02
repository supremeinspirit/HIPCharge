// HIPCharge: enable Battman's "Simulate HIP" while charging, disable it otherwise.
// Uses the same OSThermalStatus SCPreferences keys as Battman (scprefs/wrapper.c).

#include <CoreFoundation/CoreFoundation.h>
// SCPreferences is marked unavailable in the iOS SDK headers, so declare what we use
typedef const struct __SCPreferences *SCPreferencesRef;
extern SCPreferencesRef SCPreferencesCreate(CFAllocatorRef allocator, CFStringRef name, CFStringRef prefsID);
extern Boolean SCPreferencesSetValue(SCPreferencesRef prefs, CFStringRef key, CFPropertyListRef value);
extern Boolean SCPreferencesCommitChanges(SCPreferencesRef prefs);
extern Boolean SCPreferencesApplyChanges(SCPreferencesRef prefs);
extern int SCError(void);
extern const char *SCErrorString(int status);
enum { kSCStatusOK = 0, kSCStatusFailed = 1001 };
// IOKit/ps headers are not in the iOS SDK
typedef void (*IOPowerSourceCallbackType)(void *context);
extern CFTypeRef IOPSCopyPowerSourcesInfo(void);
extern CFStringRef IOPSGetProvidingPowerSourceType(CFTypeRef snapshot);
extern CFRunLoopSourceRef IOPSNotificationCreateRunLoopSource(IOPowerSourceCallbackType callback, void *context);
#define kIOPMACPowerKey "AC Power"
#include <os/log.h>
#include "banner.h"
#include <stdbool.h>

static os_log_t gLog;
static int lastState = -1;

static int setSimulateHIPEnabled(bool enable) {
	SCPreferencesRef prefs = SCPreferencesCreate(kCFAllocatorDefault, CFSTR("OSThermalStatus"), CFSTR("OSThermalStatus.plist"));
	if (!prefs) {
		os_log_error(gLog, "unable to open OSThermalStatus.plist");
		return kSCStatusFailed;
	}
	SCPreferencesSetValue(prefs, CFSTR("simulateHip"), enable ? kCFBooleanTrue : kCFBooleanFalse);
	int ret = kSCStatusOK;
	if (SCPreferencesCommitChanges(prefs)) {
		(void)SCPreferencesApplyChanges(prefs);
	} else {
		ret = SCError();
		os_log_error(gLog, "SCPreferencesCommitChanges failed: %s", SCErrorString(ret));
	}
	CFRelease(prefs);
	return ret;
}

static bool isCharging(void) {
	CFTypeRef info = IOPSCopyPowerSourcesInfo();
	if (!info) return false;
	CFStringRef type = IOPSGetProvidingPowerSourceType(info);
	bool onAC = type && CFEqual(type, CFSTR(kIOPMACPowerKey));
	CFRelease(info);
	return onAC;
}

static void update(void *ctx) {
	int state = isCharging();
	if (state == lastState) return;
	bool initial = lastState == -1;
	lastState = state;
	int ret = setSimulateHIPEnabled(state);
	os_log(gLog, "power %s -> simulate HIP %s (status %d)", state ? "connected" : "disconnected", state ? "on" : "off", ret);
	// No banner for the startup check (SpringBoard may not be up yet at boot)
	if (initial) return;
	showBanner(ret != kSCStatusOK ? "Failed to change Simulate HIP"
		: state ? "Charging: Simulate HIP ON" : "Unplugged: Simulate HIP OFF");
}

int main(void) {
	gLog = os_log_create("com.flo.hipcharge", "daemon");
	CFRunLoopSourceRef src = IOPSNotificationCreateRunLoopSource(update, NULL);
	if (!src) {
		os_log_error(gLog, "IOPSNotificationCreateRunLoopSource failed");
		return 1;
	}
	CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
	update(NULL);
	CFRunLoopRun();
	return 0;
}
