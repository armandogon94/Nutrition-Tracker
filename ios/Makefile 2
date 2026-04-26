.PHONY: gen build test clean open

DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer
SCHEME        := FitTracker
DESTINATION   := platform=iOS Simulator,name=iPhone 17 Pro

gen:
	xcodegen

build: gen
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -scheme $(SCHEME) \
	  -destination '$(DESTINATION)' build

test: gen
	DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -scheme $(SCHEME) \
	  -destination '$(DESTINATION)' test

clean:
	rm -rf FitTracker.xcodeproj DerivedData build

open: gen
	open FitTracker.xcodeproj
