.PHONY: project build test clean
BUILD_DIR ?= /tmp/Tape-build
TEST_DIR ?= /tmp/Tape-tests
project:
	xcodegen generate
build: project
	xcodebuild -project Tape.xcodeproj -scheme Tape -configuration Debug -derivedDataPath "$(BUILD_DIR)" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
test:
	CLANG_MODULE_CACHE_PATH="$(TEST_DIR)/ModuleCache" swift test --scratch-path "$(TEST_DIR)"
clean:
	rm -rf build .build Tape.xcodeproj "$(BUILD_DIR)" "$(TEST_DIR)"

.PHONY: release
release:
	./Scripts/package-release.sh
