#pragma once

#import <Foundation/Foundation.h>

static NSString *const MacFaceSettingsDomain = @"com.macface.settings";
static NSString *const MacFaceMenuBarIconKey = @"ShowsMenuBarIcon";
static NSString *const MacFaceMenuBarIconChanged = @"com.macface.settings.menu-bar-icon-changed";
static NSString *const MacFaceModeKey = @"ScreenUnlockMode";
static NSString *const MacFaceModeGlance = @"glance";
static NSString *const MacFaceModeAutomatic = @"automatic";
static NSString *const MacFaceModePassword = @"password";
static NSString *const MacFaceRequestEventAccess = @"com.macface.settings.request-event-access";

static inline NSString *MacFaceUnlockMode(void) {
    NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:MacFaceSettingsDomain];
    NSString *mode = [settings stringForKey:MacFaceModeKey];
    if (!mode) return MacFaceModeGlance;
    if ([mode isEqualToString:MacFaceModeGlance] || [mode isEqualToString:MacFaceModeAutomatic]) {
        return mode;
    }
    return MacFaceModePassword;
}
