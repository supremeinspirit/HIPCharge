// HIPChargeTM: loaded into thermalmonitord. On iOS < 15 (no simulateHip key) it keeps HIP
// engaged the whole time the device is charging, like simulateHip does on iOS 15+, where the
// daemon sets simulateHip instead and this tweak does nothing.
// -[ContextInPocket updateContextActiveState] turns HIP off while the backlight is on, audio
// is playing, or the device is connected (unless topping off). Those three getters are only
// read there, so while charging they report NO and HIP stays on regardless of the screen.
// Only the getters are replaced: the real values are still stored, and the methods are looked
// up by name, so there are no build-specific addresses. Missing methods are left alone.
// HIP is forced while the daemon's published Simulate HIP flag (ipc.h) is on. The daemon turns
// it on when power is connected and off when unplugged, and the Control Center toggle can
// change it at any time. Without a daemon HIP is forced while charging.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <os/log.h>
#include <notify.h>
#include "../ipc.h"

static BOOL (*origConnectedExternally)(id, SEL);
static BOOL (*origBacklightIsOn)(id, SEL);
static BOOL (*origAudioIsOn)(id, SEL);

static int stateToken = -1;
static __unsafe_unretained id context;

static BOOL forced(id self) {
	context = self;
	uint64_t state = 0;
	if (stateToken != -1 && notify_get_state(stateToken, &state) == NOTIFY_STATUS_OK && (state & HIPCHARGE_STATE_VALID))
		return (state & HIPCHARGE_STATE_SIMULATE) != 0;
	// No daemon: force HIP while charging
	return origConnectedExternally(self, sel_registerName("connectedExternally"));
}
static BOOL connectedExternally(id self, SEL _cmd) {
	return forced(self) ? NO : origConnectedExternally(self, _cmd);
}
static BOOL backlightIsOn(id self, SEL _cmd) {
	return forced(self) ? NO : origBacklightIsOn(self, _cmd);
}
static BOOL audioIsOn(id self, SEL _cmd) {
	return forced(self) ? NO : origAudioIsOn(self, _cmd);
}

static IMP hookGetter(Class cls, const char *name, IMP imp) {
	Method m = class_getInstanceMethod(cls, sel_registerName(name));
	if (!m || strcmp(method_getTypeEncoding(m), "B16@0:8") != 0) return NULL;
	return method_setImplementation(m, imp);
}

__attribute__((constructor)) static void init(void) {
	if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){15, 0, 0}]) return;
	Class cls = objc_getClass("ContextInPocket");
	if (!cls) {
		os_log_error(OS_LOG_DEFAULT, "HIPChargeTM: ContextInPocket not found, not hooking");
		return;
	}
	origConnectedExternally = (BOOL (*)(id, SEL))hookGetter(cls, "connectedExternally", (IMP)connectedExternally);
	if (!origConnectedExternally) {
		os_log_error(OS_LOG_DEFAULT, "HIPChargeTM: connectedExternally not found, not hooking");
		return;
	}
	origBacklightIsOn = (BOOL (*)(id, SEL))hookGetter(cls, "backlightIsOn", (IMP)backlightIsOn);
	origAudioIsOn = (BOOL (*)(id, SEL))hookGetter(cls, "audioIsOn", (IMP)audioIsOn);
	// Re-evaluate when a Control Center toggle changes the state, not only on the next
	// backlight or power event
	notify_register_dispatch(HIPCHARGE_STATE, &stateToken, dispatch_get_main_queue(), ^(int token) {
		SEL update = sel_registerName("updateContextActiveState");
		id ctx = context;
		if (ctx && [ctx respondsToSelector:update]) ((void (*)(id, SEL))objc_msgSend)(ctx, update);
	});
	os_log(OS_LOG_DEFAULT, "HIPChargeTM: HIP forced while charging (backlight %d, audio %d)",
		origBacklightIsOn != NULL, origAudioIsOn != NULL);
}
