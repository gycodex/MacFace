#import <Foundation/Foundation.h>

#include <opencv2/core.hpp>

@interface MacFaceCamera : NSObject
- (BOOL)start;
- (void)stop;
- (BOOL)waitForFrame:(cv::Mat &)frame
             version:(uint64_t &)version
              before:(NSDate *)deadline;
@end
