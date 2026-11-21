#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <os/log.h>

#import "agent_camera.h"
#import "camera_warmup.h"
#import "settings_keys.h"
#import "status_menu.h"
#include "auth_exchange.h"
#include "native_matching.hpp"

#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <libproc.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

using Clock = std::chrono::steady_clock;

static NSString *const configuration = @"/Library/Application Support/MacFace";
static const char *const authorizationHost = "identifier \"com.apple.authorizationhosthelper.arm64\" and anchor apple";

static bool checkGlance(MacFaceCamera *camera, NativeFaceMatcher &matcher, const cv::Mat &reference,
                        bool prepared, bool &usedPreparation) {
    auto started = Clock::now();
    auto deadline = started + std::chrono::seconds(3);
    auto nextCheck = started;
    uint64_t frameVersion = 0;
    int consecutive = 0;
    while (Clock::now() < deadline) {
        cv::Mat frame;
        if (![camera waitForFrame:frame version:frameVersion before:[NSDate dateWithTimeIntervalSinceNow:0.25]] ||
            Clock::now() < nextCheck) {
            continue;
        }
        nextCheck = Clock::now() + std::chrono::milliseconds(160);
        bool matched = matcher.verifiedGlance(frame, reference);
        if (prepared && matched && Clock::now() - started <= std::chrono::milliseconds(450)) {
            usedPreparation = true;
            return true;
        }
        prepared = false;
        consecutive = matched ? consecutive + 1 : 0;
        if (consecutive >= 3) {
            return true;
        }
    }
    return false;
}

static cv::Mat loadTemplate(void) {
    NSString *filename = [configuration stringByAppendingFormat:@"/enrollment-%u.bin", getuid()];
    std::ifstream reader(filename.fileSystemRepresentation, std::ios::binary);
    if (!reader) {
        return {};
    }
    cv::Mat embedding(1, 128, CV_32F);
    const size_t length = embedding.total() * embedding.elemSize();
    if (!reader.read(reinterpret_cast<char *>(embedding.data), length) || reader.peek() != EOF ||
        !cv::checkRange(embedding) || cv::norm(embedding) <= 1e-6) {
        return {};
    }
    return embedding;
}

static int createListener(void) {
    struct sockaddr_un endpoint = {.sun_family = AF_UNIX};
    int length = snprintf(endpoint.sun_path, sizeof(endpoint.sun_path), "/tmp/com.macface.agent.%u.sock", getuid());
    if (length < 0 || (size_t)length >= sizeof(endpoint.sun_path)) {
        return -1;
    }

    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener < 0) {
        return -1;
    }
    umask(0077);
    if (bind(listener, reinterpret_cast<struct sockaddr *>(&endpoint), sizeof(endpoint)) != 0) {
        close(listener);
        return -1;
    }
    if (listen(listener, 1) != 0) {
        unlink(endpoint.sun_path);
        close(listener);
        return -1;
    }
    return listener;
}

static long elapsedMilliseconds(Clock::time_point start) {
    return (long)std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - start).count();
}

static void updateStatus(MacFaceStatusMenu *menu, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{ [menu setStatusMessage:message]; });
}

static void serve(MacFaceStatusMenu *menu) {
    @autoreleasepool {
        auto matcher = std::make_shared<NativeFaceMatcher>([NSBundle mainBundle].resourcePath.fileSystemRepresentation);
        auto warming = Clock::now();
        try {
            matcher->warmUp();
            os_log(OS_LOG_DEFAULT, "MacFace: models ready in %ld ms", elapsedMilliseconds(warming));
        } catch (const cv::Exception &) {
            os_log_error(OS_LOG_DEFAULT, "MacFace: model warm-up unavailable");
        }
        int listener = createListener();
        if (listener < 0) {
            updateStatus(menu, @"识别后台未就绪");
            os_log_error(OS_LOG_DEFAULT, "MacFace: could not start verification listener");
            return;
        }

        MacFaceCameraWarmup *cameraWarmup = [[MacFaceCameraWarmup alloc] initWithAnalyzer:^BOOL(const cv::Mat &frame) {
            const cv::Mat reference = loadTemplate();
            if (reference.empty()) return NO;
            try {
                return matcher->verifiedGlance(frame, reference);
            } catch (const cv::Exception &) {
                return NO;
            }
        }];
        dispatch_async(dispatch_get_main_queue(), ^{ [cameraWarmup startWatching]; });
        updateStatus(menu, @"识别后台就绪");
        os_log(OS_LOG_DEFAULT, "MacFace: armed");
        for (;;) {
            @autoreleasepool {
                int client = accept(listener, NULL, NULL);
                if (client < 0) {
                    if (errno == EINTR) continue;
                    break;
                }
                uint8_t nonce[MacFaceNonceSize];
                if (MacFacePeerMatches(client, 0, authorizationHost) &&
                    MacFaceReceiveChallenge(client, nonce, 500)) {
                    NSString *mode = MacFaceUnlockMode();
                    if (!MacFaceSessionIsLocked() || [mode isEqualToString:MacFaceModePassword]) {
                        MacFaceSendVerdict(client, nonce, false, 500);
                        close(client);
                        continue;
                    }
                    const cv::Mat reference = loadTemplate();
                    if (reference.empty()) {
                        MacFaceSendVerdict(client, nonce, false, 500);
                        close(client);
                        continue;
                    }
                    bool verified = false;
                    auto requestStarted = Clock::now();
                    long cameraMs = 0;
                    BOOL reused = NO;
                    BOOL prepared = NO;
                    bool usedPreparation = false;
                    MacFaceCamera *camera = [cameraWarmup beginVerificationReused:&reused prepared:&prepared];
                    try {
                        if (camera) {
                            cameraMs = elapsedMilliseconds(requestStarted);
                            verified = checkGlance(camera, *matcher, reference, prepared, usedPreparation);
                        } else {
                            os_log_error(OS_LOG_DEFAULT, "MacFace: no available camera");
                        }
                    } catch (const cv::Exception &) {
                        os_log_error(OS_LOG_DEFAULT, "MacFace: recognition failed");
                    }
                    verified = verified && MacFaceSessionIsLocked();
                    if (verified) [cameraWarmup updateFeedback:MacFaceFeedbackAccepted];
                    const bool delivered = MacFaceSendVerdict(client, nonce, verified, 500);
                    if (!verified || !delivered) [cameraWarmup updateFeedback:MacFaceFeedbackFailed];
                    os_log(OS_LOG_DEFAULT, "MacFace: glance check %{public}s, camera=%ld ms total=%ld ms prewarmed=%d early=%d",
                           verified ? "passed" : "denied",
                           cameraMs, elapsedMilliseconds(requestStarted), reused, usedPreparation);
                    [cameraWarmup endVerification:camera];
                }
                close(client);
            }
        }
        close(listener);
        dispatch_async(dispatch_get_main_queue(), ^{ [cameraWarmup stopWatching]; });
        updateStatus(menu, @"识别后台未就绪");
    }
}

int main(void) {
    char executable[PROC_PIDPATHINFO_MAXSIZE];
    static const char installedExecutable[] =
        "/Library/Application Support/MacFace/MacFaceAgent.app/Contents/MacOS/MacFaceAgent";
    if (proc_pidpath(getpid(), executable, sizeof(executable)) <= 0 ||
        strcmp(executable, installedExecutable) != 0) {
        return 1;
    }
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        __attribute__((objc_precise_lifetime)) MacFaceStatusMenu *menu = [[MacFaceStatusMenu alloc] init];
        if (loadTemplate().empty()) {
            [menu setStatusMessage:@"等待录入人脸"];
        } else {
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                if (!granted) {
                    updateStatus(menu, @"请允许摄像头权限");
                    os_log_error(OS_LOG_DEFAULT, "MacFace: camera permission denied");
                } else {
                    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                        try {
                            serve(menu);
                        } catch (const cv::Exception &) {
                            updateStatus(menu, @"识别模型无法加载");
                            os_log_error(OS_LOG_DEFAULT, "MacFace: model initialization failed");
                        }
                    });
                }
            }];
        }
        [NSApp run];
    }
}
