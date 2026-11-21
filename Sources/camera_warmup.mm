#import "camera_warmup.h"
#import "settings_keys.h"
#include "early_glance.hpp"
#import <CoreGraphics/CoreGraphics.h>
#import <os/log.h>

static const NSTimeInterval warmupSeconds = 4.0;

BOOL MacFaceSessionIsLocked(void) {
    NSDictionary *state = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    id locked = state[@"CGSSessionScreenIsLocked"];
    return [locked isKindOfClass:[NSNumber class]] && [locked boolValue];
}

static BOOL canWarmCamera(void) {
    return [MacFaceUnlockMode() isEqualToString:MacFaceModeGlance] &&
        MacFaceSessionIsLocked() && !CGDisplayIsAsleep(CGMainDisplayID());
}

@implementation MacFaceCameraWarmup {
    dispatch_queue_t _queue;
    MacFaceCamera *_waiting;
    uint64_t _generation;
    BOOL _verifying;
    NSTimer *_timer;
    BOOL _eligible;
    BOOL (^_analyzer)(const cv::Mat &);
    EarlyGlance _earlyGlance;
    uint64_t _frameVersion;
}

- (instancetype)initWithAnalyzer:(BOOL (^)(const cv::Mat &))analyzer {
    if ((self = [super init])) {
        _analyzer = [analyzer copy];
        _queue = dispatch_queue_create("com.macface.camera.lifecycle", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)startWatching {
    __weak MacFaceCameraWarmup *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf checkDisplay];
    }];
}

- (void)stopWatching {
    [_timer invalidate];
    _timer = nil;
    dispatch_async(_queue, ^{ [self stopIdleCapture]; });
}

- (void)checkDisplay {
    BOOL eligible = canWarmCamera();
    if (eligible == _eligible) return;
    _eligible = eligible;
    dispatch_async(_queue, ^{
        if (eligible) {
            [self warmCamera];
        } else {
            [self stopIdleCapture];
        }
    });
}

- (void)warmCamera {
    if (_verifying || _waiting || !canWarmCamera()) return;
    MacFaceCamera *camera = [[MacFaceCamera alloc] init];
    uint64_t generation = ++_generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(warmupSeconds * NSEC_PER_SEC)), _queue, ^{
        if (self->_generation == generation) [self stopIdleCapture];
    });
    if ([camera start] && canWarmCamera()) {
        _waiting = camera;
        _earlyGlance = EarlyGlance();
        _frameVersion = 0;
        [camera beginFrameDelivery];
        [self analyzeIdleFrame:generation];
        os_log(OS_LOG_DEFAULT, "MacFace: camera prewarmed");
    } else {
        [camera stop];
    }
}

- (void)analyzeIdleFrame:(uint64_t)generation {
    if (!_waiting || _generation != generation || !canWarmCamera()) return;

    cv::Mat frame;
    BOOL received = [_waiting waitForFrame:frame version:_frameVersion before:[NSDate date]];
    const double now = NSProcessInfo.processInfo.systemUptime;
    if (received) {
        BOOL matched = _analyzer(frame);
        BOOL wasReady = _earlyGlance.fresh(now);
        _earlyGlance.record(matched, now);
        if (!wasReady && _earlyGlance.fresh(now)) {
            os_log(OS_LOG_DEFAULT, "MacFace: early verification ready");
        }
    } else {
        _earlyGlance.record(false, now);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 160 * NSEC_PER_MSEC), _queue, ^{
        [self analyzeIdleFrame:generation];
    });
}

- (void)stopIdleCapture {
    if (!_waiting) return;
    [_waiting stop];
    _waiting = nil;
    _earlyGlance = EarlyGlance();
    ++_generation;
}

- (MacFaceCamera *)beginVerificationReused:(BOOL *)reused prepared:(BOOL *)prepared {
    __block MacFaceCamera *camera = nil;
    __block BOOL warm = NO;
    __block BOOL preverified = NO;
    dispatch_sync(_queue, ^{
        self->_verifying = YES;
        if (!MacFaceSessionIsLocked()) {
            [self stopIdleCapture];
            return;
        }
        camera = self->_waiting;
        self->_waiting = nil;
        ++self->_generation;
        warm = camera != nil;
        preverified = warm && canWarmCamera() &&
            self->_earlyGlance.fresh(NSProcessInfo.processInfo.systemUptime);
        self->_earlyGlance = EarlyGlance();
        if (!camera) {
            camera = [[MacFaceCamera alloc] init];
            if (![camera start]) {
                [camera stop];
                camera = nil;
            }
        }
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
