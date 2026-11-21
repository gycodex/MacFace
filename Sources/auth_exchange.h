#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { MacFaceNonceSize = 32 };

bool MacFacePeerMatches(int socket, uid_t uid, const char *requirement);
bool MacFaceReceiveChallenge(int socket, uint8_t nonce[MacFaceNonceSize], int timeoutMs);
bool MacFaceSendVerdict(int socket, const uint8_t nonce[MacFaceNonceSize],
                        bool approved, int timeoutMs);
bool MacFaceRequestVerification(int socket, int timeoutMs);

#ifdef __cplusplus
}
#endif
