// Control Center modules for CCSupport. Built twice: once as the HIPCharge on/off toggle,
// once (-DHIPCHARGE_SIMULATE_MODULE) as the Simulate HIP toggle. Both only mirror the state
// the daemon publishes and ask it to change through the notify commands in ipc.h.
//
// The module class is created at runtime and there are no @"" literals on purpose: the
// on-device clang doesn't sign the isa of compiled classes and constant strings, and on
// arm64e (iOS 17) SpringBoard dies in objc_msgSend the first time one of those is messaged.
// Objects and classes made by the runtime are signed correctly. Don't add @implementation
// or @"" here without building with a toolchain that signs them.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <notify.h>
#include "../ipc.h"

#ifdef HIPCHARGE_SIMULATE_MODULE
#define MODULE_NAME "HIPChargeSimulateModule"
#define STATE_BIT HIPCHARGE_STATE_SIMULATE
#define CMD_ON HIPCHARGE_CMD_SIM_ON
#define CMD_OFF HIPCHARGE_CMD_SIM_OFF
#define SYMBOL "thermometer"
#define FALLBACK "HIP"
#else
#define MODULE_NAME "HIPChargeModule"
#define STATE_BIT HIPCHARGE_STATE_ENABLED
#define CMD_ON HIPCHARGE_CMD_ENABLE
#define CMD_OFF HIPCHARGE_CMD_DISABLE
#define SYMBOL "bolt.fill"
#define FALLBACK "HIP+"
#endif

#define STR(s) [NSString stringWithUTF8String:(s)]

// Per-instance state, kept behind the "state" ivar
typedef struct {
	int token;
	BOOL registered;
	// What was last asked for, shown until the daemon confirms or the request times out
	BOOL pending;
	BOOL pendingValue;
} ModuleState;

static ptrdiff_t stateOffset;

static ModuleState **stateSlot(__unsafe_unretained id self) {
	return (ModuleState **)((char *)(__bridge void *)self + stateOffset);
}

static void refresh(id self) {
	((void (*)(id, SEL))objc_msgSend)(self, sel_registerName("refreshState"));
}

static id moduleInit(id self, SEL _cmd) {
	struct objc_super sup = { self, class_getSuperclass(objc_getClass(MODULE_NAME)) };
	self = ((id (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
	if (!self) return nil;
	ModuleState *state = calloc(1, sizeof(ModuleState));
	*stateSlot(self) = state;
	__weak id weakSelf = self;
	state->registered = notify_register_dispatch(HIPCHARGE_STATE, &state->token, dispatch_get_main_queue(), ^(int token) {
		id strongSelf = weakSelf;
		if (!strongSelf) return;
		(*stateSlot(strongSelf))->pending = NO;
		refresh(strongSelf);
	}) == NOTIFY_STATUS_OK;
	return self;
}

static void moduleDealloc(__unsafe_unretained id self, SEL _cmd) {
	ModuleState *state = *stateSlot(self);
	if (state) {
		if (state->registered) notify_cancel(state->token);
		free(state);
	}
	struct objc_super sup = { self, class_getSuperclass(objc_getClass(MODULE_NAME)) };
	((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
}

static BOOL moduleIsSelected(id self, SEL _cmd) {
	ModuleState *state = *stateSlot(self);
	if (!state) return NO;
	if (state->pending) return state->pendingValue;
	uint64_t value = 0;
	if (!state->registered || notify_get_state(state->token, &value) != NOTIFY_STATUS_OK) return NO;
	return (value & STATE_BIT) != 0;
}

static void moduleSetSelected(id self, SEL _cmd, BOOL selected) {
	ModuleState *state = *stateSlot(self);
	if (!state) return;
	state->pending = YES;
	state->pendingValue = selected;
	notify_post(selected ? CMD_ON : CMD_OFF);
	refresh(self);
	// Fall back to the real state if the daemon doesn't answer (not running)
	__weak id weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		id strongSelf = weakSelf;
		if (!strongSelf || !(*stateSlot(strongSelf))->pending) return;
		(*stateSlot(strongSelf))->pending = NO;
		refresh(strongSelf);
	});
}

static UIImage *moduleIconGlyph(id self, SEL _cmd) {
	CGSize size = CGSizeMake(48, 48);
	UIImage *symbol = nil;
	if (@available(iOS 13.0, *)) {
		symbol = [UIImage systemImageNamed:STR(SYMBOL)
			withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightMedium]];
	}
	UIGraphicsBeginImageContextWithOptions(size, NO, 0);
	if (symbol) {
		CGSize s = symbol.size;
		[[symbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
			drawInRect:CGRectMake((size.width - s.width) / 2, (size.height - s.height) / 2, s.width, s.height)];
	} else {
		NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
			[UIFont boldSystemFontOfSize:15], NSFontAttributeName, [UIColor blackColor], NSForegroundColorAttributeName, nil];
		NSString *text = STR(FALLBACK);
		CGSize s = [text sizeWithAttributes:attributes];
		[text drawAtPoint:CGPointMake((size.width - s.width) / 2, (size.height - s.height) / 2) withAttributes:attributes];
	}
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIColor *moduleSelectedColor(id self, SEL _cmd) {
#ifdef HIPCHARGE_SIMULATE_MODULE
	return [UIColor systemOrangeColor];
#else
	return [UIColor systemGreenColor];
#endif
}

__attribute__((constructor)) static void registerModule(void) {
	Class base = objc_getClass("CCUIToggleModule");
	if (!base || objc_getClass(MODULE_NAME)) return;
	Class cls = objc_allocateClassPair(base, MODULE_NAME, 0);
	if (!cls) return;
	class_addIvar(cls, "state", sizeof(void *), __builtin_ctz(sizeof(void *)), "^v");
	class_addMethod(cls, sel_registerName("init"), (IMP)moduleInit, "@16@0:8");
	class_addMethod(cls, sel_registerName("dealloc"), (IMP)moduleDealloc, "v16@0:8");
	class_addMethod(cls, sel_registerName("isSelected"), (IMP)moduleIsSelected, "B16@0:8");
	class_addMethod(cls, sel_registerName("setSelected:"), (IMP)moduleSetSelected, "v20@0:8B16");
	class_addMethod(cls, sel_registerName("iconGlyph"), (IMP)moduleIconGlyph, "@16@0:8");
	class_addMethod(cls, sel_registerName("selectedColor"), (IMP)moduleSelectedColor, "@16@0:8");
	objc_registerClassPair(cls);
	stateOffset = ivar_getOffset(class_getInstanceVariable(cls, "state"));
}
