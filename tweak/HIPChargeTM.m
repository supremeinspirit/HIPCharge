// HIPChargeTM: loaded into thermalmonitord. On iOS < 15 (no simulateHip key) it keeps HIP
// engaged the whole time the device is charging, like simulateHip does on iOS 15+, where the
// daemon sets simulateHip instead and this tweak does nothing.
// -[ContextInPocket updateContextActiveState] turns HIP off while the backlight is on, audio
// is playing, or the device is connected (unless topping off). Those three getters are only
// read there, so while charging they report NO and HIP stays on regardless of the screen.
// Only the getters are replaced: the real values are still stored, and the methods are looked
// up by name, so there are no build-specific addresses. Missing methods are left alone.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <os/log.h>

static BOOL (*origConnectedExternally)(id, SEL);
static BOOL (*origBacklightIsOn)(id, SEL);
static BOOL (*origAudioIsOn)(id, SEL);

static BOOL charging(id self) {
	return origConnectedExternally(self, sel_registerName("connectedExternally"));
}
static BOOL connectedExternally(id self, SEL _cmd) {
	return NO;
}
static BOOL backlightIsOn(id self, SEL _cmd) {
	return charging(self) ? NO : origBacklightIsOn(self, _cmd);
}
static BOOL audioIsOn(id self, SEL _cmd) {
	return charging(self) ? NO : origAudioIsOn(self, _cmd);
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
	os_log(OS_LOG_DEFAULT, "HIPChargeTM: HIP forced while charging (backlight %d, audio %d)",
		origBacklightIsOn != NULL, origAudioIsOn != NULL);
}
