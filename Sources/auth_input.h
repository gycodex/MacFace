#pragma once

#include <Security/AuthorizationPlugin.h>
#include <Security/AuthorizationTags.h>
#include <stdbool.h>

static inline bool MacFaceInputIsEmpty(const AuthorizationCallbacks *callbacks, AuthorizationEngineRef engine) {
    AuthorizationContextFlags flags = 0;
    const AuthorizationValue *input = NULL;
    return callbacks->GetContextValue &&
        callbacks->GetContextValue(engine, kAuthorizationEnvironmentPassword, &flags, &input) == errAuthorizationSuccess &&
        input && input->length == 0;
}
