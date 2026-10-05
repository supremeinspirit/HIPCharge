// HIPCharge: enable Battman's "Simulate HIP" while charging, disable it otherwise.
// Uses the same OSThermalStatus SCPreferences keys as Battman (scprefs/wrapper.c).
// HIPCHARGE_TWEAK builds (iOS < 15, no simulateHip key) leave that to the HIPChargeTM
// tweak in thermalmonitord and only show the banners.
// The Control Center modules switch HIPCharge itself and Simulate HIP through the notify
// commands in ipc.h; Simulate HIP works whether or not HIPCharge is enabled.

#include <CoreFoundation/CoreFoundation.h>
// SCPreferences is marked unavailable in the iOS SDK headers, so declare what we use
typedef const struct __SCPreferences *SCPreferencesRef;
extern SCPreferencesRef SCPreferencesCreate(CFAllocatorRef allocator, CFStringRef name, CFStringRef prefsID);
extern CFPropertyListRef SCPreferencesGetValue(SCPreferencesRef prefs, CFStringRef key);
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
#include "ipc.h"
#include <notify.h>
#include <stdbool.h>
#include <dispatch/dispatch.h>
#include <fcntl.h>
#include <string.h>
// libproc.h is not in the iOS SDK
extern int proc_listallpids(void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);

static os_log_t gLog;
static int lastState = -1;
static bool gEnabled = true;
static void publishState(void);
#define PREFS_ID CFSTR("com.supremeinspirit.hipcharge")

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

static bool simulateHIPEnabled(void) {
	SCPreferencesRef prefs = SCPreferencesCreate(kCFAllocatorDefault, CFSTR("OSThermalStatus"), CFSTR("OSThermalStatus.plist"));
	if (!prefs) return false;
	CFPropertyListRef value = SCPreferencesGetValue(prefs, CFSTR("simulateHip"));
	bool on = value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value);
	CFRelease(prefs);
	return on;
}
#else
// No simulateHip key before iOS 15: the tweak reads this from the published state. Like
// the real key it is not kept across a restart.
static bool gSimulate;
static int setSimulateHIPEnabled(bool enable) {
	gSimulate = enable;
	return kSCStatusOK;
}
static bool simulateHIPEnabled(void) {
	return gSimulate;
}
#endif

static void publishState(void) {
	static int token = -1;
	if (token == -1 && notify_register_check(HIPCHARGE_STATE, &token) != NOTIFY_STATUS_OK) {
		token = -1;
		return;
	}
	uint64_t state = HIPCHARGE_STATE_VALID;
	if (gEnabled) state |= HIPCHARGE_STATE_ENABLED;
	if (simulateHIPEnabled()) state |= HIPCHARGE_STATE_SIMULATE;
	uint64_t old = 0;
	if (notify_get_state(token, &old) == NOTIFY_STATUS_OK && old == state) return;
	notify_set_state(token, state);
	notify_post(HIPCHARGE_STATE);
}

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
	if (!gEnabled) return;
#ifdef HIPCHARGE_TWEAK
	os_log(gLog, "power %s", state ? "connected" : "disconnected");
	if (initial) return;
	showBanner(state ? "Charging: Simulate HIP ON" : "Unplugged: Simulate HIP OFF");
#else
	int ret = setSimulateHIPEnabled(state);
	os_log(gLog, "power %s -> simulate HIP %s (status %d)", state ? "connected" : "disconnected", state ? "on" : "off", ret);
	// No banner for the startup check (SpringBoard may not be up yet at boot)
	if (initial) return;
	showBanner(ret != kSCStatusOK ? "Failed to change Simulate HIP"
		: state ? "Charging: Simulate HIP ON" : "Unplugged: Simulate HIP OFF");
	publishState();
#endif
}

static void setEnabled(bool enable) {
	if (enable == gEnabled) return;
	gEnabled = enable;
	CFPreferencesSetAppValue(CFSTR("enabled"), enable ? kCFBooleanTrue : kCFBooleanFalse, PREFS_ID);
	CFPreferencesAppSynchronize(PREFS_ID);
	os_log(gLog, "HIPCharge %s", enable ? "enabled" : "disabled");
#ifndef HIPCHARGE_TWEAK
	// Take over (or hand back) right away if the device is charging
	if (isCharging()) setSimulateHIPEnabled(enable);
#endif
	publishState();
	showBanner(enable ? "HIPCharge on" : "HIPCharge off");
}

static void setSimulate(bool enable) {
	int ret = setSimulateHIPEnabled(enable);
	os_log(gLog, "simulate HIP %s by request (status %d)", enable ? "on" : "off", ret);
	publishState();
	showBanner(ret != kSCStatusOK ? "Failed to change Simulate HIP" : enable ? "Simulate HIP on" : "Simulate HIP off");
}

static void listen(const char *name, void (^handler)(void)) {
	int token;
	notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) { handler(); });
}

#ifndef HIPCHARGE_TWEAK
// thermalmonitord rewrites OSThermalStatus.plist with simulateHip off when it (re)starts, e.g.
// at boot or after a crash, which would leave HIP off until the next plug-in. Watch the prefs
// folder for a new thermalmonitord; once it has settled, re-apply simulateHip if charging.
// It only reacts to a changed value, so turn it off first, then on. Changes made by others
// (Battman) while thermalmonitord keeps running are left alone.
static pid_t gThermalPID;

static void reapplyAfterRestart(void) {
	if (!gEnabled || !isCharging()) return;
	setSimulateHIPEnabled(false);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (!gEnabled || !isCharging()) return;
		int ret = setSimulateHIPEnabled(true);
		os_log(gLog, "simulate HIP re-enabled after thermalmonitord restart (status %d)", ret);
		publishState();
	});
}

static void prefsChanged(void) {
	// Also picks up Simulate HIP being changed elsewhere (Battman)
	publishState();
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
	Boolean valid = false;
	Boolean enabled = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), PREFS_ID, &valid);
	if (valid) gEnabled = enabled;
	listen(HIPCHARGE_CMD_ENABLE, ^{ setEnabled(true); });
	listen(HIPCHARGE_CMD_DISABLE, ^{ setEnabled(false); });
	listen(HIPCHARGE_CMD_SIM_ON, ^{ setSimulate(true); });
	listen(HIPCHARGE_CMD_SIM_OFF, ^{ setSimulate(false); });
	update(NULL);
	publishState();
#ifndef HIPCHARGE_TWEAK
	watchThermalPrefs();
#endif
	CFRunLoopRun();
	return 0;
}
