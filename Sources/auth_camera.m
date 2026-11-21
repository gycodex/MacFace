#import <AVFoundation/AVFoundation.h>
#import <os/log.h>

@interface MacFaceFrameProbe : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property(nonatomic, strong) dispatch_semaphore_t frame;
@end

@implementation MacFaceFrameProbe

- (void)captureOutput:(AVCaptureOutput *)output
 didOutputSampleBuffer:(CMSampleBufferRef)sample
       fromConnection:(AVCaptureConnection *)connection {
    (void)output;
    (void)sample;
    (void)connection;
    dispatch_semaphore_signal(self.frame);
}

@end

void MacFaceCheckCamera(void) {
    AVAuthorizationStatus permission = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    os_log(OS_LOG_DEFAULT, "MacFaceProbe: authorization host camera permission=%ld", (long)permission);
    if (permission != AVAuthorizationStatusAuthorized) {
        return;
    }

    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            AVCaptureDeviceDiscoverySession *discovery =
                [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeExternal]
                                                                      mediaType:AVMediaTypeVideo
                                                                       position:AVCaptureDevicePositionUnspecified];
            AVCaptureDevice *camera = discovery.devices.firstObject;
            AVCaptureDeviceInput *input = camera ? [AVCaptureDeviceInput deviceInputWithDevice:camera error:nil] : nil;
            AVCaptureSession *session = [[AVCaptureSession alloc] init];
            AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
            if (!input || ![session canAddInput:input] || ![session canAddOutput:output]) {
                os_log(OS_LOG_DEFAULT, "MacFaceProbe: authorization host camera unavailable");
                dispatch_semaphore_signal(finished);
                return;
            }
            MacFaceFrameProbe *probe = [[MacFaceFrameProbe alloc] init];
            probe.frame = dispatch_semaphore_create(0);
            dispatch_queue_t delivery = dispatch_queue_create("com.macface.camera.frames", DISPATCH_QUEUE_SERIAL);
            [output setSampleBufferDelegate:probe queue:delivery];
            [session addInput:input];
            [session addOutput:output];
            [session startRunning];
            long frame = dispatch_semaphore_wait(probe.frame, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
            os_log(OS_LOG_DEFAULT, "MacFaceProbe: authorization host received camera frame=%d", frame == 0);
            dispatch_semaphore_signal(finished);
            [session stopRunning];
            [output setSampleBufferDelegate:nil queue:NULL];
        }
    });
    if (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) != 0) {
        os_log(OS_LOG_DEFAULT, "MacFaceProbe: authorization host camera timed out");
    }
}
