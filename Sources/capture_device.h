#pragma once

#import <AVFoundation/AVFoundation.h>

static inline AVCaptureDevice *MacFaceCaptureDevice(void) {
    AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeExternal, AVCaptureDeviceTypeBuiltInWideAngleCamera]
                              mediaType:AVMediaTypeVideo
                               position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *camera in discovery.devices) {
        if (!camera.isContinuityCamera) return camera;
    }
    return nil;
}
