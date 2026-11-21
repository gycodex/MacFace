#include "auth_input.h"
#include <os/log.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

void MacFaceCheckCamera(void);
bool MacFaceCheckAgent(void);

struct ProbePlugin {
    const AuthorizationCallbacks *callbacks;
};

struct ProbeMechanism {
    const AuthorizationCallbacks *callbacks;
    AuthorizationEngineRef engine;
    bool checkCamera;
    bool verifyFace;
};

static OSStatus destroyPlugin(AuthorizationPluginRef plugin) {
    free(plugin);
    return errAuthorizationSuccess;
}

static OSStatus createMechanism(AuthorizationPluginRef plugin,
                                AuthorizationEngineRef engine,
                                AuthorizationMechanismId id,
                                AuthorizationMechanismRef *mechanism) {
    if (!plugin || !engine || !id || !mechanism ||
        (strcmp(id, "observe") != 0 && strcmp(id, "camera") != 0 && strcmp(id, "verify-empty") != 0)) {
        return errAuthorizationInternal;
    }
    struct ProbeMechanism *observer = calloc(1, sizeof(*observer));
    if (!observer) {
        return errAuthorizationInternal;
    }
    const struct ProbePlugin *state = plugin;
    observer->callbacks = state->callbacks;
    observer->engine = engine;
    observer->checkCamera = strcmp(id, "camera") == 0;
    observer->verifyFace = strcmp(id, "verify-empty") == 0;
    *mechanism = observer;
    return errAuthorizationSuccess;
}

static OSStatus invokeMechanism(AuthorizationMechanismRef mechanism) {
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT,
                     "MacFaceProbe: authorization observer invoked");
    const struct ProbeMechanism *observer = mechanism;
    if (observer->checkCamera) {
        MacFaceCheckCamera();
    }
    const bool approved = observer->verifyFace &&
        MacFaceInputIsEmpty(observer->callbacks, observer->engine) &&
        MacFaceCheckAgent();
    return observer->callbacks->SetResult(observer->engine,
                                          approved ? kAuthorizationResultAllow : kAuthorizationResultDeny);
}

static OSStatus deactivateMechanism(AuthorizationMechanismRef mechanism) {
    const struct ProbeMechanism *observer = mechanism;
    return observer->callbacks->DidDeactivate(observer->engine);
}

static OSStatus destroyMechanism(AuthorizationMechanismRef mechanism) {
    free(mechanism);
    return errAuthorizationSuccess;
}

static const AuthorizationPluginInterface interface = {
    .version = kAuthorizationPluginInterfaceVersion,
    .PluginDestroy = destroyPlugin,
    .MechanismCreate = createMechanism,
    .MechanismInvoke = invokeMechanism,
    .MechanismDeactivate = deactivateMechanism,
    .MechanismDestroy = destroyMechanism,
};

OSStatus AuthorizationPluginCreate(const AuthorizationCallbacks *callbacks,
                                   AuthorizationPluginRef *plugin,
                                   const AuthorizationPluginInterface **pluginInterface) {
    if (!callbacks || !callbacks->SetResult || !callbacks->DidDeactivate ||
        !plugin || !pluginInterface) {
        return errAuthorizationInternal;
    }
    struct ProbePlugin *observer = calloc(1, sizeof(*observer));
    if (!observer) {
        return errAuthorizationInternal;
    }
    observer->callbacks = callbacks;
    *plugin = observer;
    *pluginInterface = &interface;
    return errAuthorizationSuccess;
}
