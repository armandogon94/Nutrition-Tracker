.PHONY: gen build test clean open

DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
SCHEME        := FitTracker
DESTINATION   := platform=iOS Simulator,name=iPhone 17 Pro

gen:
	xcodegen

build: gen
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -scheme $(SCHEME) \
	  -destination '$(DESTINATION)' \
	  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
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
