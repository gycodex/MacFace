#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Security/Security.h>
#import <os/log.h>

#import "agent_camera.h"
#import "settings_keys.h"
#include "auth_exchange.h"
#include "native_matching.hpp"

#include <array>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <libproc.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

using Clock = std::chrono::steady_clock;

static NSString *const configuration = @"/Library/Application Support/MacFace";
static const char *const authorizationHost = "identifier \"com.apple.authorizationhosthelper.arm64\" and anchor apple";

static void say(NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static AVSpeechSynthesizer *speaker = [[AVSpeechSynthesizer alloc] init];
        [speaker stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        AVSpeechUtterance *sentence = [AVSpeechUtterance speechUtteranceWithString:message];
        sentence.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"zh-CN"];
        [speaker speakUtterance:sentence];
    });
}

static bool checkMovement(MacFaceCamera *camera, NativeFaceMatcher &matcher, const cv::Mat &reference) {
    uint8_t randomness = 0;
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(randomness), &randomness) != errSecSuccess) {
        return false;
    }
    int direction = (randomness & 1) ? 1 : -1;
    std::array<int, 3> steps{direction, -direction, 0};
    auto directionText = [](int step) -> NSString * {
        if (step == 1) return @"请向右转头，保持片刻。";
        if (step == -1) return @"请向左转头，保持片刻。";
        return @"请回到正面。";
    };

    uint64_t version = 0;
    auto start = Clock::now();
    std::optional<double> center;
    while (Clock::now() < start + std::chrono::seconds(3)) {
        cv::Mat frame;
        if (![camera waitForFrame:frame version:version before:[NSDate dateWithTimeIntervalSinceNow:0.25]]) {
            continue;
        }
        auto pose = matcher.verifiedPose(frame, reference);
        if (pose && std::abs(*pose) <= 0.28) {
            center = pose;
            break;
        }
    }
    if (!center) {
        os_log(OS_LOG_DEFAULT, "MacFace: initial matching face unavailable");
        return false;
    }

    auto deadline = start + std::chrono::seconds(12);
    for (int step : steps) {
        say(directionText(step));
        std::optional<Clock::time_point> heldSince;
        bool completed = false;
        auto lastVerified = Clock::now();
        while (Clock::now() < deadline) {
            cv::Mat frame;
            std::optional<double> pose;
            if ([camera waitForFrame:frame version:version before:[NSDate dateWithTimeIntervalSinceNow:0.25]]) {
                pose = matcher.verifiedPose(frame, reference);
            }
            auto now = Clock::now();
            if (!pose) {
                heldSince.reset();
                if (now - lastVerified >= std::chrono::milliseconds(900)) {
                    os_log(OS_LOG_DEFAULT, "MacFace: matching face lost during movement");
                    return false;
                }
                continue;
            }
            lastVerified = now;
            double offset = *pose - *center;
            bool reached = step ? offset * step >= 0.19 : std::abs(offset) <= 0.09;
            if (!reached) {
                heldSince.reset();
                continue;
            }

            if (!heldSince) {
                heldSince = now;
                continue;
            }
            if (now - *heldSince >= std::chrono::milliseconds(220)) {
                completed = true;
                break;
            }
        }
        if (!completed) {
            os_log(OS_LOG_DEFAULT, "MacFace: movement stage timed out");
            return false;
        }
    }
    return true;
}

static bool checkGlance(MacFaceCamera *camera, NativeFaceMatcher &matcher, const cv::Mat &reference) {
    auto deadline = Clock::now() + std::chrono::seconds(3);
    auto nextCheck = Clock::now();
    uint64_t frameVersion = 0;
    int consecutive = 0;
    while (Clock::now() < deadline) {
        cv::Mat frame;
        if (![camera waitForFrame:frame version:frameVersion before:[NSDate dateWithTimeIntervalSinceNow:0.25]] ||
            Clock::now() < nextCheck) {
            continue;
        }
        nextCheck = Clock::now() + std::chrono::milliseconds(160);
        consecutive = matcher.verifiedGlance(frame, reference) ? consecutive + 1 : 0;
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

static bool sessionIsLocked(void) {
    NSDictionary *state = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    id locked = state[@"CGSSessionScreenIsLocked"];
    return [locked isKindOfClass:[NSNumber class]] && [locked boolValue];
}

static void serve(void) {
    @autoreleasepool {
        NativeFaceMatcher matcher([NSBundle mainBundle].resourcePath.fileSystemRepresentation);
        int listener = createListener();
        if (listener < 0) {
            os_log_error(OS_LOG_DEFAULT, "MacFace: could not start verification listener");
            return;
        }

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
                    bool turn = [mode isEqualToString:MacFaceModeTurn];
                    if (!sessionIsLocked() || [mode isEqualToString:MacFaceModePassword]) {
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
                    MacFaceCamera *camera = [[MacFaceCamera alloc] init];
                    try {
                        if ([camera start]) {
                            verified = turn ? checkMovement(camera, matcher, reference) : checkGlance(camera, matcher, reference);
                        } else {
                            os_log_error(OS_LOG_DEFAULT, "MacFace: no external camera");
                        }
                    } catch (const cv::Exception &) {
                        os_log_error(OS_LOG_DEFAULT, "MacFace: recognition failed");
                    }
                    [camera stop];
                    verified = verified && sessionIsLocked();
                    MacFaceSendVerdict(client, nonce, verified, 500);
                    os_log(OS_LOG_DEFAULT, "MacFace: %{public}s check %{public}s", turn ? "movement" : "glance", verified ? "passed" : "denied");
                }
                close(client);
            }
        }
        close(listener);
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
        if (loadTemplate().empty()) {
            os_log(OS_LOG_DEFAULT, "MacFace: waiting for enrollment");
            return 0;
        }
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            if (!granted) {
                os_log_error(OS_LOG_DEFAULT, "MacFace: camera permission denied");
            } else {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    try {
                        serve();
                    } catch (const cv::Exception &) {
                        os_log_error(OS_LOG_DEFAULT, "MacFace: model initialization failed");
                    }
                });
            }
        }];
        [NSApp run];
    }
}
