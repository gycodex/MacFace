#include "auth_exchange.h"

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <bsm/audit.h>
#include <errno.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static int64_t monotonicMilliseconds(void) {
    return (int64_t)(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) / 1000000);
}

static bool transfer(int socket, void *data, size_t bytes, bool writing, int64_t deadline) {
    uint8_t *cursor = data;
    while (bytes > 0) {
        int64_t remaining = deadline - monotonicMilliseconds();
        if (remaining <= 0) {
            return false;
        }

        struct pollfd pollSocket = {.fd = socket, .events = writing ? POLLOUT : POLLIN};
        int ready = poll(&pollSocket, 1, (int)remaining);
        if (ready < 0 && errno == EINTR) {
            continue;
        }
        if (ready <= 0 || !(pollSocket.revents & pollSocket.events)) {
            return false;
        }

        ssize_t count = writing ? send(socket, cursor, bytes, MSG_DONTWAIT | MSG_NOSIGNAL)
                                : recv(socket, cursor, bytes, MSG_DONTWAIT);
        if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) {
            continue;
        }
        if (count <= 0) {
            return false;
        }
        cursor += count;
        bytes -= (size_t)count;
    }
    return true;
}

bool MacFacePeerMatches(int socket, uid_t uid, const char *requirement) {
    uid_t peerUID;
    gid_t peerGID;
    if (!requirement || getpeereid(socket, &peerUID, &peerGID) != 0 || peerUID != uid) {
        return false;
    }
    audit_token_t token;
    socklen_t tokenLength = sizeof(token);
    if (getsockopt(socket, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &tokenLength) != 0 ||
        tokenLength != sizeof(token)) {
        return false;
    }

    CFDataRef audit = CFDataCreate(NULL, (const UInt8 *)&token, sizeof(token));
    CFStringRef expression = CFStringCreateWithCString(NULL, requirement, kCFStringEncodingUTF8);
    if (!audit || !expression) {
        if (audit) CFRelease(audit);
        if (expression) CFRelease(expression);
        return false;
    }
    const void *keys[] = {kSecGuestAttributeAudit};
    const void *values[] = {audit};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
                                                    &kCFTypeDictionaryKeyCallBacks,
                                                    &kCFTypeDictionaryValueCallBacks);
    SecCodeRef peerCode = NULL;
    SecRequirementRef peerRequirement = NULL;
    bool matches = attributes &&
        SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &peerCode) == errSecSuccess &&
        SecRequirementCreateWithString(expression, kSecCSDefaultFlags, &peerRequirement) == errSecSuccess &&
        SecCodeCheckValidity(peerCode, kSecCSDefaultFlags, peerRequirement) == errSecSuccess;
    if (peerRequirement) CFRelease(peerRequirement);
    if (peerCode) CFRelease(peerCode);
    if (attributes) CFRelease(attributes);
    CFRelease(expression);
    CFRelease(audit);
    return matches;
}

bool MacFaceReceiveChallenge(int socket, uint8_t nonce[MacFaceNonceSize], int timeoutMs) {
    return transfer(socket, nonce, MacFaceNonceSize, false, monotonicMilliseconds() + timeoutMs);
}

bool MacFaceSendVerdict(int socket, const uint8_t nonce[MacFaceNonceSize],
                        bool approved, int timeoutMs) {
    uint8_t response[MacFaceNonceSize + 1];
    memcpy(response, nonce, MacFaceNonceSize);
    response[MacFaceNonceSize] = approved ? 1 : 0;
    return transfer(socket, response, sizeof(response), true, monotonicMilliseconds() + timeoutMs);
}

bool MacFaceRequestVerification(int socket, int timeoutMs) {
    uint8_t nonce[MacFaceNonceSize];
    uint8_t response[MacFaceNonceSize + 1];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(nonce), nonce) != errSecSuccess) {
        return false;
    }
    int64_t deadline = monotonicMilliseconds() + timeoutMs;
    return transfer(socket, nonce, sizeof(nonce), true, deadline) &&
        transfer(socket, response, sizeof(response), false, deadline) &&
        response[MacFaceNonceSize] == 1 &&
        memcmp(nonce, response, sizeof(nonce)) == 0;
}
