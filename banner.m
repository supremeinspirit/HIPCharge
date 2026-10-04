// Posts a Notification Center banner from the daemon (no SpringBoard injection).
// Uses the private bundle-identifier initializer with iOS's own charging notification
// section; requires com.apple.private.usernotifications.bundle-identifiers in ent.plist.

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#include <os/log.h>
#include "banner.h"

#define kBannerID @"com.supremeinspirit.hipcharge"

@interface UNUserNotificationCenter (Private)
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

static UNUserNotificationCenter *gCenter;
static NSUInteger gGeneration;

void showBanner(const char *body) {
	@autoreleasepool {
		if (!gCenter) {
			if (![UNUserNotificationCenter instancesRespondToSelector:@selector(initWithBundleIdentifier:)]) return;
			// chargeawareness is iOS 14+; older versions have the Optimized Charging section
			NSString *bundleID = [[NSFileManager defaultManager] fileExistsAtPath:@"/System/Library/UserNotifications/Bundles/com.apple.powerui.chargeawareness.bundle"]
				? @"com.apple.powerui.chargeawareness" : @"com.apple.powerui.smartcharging";
			gCenter = [[UNUserNotificationCenter alloc] initWithBundleIdentifier:bundleID];
		}
		UNMutableNotificationContent *content = [UNMutableNotificationContent new];
		content.title = @"HIPCharge";
		content.body = @(body);
		// Same identifier every time, so a new banner replaces the previous one
		UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:kBannerID content:content trigger:nil];
		[gCenter addNotificationRequest:request withCompletionHandler:^(NSError *error) {
			if (error) os_log_error(OS_LOG_DEFAULT, "hipcharge: banner failed: %{public}@", error);
		}];
		// Clear it from Notification Center after the banner has gone
		NSUInteger generation = ++gGeneration;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if (generation == gGeneration) [gCenter removeDeliveredNotificationsWithIdentifiers:@[kBannerID]];
		});
	}
}
