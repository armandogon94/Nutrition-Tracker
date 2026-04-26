.PHONY: gen build test clean open

DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
SCHEME        := FitTracker
DESTINATION   := platform=iOS Simulator,name=iPhone 17 Pro

gen:
	xcodegen

# Use ad-hoc signing identity ("Sign to Run Locally") so Keychain APIs
# work on Simulator. CODE_SIGNING_ALLOWED=NO produces an unsigned bundle
# whose SecItemAdd silently fails (errSecMissingEntitlement). DerivedData
# lives in /tmp to dodge resource-fork issues caused by extended
# attributes on the worktree path (which has spaces).
build: gen
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -scheme $(SCHEME) \
	  -destination '$(DESTINATION)' \
	  -derivedDataPath /tmp/fit-derived \
	  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO \
	  build

# Don't disable code signing on test — Keychain APIs (SecItemAdd) on
# Simulator return errSecMissingEntitlement when signing is bypassed.
# Disable parallel testing — MockURLProtocol uses static handler state
# that collides when APIClient/AuthService suites run concurrently.
test: gen
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -scheme $(SCHEME) \
	  -destination '$(DESTINATION)' \
	  -parallel-testing-enabled NO \
	  test

clean:
	rm -rf FitTracker.xcodeproj DerivedData build

open: gen
	open FitTracker.xcodeproj
