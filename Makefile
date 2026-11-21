BUNDLE := build/MacFaceProbe.bundle
BINARY := $(BUNDLE)/Contents/MacOS/MacFaceProbe
CFLAGS := -Wall -Wextra -Werror

.PHONY: all test

all: $(BINARY)

AUTH_SOURCES := Sources/probe.c Sources/auth_camera.m Sources/auth_agent.c Sources/auth_exchange.c
AUTH_FRAMEWORKS := -framework AVFoundation -framework Foundation -framework Security -framework SystemConfiguration

$(BINARY): $(AUTH_SOURCES) Sources/auth_exchange.h Sources/auth_input.h Sources/Info.plist Makefile
	mkdir -p "$(BUNDLE)/Contents/MacOS"
	cp Sources/Info.plist "$(BUNDLE)/Contents/Info.plist"
	xcrun clang $(CFLAGS) -fobjc-arc -bundle $(AUTH_SOURCES) $(AUTH_FRAMEWORKS) -o "$@"
	codesign --force --sign - "$(BUNDLE)"

build/probe_test: Tests/probe_test.c Sources/auth_input.h Makefile
	mkdir -p build
	xcrun clang $(CFLAGS) Tests/probe_test.c -o "$@"

build/test_auth_exchange: Tests/test_auth_exchange.c Sources/auth_exchange.c Sources/auth_exchange.h Makefile
	mkdir -p build
	xcrun clang $(CFLAGS) Tests/test_auth_exchange.c Sources/auth_exchange.c -framework Security -framework CoreFoundation -o "$@"
	codesign --force --sign - --identifier com.macface.exchange-test "$@"

build/test_early_glance: Tests/test_early_glance.cpp Sources/early_glance.hpp Makefile
	mkdir -p build
	xcrun clang++ -std=c++17 $(CFLAGS) Tests/test_early_glance.cpp -o "$@"

test: $(BINARY) build/probe_test build/test_auth_exchange build/test_early_glance
	plutil -lint "$(BUNDLE)/Contents/Info.plist"
	codesign --verify --strict "$(BUNDLE)"
	build/probe_test "$(abspath $(BINARY))"
	hash=$$(codesign -dvvv build/test_auth_exchange 2>&1 | sed -n 's/^CDHash=//p'); \
	    test -n "$$hash" && build/test_auth_exchange "cdhash H\"$$hash\""
	bash Tests/test_lock_rule.sh
	build/test_early_glance

.PHONY: release
release:
	bash Scripts/build-release.sh

.PHONY: package
package: release
	bash Scripts/package-macos.sh
