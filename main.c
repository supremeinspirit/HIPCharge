// HIPCharge: enable Battman's "Simulate HIP" while charging, disable it otherwise.
// Uses the same OSThermalStatus SCPreferences keys as Battman (scprefs/wrapper.c).
// HIPCHARGE_TWEAK builds (iOS < 15, no simulateHip key) leave that to the HIPChargeTM
// tweak in thermalmonitord and only show the banners.

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
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <string.h>
// libproc.h is not in the iOS SDK
extern int proc_listallpids(void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);

static os_log_t gLog;
static int lastState = -1;

#ifndef HIPCHARGE_TWEAK
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
#endif

#ifndef HIPCHARGE_TWEAK
static pid_t thermalmonitordPID(void) {
	static pid_t pids[4096];
	int n = proc_listallpids(pids, sizeof(pids)) / (int)sizeof(pid_t);
	if (n > (int)(sizeof(pids) / sizeof(pids[0]))) n = sizeof(pids) / sizeof(pids[0]);
	for (int i = 0; i < n; i++) {
		char name[64];
		if (proc_name(pids[i], name, sizeof(name)) > 0 && strcmp(name, "thermalmonitord") == 0) return pids[i];
	}
	return 0;
}
#endif

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
#ifdef HIPCHARGE_TWEAK
	os_log(gLog, "power %s", state ? "connected" : "disconnected");
	if (initial) return;
	showBanner(state ? "Charging: HIP stays active" : "Unplugged: HIP normal");
#else
	int ret = setSimulateHIPEnabled(state);
	os_log(gLog, "power %s -> simulate HIP %s (status %d)", state ? "connected" : "disconnected", state ? "on" : "off", ret);
	// No banner for the startup check (SpringBoard may not be up yet at boot)
	if (initial) return;
	showBanner(ret != kSCStatusOK ? "Failed to change Simulate HIP"
		: state ? "Charging: Simulate HIP ON" : "Unplugged: Simulate HIP OFF");
#endif
}

#ifndef HIPCHARGE_TWEAK
// thermalmonitord rewrites OSThermalStatus.plist with simulateHip off when it (re)starts, e.g.
// at boot or after a crash, which would leave HIP off until the next plug-in. Watch the prefs
// folder for a new thermalmonitord; once it has settled, re-apply simulateHip if charging.
// It only reacts to a changed value, so turn it off first, then on. Changes made by others
// (Battman) while thermalmonitord keeps running are left alone.
static pid_t gThermalPID;

static void reapplyAfterRestart(void) {
	if (!isCharging()) return;
	setSimulateHIPEnabled(false);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (!isCharging()) return;
		int ret = setSimulateHIPEnabled(true);
		os_log(gLog, "simulate HIP re-enabled after thermalmonitord restart (status %d)", ret);
	});
}

static void prefsChanged(void) {
	pid_t pid = thermalmonitordPID();
	if (!pid || pid == gThermalPID) return;
	os_log(gLog, "thermalmonitord restarted (pid %d -> %d)", gThermalPID, pid);
	gThermalPID = pid;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		reapplyAfterRestart();
	});
}

static void watchThermalPrefs(void) {
	gThermalPID = thermalmonitordPID();
	int fd = open("/Library/Preferences/SystemConfiguration", O_EVTONLY);
	if (fd < 0) {
		os_log_error(gLog, "unable to watch SystemConfiguration prefs");
		return;
	}
	dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd,
		DISPATCH_VNODE_WRITE | DISPATCH_VNODE_LINK | DISPATCH_VNODE_RENAME, dispatch_get_main_queue());
	dispatch_source_set_event_handler(src, ^{ prefsChanged(); });
	dispatch_resume(src);
}
#endif

int main(void) {
	gLog = os_log_create("com.supremeinspirit.hipcharge", "daemon");
	CFRunLoopSourceRef src = IOPSNotificationCreateRunLoopSource(update, NULL);
	if (!src) {
		os_log_error(gLog, "IOPSNotificationCreateRunLoopSource failed");
		return 1;
	}
	CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
	update(NULL);
#ifndef HIPCHARGE_TWEAK
	watchThermalPrefs();
#endif
	CFRunLoopRun();
	return 0;
}
