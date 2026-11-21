#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, MacFaceFeedbackState) {
    MacFaceFeedbackHidden,
    MacFaceFeedbackScanning,
    MacFaceFeedbackReady,
    MacFaceFeedbackAccepted,
    MacFaceFeedbackFailed,
    MacFaceFeedbackRetry,
};

@interface MacFaceLockFeedback : NSObject
- (void)showState:(MacFaceFeedbackState)state;
- (void)updateForLockedDisplay:(BOOL)lockedDisplay unlocked:(BOOL)unlocked;
@end
