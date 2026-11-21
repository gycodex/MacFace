#import <Foundation/Foundation.h>
#import "agent_camera.h"

BOOL MacFaceSessionIsLocked(void);

@interface MacFaceCameraWarmup : NSObject
- (instancetype)initWithAnalyzer:(BOOL (^)(const cv::Mat &))analyzer;
- (void)startWatching;
- (void)stopWatching;
- (MacFaceCamera *)beginVerificationReused:(BOOL *)reused prepared:(BOOL *)prepared;
- (void)endVerification:(MacFaceCamera *)camera;
@end
