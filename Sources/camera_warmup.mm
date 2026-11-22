#import "camera_warmup.h"
#import "settings_keys.h"
#include "early_glance.hpp"
#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#import <os/log.h>
#include <unistd.h>

BOOL MacFaceSessionIsLocked(void) {
    NSDictionary *state = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    id locked = state[@"CGSSessionScreenIsLocked"];
    return [locked isKindOfClass:[NSNumber class]] && [locked boolValue];
}

static BOOL canWarmCamera(void) {
    return ![MacFaceUnlockMode() isEqualToString:MacFaceModePassword] &&
        MacFaceSessionIsLocked() && !CGDisplayIsAsleep(CGMainDisplayID());
}

static BOOL submitFaceUnlock(double armedAt) {
    if (![MacFaceUnlockMode() isEqualToString:MacFaceModeAutomatic] ||
        CGDisplayIsAsleep(CGMainDisplayID())) {
        return NO;
    }
    if (!CGPreflightPostEventAccess()) {
        os_log(OS_LOG_DEFAULT, "MacFace: automatic unlock needs Accessibility permission");
        return NO;
    }
    NSDictionary *session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    if (![session[@"CGSSessionScreenIsLocked"] boolValue] ||
        ![session[(__bridge NSString *)kCGSessionOnConsoleKey] boolValue] ||
        [session[(__bridge NSString *)kCGSessionUserIDKey] unsignedIntValue] != getuid()) {
        return NO;
    }
    const double timeSinceKeyDown = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState, kCGEventKeyDown);
    if (timeSinceKeyDown < NSProcessInfo.processInfo.systemUptime - armedAt) return NO;

    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!source) return NO;
    CGEventRef down = CGEventCreateKeyboardEvent(source, kVK_Return, true);
    CGEventRef up = CGEventCreateKeyboardEvent(source, kVK_Return, false);
    const BOOL posted = down && up && MacFaceSessionIsLocked();
    if (posted) {
        CGEventSetFlags(down, 0);
        CGEventSetFlags(up, 0);
        CGEventPost(kCGHIDEventTap, down);
        [NSThread sleepForTimeInterval:0.012];
        CGEventPost(kCGHIDEventTap, up);
    }
    if (down) CFRelease(down);
    if (up) CFRelease(up);
    CFRelease(source);
    return posted;
}

@implementation MacFaceCameraWarmup {
    dispatch_queue_t _queue;
    MacFaceCamera *_waiting;
    uint64_t _generation;
    BOOL _verifying;
    NSTimer *_timer;
    NSArray<id> *_screenObservers;
    BOOL _eligible;
    BOOL _lastLocked;
    BOOL _lastAutomatic;
    BOOL (^_analyzer)(const cv::Mat &);
    EarlyGlance _earlyGlance;
    uint64_t _frameVersion;
    double _warmupStarted;
    BOOL _reportedFirstFrame;
    MacFaceLockFeedback *_feedback;
    BOOL _showingReturnPrompt;
    BOOL _autoSubmitPending;
    double _autoKeyboardBaseline;
    double _automaticSubmittedAt;
}

- (instancetype)initWithAnalyzer:(BOOL (^)(const cv::Mat &))analyzer {
    if ((self = [super init])) {
        _analyzer = [analyzer copy];
        _queue = dispatch_queue_create("com.macface.camera.lifecycle", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)startWatching {
    _feedback = [[MacFaceLockFeedback alloc] init];
    __weak MacFaceCameraWarmup *weakSelf = self;
    NSDistributedNotificationCenter *notifications = NSDistributedNotificationCenter.defaultCenter;
    NSMutableArray<id> *observers = [NSMutableArray array];
    for (NSString *name in @[@"com.apple.screenIsLocked", @"com.apple.screenIsUnlocked"]) {
        [observers addObject:[notifications addObserverForName:name object:nil
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                (void)notification;
                [weakSelf checkDisplay];
            }]];
    }
    _screenObservers = [observers copy];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf checkDisplay];
    }];
}

- (void)stopWatching {
    for (id observer in _screenObservers) {
        [NSDistributedNotificationCenter.defaultCenter removeObserver:observer];
    }
    _screenObservers = nil;
    [_timer invalidate];
    _timer = nil;
    [_feedback showState:MacFaceFeedbackHidden];
    dispatch_async(_queue, ^{ [self stopIdleCapture]; });
}

- (void)checkDisplay {
    BOOL locked = MacFaceSessionIsLocked();
    BOOL awake = !CGDisplayIsAsleep(CGMainDisplayID());
    NSString *mode = MacFaceUnlockMode();
    BOOL automatic = [mode isEqualToString:MacFaceModeAutomatic];
    BOOL eligible = locked && awake && ![mode isEqualToString:MacFaceModePassword];
    [_feedback updateForLockedDisplay:eligible unlocked:!locked];
    if (eligible == _eligible && locked == _lastLocked && automatic == _lastAutomatic) return;
    _eligible = eligible;
    _lastLocked = locked;
    _lastAutomatic = automatic;
    const double now = NSProcessInfo.processInfo.systemUptime;
    dispatch_async(_queue, ^{
        self->_autoSubmitPending = eligible && automatic && CGPreflightPostEventAccess();
        self->_automaticSubmittedAt = 0;
        if (eligible) {
            self->_autoKeyboardBaseline = now;
            if (automatic && !self->_autoSubmitPending) {
                os_log(OS_LOG_DEFAULT, "MacFace: automatic unlock needs Accessibility permission");
            }
            [self warmCamera];
        } else {
            [self stopIdleCapture];
        }
    });
}

- (void)updateFeedback:(MacFaceFeedbackState)state {
    dispatch_async(dispatch_get_main_queue(), ^{ [self->_feedback showState:state]; });
}

- (void)warmCamera {
    if (_verifying || _waiting || !canWarmCamera()) return;
    MacFaceCamera *camera = [[MacFaceCamera alloc] init];
    uint64_t generation = ++_generation;
    _warmupStarted = NSProcessInfo.processInfo.systemUptime;
    _reportedFirstFrame = NO;
    [self updateFeedback:MacFaceFeedbackScanning];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(EarlyGlance::maxWarmupSeconds * NSEC_PER_SEC)),
                   _queue, ^{
        if (self->_generation == generation && self->_automaticSubmittedAt == 0) {
            [self finishIdleScan];
        }
    });
    [camera beginFrameDelivery];
    if ([camera start] && canWarmCamera()) {
        _waiting = camera;
        _earlyGlance = EarlyGlance();
        _frameVersion = 0;
        [self analyzeIdleFrame:generation];
        os_log(OS_LOG_DEFAULT, "MacFace: camera prewarmed");
    } else {
        [camera stop];
        [self updateFeedback:MacFaceFeedbackHidden];
    }
}

- (void)analyzeIdleFrame:(uint64_t)generation {
    if (!_waiting || _generation != generation) return;
    if (!canWarmCamera()) {
        [self stopIdleCapture];
        return;
    }

    cv::Mat frame;
    BOOL received = [_waiting waitForFrame:frame version:_frameVersion before:[NSDate date]];
    const double now = NSProcessInfo.processInfo.systemUptime;
    if (received) {
        if (!_reportedFirstFrame) {
            _reportedFirstFrame = YES;
            os_log(OS_LOG_DEFAULT, "MacFace: first usable frame in %ld ms", (long)((now - _warmupStarted) * 1000));
        }
        BOOL matched = _analyzer(frame);
        BOOL wasReady = _earlyGlance.fresh(now);
        _earlyGlance.record(matched, now);
        if (!wasReady && _earlyGlance.fresh(now)) {
            const long elapsed = (long)((NSProcessInfo.processInfo.systemUptime - _warmupStarted) * 1000);
            os_log(OS_LOG_DEFAULT, "MacFace: early verification ready, elapsed=%ld ms", elapsed);
        }
    } else {
        _earlyGlance.record(false, now);
    }
    const BOOL ready = _earlyGlance.fresh(now);
    if (_autoSubmitPending &&
        CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState, kCGEventKeyDown) < now - _autoKeyboardBaseline) {
        _autoSubmitPending = NO;
    }
    if (ready && _autoSubmitPending) {
        _autoSubmitPending = NO;
        if (submitFaceUnlock(_autoKeyboardBaseline)) {
            _automaticSubmittedAt = NSProcessInfo.processInfo.systemUptime;
            os_log(OS_LOG_DEFAULT, "MacFace: submitted automatic face unlock");
        }
    }
    const double currentTime = NSProcessInfo.processInfo.systemUptime;
    const BOOL awaitingSystem = _automaticSubmittedAt > 0 && currentTime - _automaticSubmittedAt < 2.0;
    if (!awaitingSystem && !_earlyGlance.canKeepWarming(currentTime, _warmupStarted)) {
        [self finishIdleScan];
        return;
    }
    const BOOL showReturnPrompt = ready && !awaitingSystem;
    if (showReturnPrompt != _showingReturnPrompt) {
        _showingReturnPrompt = showReturnPrompt;
        [self updateFeedback:showReturnPrompt ? MacFaceFeedbackReady : MacFaceFeedbackScanning];
    }
    const int64_t delay = _autoSubmitPending ? 70 : 160;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_MSEC), _queue, ^{
        [self analyzeIdleFrame:generation];
    });
}

- (void)finishIdleScan {
    if (!_waiting) return;
    [self stopIdleCapture];
    if (canWarmCamera()) [self updateFeedback:MacFaceFeedbackRetry];
}

- (void)stopIdleCapture {
    if (!_waiting) return;
    [_waiting stop];
    _waiting = nil;
    _earlyGlance = EarlyGlance();
    _showingReturnPrompt = NO;
    [self updateFeedback:MacFaceFeedbackHidden];
    ++_generation;
}

- (MacFaceCamera *)beginVerificationReused:(BOOL *)reused prepared:(BOOL *)prepared {
    __block MacFaceCamera *camera = nil;
    __block BOOL warm = NO;
    __block BOOL preverified = NO;
    dispatch_sync(_queue, ^{
        self->_verifying = YES;
        self->_autoSubmitPending = NO;
        if (!MacFaceSessionIsLocked()) {
            [self stopIdleCapture];
            return;
        }
        const double now = NSProcessInfo.processInfo.systemUptime;
        if (self->_waiting && !self->_earlyGlance.canKeepWarming(now, self->_warmupStarted)) {
            [self stopIdleCapture];
        }
        camera = self->_waiting;
        self->_waiting = nil;
        self->_showingReturnPrompt = NO;
        ++self->_generation;
        warm = camera != nil;
        preverified = warm && canWarmCamera() &&
            self->_earlyGlance.fresh(now);
        self->_earlyGlance = EarlyGlance();
        if (!camera) {
            camera = [[MacFaceCamera alloc] init];
            if (![camera start]) {
                [camera stop];
                camera = nil;
            }
        }
        if (camera) [self updateFeedback:MacFaceFeedbackScanning];
        [camera beginFrameDelivery];
    });
    if (reused) *reused = warm;
    if (prepared) *prepared = preverified;
    return camera;
}

- (void)endVerification:(MacFaceCamera *)camera {
    dispatch_sync(_queue, ^{
        [camera stop];
        self->_verifying = NO;
    });
}

@end
