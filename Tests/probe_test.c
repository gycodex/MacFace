#include <Security/AuthorizationPlugin.h>
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>

static unsigned resultCount;
static unsigned deactivateCount;
static char engineToken;

static OSStatus recordResult(AuthorizationEngineRef engine, AuthorizationResult result) {
    assert(engine == (AuthorizationEngineRef)&engineToken);
    assert(result == kAuthorizationResultDeny);
    resultCount++;
    return errAuthorizationSuccess;
}

static OSStatus recordDeactivation(AuthorizationEngineRef engine) {
    assert(engine == (AuthorizationEngineRef)&engineToken);
    deactivateCount++;
    return errAuthorizationSuccess;
}

int main(int argc, char **argv) {
    assert(argc == 2);
    void *bundle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!bundle) {
        fprintf(stderr, "%s\n", dlerror());
        return 1;
    }
    typeof(AuthorizationPluginCreate) *create = dlsym(bundle, "AuthorizationPluginCreate");
    assert(create);

    const AuthorizationCallbacks callbacks = {
        .version = kAuthorizationCallbacksVersion,
        .SetResult = recordResult,
        .DidDeactivate = recordDeactivation,
    };
    const AuthorizationPluginInterface *interface = NULL;
    AuthorizationPluginRef plugin = NULL;
    AuthorizationMechanismRef mechanism = NULL;
    AuthorizationEngineRef engine = (AuthorizationEngineRef)&engineToken;
    assert(create(&callbacks, &plugin, &interface) == errAuthorizationSuccess);
    assert(interface->version == kAuthorizationPluginInterfaceVersion);
    assert(interface->MechanismCreate(plugin, engine, "wrong", &mechanism) != errAuthorizationSuccess);
    assert(interface->MechanismCreate(plugin, engine, "observe", &mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismInvoke(mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismDeactivate(mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismDestroy(mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismCreate(plugin, engine, "camera", &mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismDestroy(mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismCreate(plugin, engine, "verify", &mechanism) == errAuthorizationSuccess);
    assert(interface->MechanismDestroy(mechanism) == errAuthorizationSuccess);
    assert(interface->PluginDestroy(plugin) == errAuthorizationSuccess);
    assert(resultCount == 1 && deactivateCount == 1);
    dlclose(bundle);
    puts("PASS: probe invoked, denied its request, and deactivated");
}
