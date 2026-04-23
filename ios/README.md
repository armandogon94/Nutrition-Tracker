# FitTracker iOS

Native iOS 26 SwiftUI client for [FitTracker](../README.md). See [../SPEC.md](../SPEC.md) for the full product spec and [../plans/](../plans/) for the slice-by-slice build plan.

## Requirements

- Xcode 16 or later
- iOS 26 SDK
- `xcodegen` (`brew install xcodegen`)
- Swift 6.0
- Strict concurrency enabled

## Getting started

```bash
# Regenerate the project from project.yml (run after any project.yml change)
cd ios
xcodegen

# Open in Xcode
open FitTracker.xcodeproj
```

Or build + test from the command line:

```bash
# If xcode-select points to CLT instead of Xcode.app, override via DEVELOPER_DIR
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme FitTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

## Backend

Point the app at a local backend by editing `APIConfig.swift` or setting `API_BASE_URL` in `Info.plist`. Default is `http://localhost:8001`. See [../backend/](../backend/) for backend setup.

## Project layout

```
ios/
├── project.yml                    # xcodegen source of truth
├── FitTracker/
│   ├── App/                       # @main + AppRoot
│   ├── Core/
│   │   ├── Networking/            # APIClient actor, DTOs, errors
│   │   ├── Security/              # Keychain, token provider
│   │   ├── Theme/                 # AppTheme protocol + Liquid Glass + Health Cards
│   │   ├── Persistence/           # SwiftData schema (Slice 2)
│   │   ├── Services/              # Domain services (per slice)
│   │   ├── Health/                # HealthKit facade (Slices 2, 3, 7)
│   │   └── …
│   ├── Features/
│   │   ├── Auth/, Home/, Scan/, Meals/, MealPlan/,
│   │   │ Profile/, Workouts/, Exercises/, History/, Settings/
│   │   └── Debug/                 # dev-only PingView (Slice 0)
│   ├── Models/                    # Shared DTOs mirroring backend
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Localizable.xcstrings  # es-419 + en (Slice 11)
│       ├── PrivacyInfo.xcprivacy
│       └── Info.plist
└── FitTrackerTests/
    └── …                          # Swift Testing unit tests
```

## Never hand-edit `FitTracker.xcodeproj` — always regenerate via `xcodegen`.
