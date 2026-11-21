#import "agent_camera.h"
#import <AVFoundation/AVFoundation.h>

#include <opencv2/imgproc.hpp>
#include <utility>

@interface MacFaceCamera () <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation MacFaceCamera {
    AVCaptureSession *_session;
    NSCondition *_delivery;
    cv::Mat _latest;
    uint64_t _version;
    BOOL _delivering;
    BOOL _discardNext;
}

- (instancetype)init {
    if ((self = [super init])) {
        _delivery = [[NSCondition alloc] init];
    }
    return self;
}

- (BOOL)start {
    AVCaptureDeviceDiscoverySession *discovery =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeExternal]
                                                               mediaType:AVMediaTypeVideo
                                                                position:AVCaptureDevicePositionUnspecified];
    AVCaptureDevice *camera = nil;
    for (AVCaptureDevice *candidate in discovery.devices) {
        if (!candidate.isContinuityCamera) {
            camera = candidate;
            break;
        }
    }
    if (!camera) {
        return NO;
    }
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:nil];
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    if (!input || ![session canAddInput:input]) {
        return NO;
    }
    [session addInput:input];
    if ([session canSetSessionPreset:AVCaptureSessionPresetMedium]) {
        session.sessionPreset = AVCaptureSessionPresetMedium;
    }
    output.videoSettings = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:
                                 @(kCVPixelFormatType_32BGRA)};
    output.alwaysDiscardsLateVideoFrames = YES;
    if (![session canAddOutput:output]) {
        return NO;
    }
    [session addOutput:output];
    [output setSampleBufferDelegate:self
                              queue:dispatch_queue_create("com.macface.agent.capture", DISPATCH_QUEUE_SERIAL)];
    [session startRunning];
    _session = session;
    return session.isRunning;
}

- (void)beginFrameDelivery {
    [_delivery lock];
    _latest.release();
    _discardNext = YES;
    _delivering = YES;
    [_delivery unlock];
}

- (void)stop {
    [_session stopRunning];
    _session = nil;
    [_delivery lock];
    _delivering = NO;
    _latest.release();
    [_delivery unlock];
}

- (BOOL)waitForFrame:(cv::Mat &)frame
             version:(uint64_t &)version
              before:(NSDate *)deadline {
    [_delivery lock];
    while (_latest.empty() || version == _version) {
        if (![_delivery waitUntilDate:deadline]) {
            [_delivery unlock];
            return NO;
        }
    }
    frame = _latest;
    version = _version;
    [_delivery unlock];
    return YES;
}

- (void)captureOutput:(AVCaptureOutput *)output
 didOutputSampleBuffer:(CMSampleBufferRef)sample
       fromConnection:(AVCaptureConnection *)connection {
    (void)output;
    (void)connection;
    [_delivery lock];
    if (!_delivering || _discardNext) {
        _discardNext = NO;
        [_delivery unlock];
        return;
    }
    CVPixelBufferRef pixels = CMSampleBufferGetImageBuffer(sample);
    if (!pixels || CVPixelBufferLockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
        [_delivery unlock];
        return;
    }
    cv::Mat bgra((int)CVPixelBufferGetHeight(pixels), (int)CVPixelBufferGetWidth(pixels),
                 CV_8UC4, CVPixelBufferGetBaseAddress(pixels), CVPixelBufferGetBytesPerRow(pixels));
    cv::Mat bgr;
    cv::cvtColor(bgra, bgr, cv::COLOR_BGRA2BGR);
    CVPixelBufferUnlockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);

    _latest = std::move(bgr);
    ++_version;
    [_delivery broadcast];
    [_delivery unlock];
}
@end
