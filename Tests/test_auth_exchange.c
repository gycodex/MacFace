#include "../Sources/auth_exchange.h"

#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>

struct TestPeer {
    int socket;
    bool approve;
    bool corruptNonce;
};

static void *respond(void *value) {
    struct TestPeer *peer = value;
    uint8_t nonce[MacFaceNonceSize];
    assert(MacFaceReceiveChallenge(peer->socket, nonce, 1000));
    if (peer->corruptNonce) {
        nonce[0] ^= 1;
    }
    assert(MacFaceSendVerdict(peer->socket, nonce, peer->approve, 1000));
    return NULL;
}

static void verifyExchange(bool approve, bool corruptNonce, bool expected) {
    int sockets[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    struct TestPeer peer = {sockets[1], approve, corruptNonce};
    pthread_t responder;
    assert(pthread_create(&responder, NULL, respond, &peer) == 0);
    assert(MacFaceRequestVerification(sockets[0], 1000) == expected);
    assert(pthread_join(responder, NULL) == 0);
    close(sockets[0]);
    close(sockets[1]);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    verifyExchange(true, false, true);
    verifyExchange(false, false, false);
    verifyExchange(true, true, false);
    int sockets[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    assert(!MacFaceRequestVerification(sockets[0], 30));
    assert(MacFacePeerMatches(sockets[0], getuid(), argv[1]));
    assert(!MacFacePeerMatches(sockets[0], getuid(), "identifier \"com.macface.wrong-peer\""));
    assert(!MacFacePeerMatches(sockets[0], getuid() ^ 1, "identifier \"com.macface.exchange-test\""));
    close(sockets[0]);
    close(sockets[1]);
    puts("PASS: accepted matching challenge; rejected denial, stale response, timeout, and mismatched UID");
}
