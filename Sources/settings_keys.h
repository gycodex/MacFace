#pragma once

#import <Foundation/Foundation.h>

static NSString *const MacFaceSettingsDomain = @"com.macface.settings";
static NSString *const MacFaceModeKey = @"ScreenUnlockMode";
static NSString *const MacFaceModeGlance = @"glance";
static NSString *const MacFaceModePassword = @"password";

static inline NSString *MacFaceUnlockMode(void) {
    NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:MacFaceSettingsDomain];
    NSString *mode = [settings stringForKey:MacFaceModeKey];
    if (!mode) return MacFaceModeGlance;
    if ([mode isEqualToString:MacFaceModeGlance]) {
        return mode;
    }
    return MacFaceModePassword;
}
