#import "lock_feedback.h"
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>

namespace {
// Glance's NotchSkyLight (MIT) documents the window-server space used on the lock screen.
struct LockScreenSpace {
    using Connection = int32_t (*)();
    using Create = int32_t (*)(int32_t, int32_t, int32_t);
    using SetLevel = int32_t (*)(int32_t, int32_t, int32_t);
    using Show = void (*)(int32_t, CFArrayRef);
    using Add = void (*)(int32_t, int32_t, CFArrayRef, int32_t);
    using Remove = void (*)(int32_t, CFArrayRef, CFArrayRef);

    int32_t connection = 0;
    int32_t space = 0;
    Add add = nullptr;
    Remove remove = nullptr;

    LockScreenSpace() {
        void *framework = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
                                 RTLD_LAZY | RTLD_LOCAL);
        if (!framework) return;
        auto connect = reinterpret_cast<Connection>(dlsym(framework, "SLSMainConnectionID"));
        auto create = reinterpret_cast<Create>(dlsym(framework, "SLSSpaceCreate"));
        auto setLevel = reinterpret_cast<SetLevel>(dlsym(framework, "SLSSpaceSetAbsoluteLevel"));
        auto show = reinterpret_cast<Show>(dlsym(framework, "SLSShowSpaces"));
        add = reinterpret_cast<Add>(dlsym(framework, "SLSSpaceAddWindowsAndRemoveFromSpaces"));
        remove = reinterpret_cast<Remove>(dlsym(framework, "SLSRemoveWindowsFromSpaces"));
        if (!connect || !create || !setLevel || !show || !add || !remove) return;
        connection = connect();
        if (connection <= 0) return;
        const int32_t candidate = create(connection, 1, 0);
        constexpr int32_t notificationCenterLockLevel = 400;
        if (candidate <= 0 || setLevel(connection, candidate, notificationCenterLockLevel) != 0) return;
        space = candidate;
        show(connection, (__bridge CFArrayRef)@[@(space)]);
    }

    bool attach(NSInteger windowNumber) const {
        if (space <= 0 || windowNumber <= 0) return false;
        add(connection, space, (__bridge CFArrayRef)@[@(windowNumber)], 7);
        return true;
    }

    void detach(NSInteger windowNumber) const {
        remove(connection, (__bridge CFArrayRef)@[@(windowNumber)], (__bridge CFArrayRef)@[@(space)]);
    }
};

LockScreenSpace &lockScreenSpace() {
    static LockScreenSpace space;
    return space;
}

}

@interface MacFaceFeedbackPanel : NSPanel
@end

@implementation MacFaceFeedbackPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@implementation MacFaceLockFeedback {
    MacFaceFeedbackPanel *_panel;
    NSImageView *_icon;
    MacFaceFeedbackState _state;
    BOOL _attached;
    BOOL _lockedDisplay;
    NSUInteger _revision;
}

- (void)createPanelOnScreen:(NSScreen *)screen {
    const NSSize size = NSMakeSize(76, 44);
    const NSRect bounds = NSMakeRect(0, 0, size.width, size.height);
    _panel = [[MacFaceFeedbackPanel alloc] initWithContentRect:bounds
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = NO;
    _panel.ignoresMouseEvents = YES;
    _panel.hidesOnDeactivate = NO;
    _panel.level = NSStatusWindowLevel;
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
        NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
    NSView *surface = [[NSView alloc] initWithFrame:bounds];
    surface.wantsLayer = YES;
    surface.layer.backgroundColor = [NSColor colorWithWhite:0.08 alpha:0.94].CGColor;
    surface.layer.cornerRadius = 17;
    surface.layer.borderWidth = 1;
    surface.layer.borderColor = [NSColor colorWithWhite:1 alpha:0.16].CGColor;
    _panel.contentView = surface;
    _icon = [[NSImageView alloc] initWithFrame:NSInsetRect(bounds, 24, 9)];
    _icon.wantsLayer = YES;
    _icon.imageScaling = NSImageScaleProportionallyDown;
    [surface addSubview:_icon];
    [_panel setFrameOrigin:NSMakePoint(NSMidX(screen.frame) - size.width / 2,
                                         NSMaxY(screen.frame) - size.height - 33)];
}

- (void)hide {
    ++_revision;
    _state = MacFaceFeedbackHidden;
    [_icon.layer removeAllAnimations];
    if (_attached) lockScreenSpace().detach(_panel.windowNumber);
    _attached = NO;
    [_panel orderOut:nil];
}

- (void)setSymbol:(NSString *)name description:(NSString *)description tint:(NSColor *)tint {
    [_icon.layer removeAllAnimations];
    if (_icon.image && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        CATransition *transition = [CATransition animation];
        transition.type = kCATransitionFade;
        transition.duration = 0.16;
        [_icon.layer addAnimation:transition forKey:@"symbol"];
    }
    _icon.image = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:description]
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:20 weight:NSFontWeightMedium]];
    _icon.contentTintColor = tint;
}

- (void)hideAfter:(NSTimeInterval)delay {
    const NSUInteger revision = ++_revision;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_revision == revision) [self hide];
    });
}

- (void)showState:(MacFaceFeedbackState)state {
    if (state == MacFaceFeedbackHidden) {
        [self hide];
        return;
    }
    if (!_lockedDisplay || state == _state) return;
    if (!_attached) {
        NSScreen *screen = NSScreen.screens.firstObject;
        if (!screen || lockScreenSpace().space == 0) return;
        [self createPanelOnScreen:screen];
        _panel.alphaValue = 0;
        [_panel orderFrontRegardless];
        _attached = lockScreenSpace().attach(_panel.windowNumber);
        if (!_attached) {
            [_panel orderOut:nil];
            return;
        }
        _panel.alphaValue = 1;
        if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
            CAKeyframeAnimation *entry = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            entry.values = @[@0.76, @1.03, @1.0];
            entry.duration = 0.23;
            [_panel.contentView.layer addAnimation:entry forKey:@"appearance"];
        }
    }
    ++_revision;
    _state = state;
    switch (state) {
        case MacFaceFeedbackScanning: {
            [self setSymbol:@"faceid" description:@"正在识别人脸" tint:NSColor.whiteColor];
            if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
                CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"opacity"];
                pulse.fromValue = @1.0;
                pulse.toValue = @0.52;
                pulse.duration = 0.62;
                pulse.autoreverses = YES;
                pulse.repeatCount = HUGE_VALF;
                [_icon.layer addAnimation:pulse forKey:@"scanning"];
            }
            break;
        }
        case MacFaceFeedbackReady:
            [self setSymbol:@"return" description:@"按回车解锁" tint:NSColor.whiteColor];
            break;
        case MacFaceFeedbackAccepted:
            [self setSymbol:@"faceid" description:@"正在解锁" tint:NSColor.whiteColor];
            [self hideAfter:1.5];
            break;
        case MacFaceFeedbackFailed:
            [self setSymbol:@"exclamationmark.circle" description:@"人脸未通过验证" tint:NSColor.systemOrangeColor];
            [self hideAfter:1.3];
            break;
        case MacFaceFeedbackRetry:
            [self setSymbol:@"arrow.clockwise" description:@"按回车重试，或输入系统密码" tint:NSColor.whiteColor];
            [self hideAfter:2.0];
            break;
        case MacFaceFeedbackHidden:
            break;
    }
}

- (void)updateForLockedDisplay:(BOOL)lockedDisplay unlocked:(BOOL)unlocked {
    _lockedDisplay = lockedDisplay;
    if (lockedDisplay || !_attached) return;
    if (unlocked && _state == MacFaceFeedbackAccepted) {
        lockScreenSpace().detach(_panel.windowNumber);
        _attached = NO;
        [self setSymbol:@"lock.open" description:@"已解锁" tint:NSColor.systemGreenColor];
        [_panel orderFrontRegardless];
        if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
            CAKeyframeAnimation *confirmation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
            confirmation.values = @[@0.88, @1.13, @1.0];
            confirmation.duration = 0.3;
            [_icon.layer addAnimation:confirmation forKey:@"confirmation"];
        }
        [self hideAfter:0.6];
    } else {
        [self hide];
    }
}

@end
