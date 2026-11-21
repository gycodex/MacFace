#include "auth_exchange.h"

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <fcntl.h>
#include <os/log.h>
#include <stdio.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

static const char agentApp[] = "/Library/Application Support/MacFace/MacFaceAgent.app";

static bool rootOwned(const char *path, mode_t type) {
    struct stat info;
    return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == type &&
        info.st_uid == 0 && !(info.st_mode & (S_IWGRP | S_IWOTH));
}

static bool pinnedAgentRequirement(char requirement[53]) {
    if (!rootOwned("/Library/Application Support/MacFace", S_IFDIR) ||
        !rootOwned(agentApp, S_IFDIR)) {
        return false;
    }

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)agentApp,
                                                           sizeof(agentApp) - 1, true);
    if (!url) {
        return false;
    }
    SecStaticCodeRef agent = NULL;
    CFDictionaryRef details = NULL;
    bool trusted = false;
    if (SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &agent) == errSecSuccess &&
        SecStaticCodeCheckValidity(agent, kSecCSStrictValidate, NULL) == errSecSuccess &&
        SecCodeCopySigningInformation(agent, kSecCSSigningInformation, &details) == errSecSuccess) {
        CFDataRef hash = CFDictionaryGetValue(details, kSecCodeInfoUnique);
        if (hash && CFGetTypeID(hash) == CFDataGetTypeID() && CFDataGetLength(hash) == 20) {
            const UInt8 *bytes = CFDataGetBytePtr(hash);
            snprintf(requirement, 53, "cdhash H\"");
            for (size_t index = 0; index < 20; ++index) {
                snprintf(requirement + 9 + index * 2, 3, "%02x", bytes[index]);
            }
            requirement[49] = '"';
            requirement[50] = '\0';
            trusted = true;
        }
    }
    if (details) CFRelease(details);
    if (agent) CFRelease(agent);
    CFRelease(url);
    return trusted;
}

bool MacFaceCheckAgent(void) {
    uid_t uid = 0;
    CFStringRef console = SCDynamicStoreCopyConsoleUser(NULL, &uid, NULL);
    if (!console) {
        return false;
    }
    CFRelease(console);
    char requirement[53];
    if (uid < 500 || !pinnedAgentRequirement(requirement)) {
        return false;
    }

    struct sockaddr_un endpoint = {.sun_family = AF_UNIX};
    int length = snprintf(endpoint.sun_path, sizeof(endpoint.sun_path), "/tmp/com.macface.agent.%u.sock", uid);
    if (length < 0 || (size_t)length >= sizeof(endpoint.sun_path)) {
        return false;
    }
    int client = socket(AF_UNIX, SOCK_STREAM, 0);
    if (client < 0) {
        return false;
    }
    bool connected = fcntl(client, F_SETFL, O_NONBLOCK) == 0 &&
        connect(client, (struct sockaddr *)&endpoint, sizeof(endpoint)) == 0;
    bool trusted = connected && MacFacePeerMatches(client, uid, requirement);
    bool approved = trusted && MacFaceRequestVerification(client, 13500);
    close(client);
    os_log(OS_LOG_DEFAULT, "MacFace: agent connected=%d validated=%d verification=%{public}s",
           connected, trusted, approved ? "approved" : "denied");
    return approved;
}
