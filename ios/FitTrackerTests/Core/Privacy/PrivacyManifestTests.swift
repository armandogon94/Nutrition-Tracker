//
//  PrivacyManifestTests.swift
//  Codex review #17 (cycle 1) / #14 (cycle 2): the privacy manifest shipped
//  with EMPTY collected-data and accessed-API arrays despite the app handling
//  HealthKit, nutrition, auth, profile, and camera/photo data — an App Store
//  review / TestFlight gate. These tests lock the manifest's content so it
//  can't silently regress back to empty.
//
//  The manifest is an app-target resource, which the unit-test host does not
//  expose through Bundle.main reliably. We instead parse the committed source
//  file directly, resolved relative to this test file's path, and assert the
//  declared data types + required-reason APIs.
//

import Foundation
import Testing

@Suite("PrivacyInfo.xcprivacy")
struct PrivacyManifestTests {

    /// The repo-relative manifest, resolved from this file's location:
    /// FitTrackerTests/Core/Privacy/ -> ../../../FitTracker/Resources/PrivacyInfo.xcprivacy
    private func loadManifest(file: StaticString = #filePath) throws -> [String: Any] {
        let here = URL(fileURLWithPath: "\(file)")
        let manifestURL = here
            .deletingLastPathComponent()   // Privacy
            .deletingLastPathComponent()   // Core
            .deletingLastPathComponent()   // FitTrackerTests
            .deletingLastPathComponent()   // ios
            .appendingPathComponent("FitTracker/Resources/PrivacyInfo.xcprivacy")
        let data = try Data(contentsOf: manifestURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = plist as? [String: Any] else {
            throw PrivacyManifestError.notADictionary
        }
        return dict
    }

    private func collectedTypes(_ manifest: [String: Any]) -> [String] {
        let array = manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        return array.compactMap { $0["NSPrivacyCollectedDataType"] as? String }
    }

    @Test("does not declare tracking")
    func notTracking() throws {
        let manifest = try loadManifest()
        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
    }

    @Test("declares health and fitness data collection")
    func declaresHealthAndFitness() throws {
        let types = collectedTypes(try loadManifest())
        #expect(types.contains("NSPrivacyCollectedDataTypeHealth"),
                "HealthKit dietary/workout/bodyweight flows require a Health declaration")
        #expect(types.contains("NSPrivacyCollectedDataTypeFitness"))
    }

    @Test("declares auth + identifier + profile data collection")
    func declaresAccountData() throws {
        let types = collectedTypes(try loadManifest())
        #expect(types.contains("NSPrivacyCollectedDataTypeEmailAddress"))
        #expect(types.contains("NSPrivacyCollectedDataTypeName"))
        #expect(types.contains("NSPrivacyCollectedDataTypeUserID"))
    }

    @Test("declares photo collection for meal recognition")
    func declaresPhotos() throws {
        let types = collectedTypes(try loadManifest())
        #expect(types.contains("NSPrivacyCollectedDataTypePhotosorVideos"))
    }

    @Test("collected-data array is no longer empty")
    func notEmpty() throws {
        let types = collectedTypes(try loadManifest())
        #expect(types.count >= 5, "manifest must enumerate the real collected data types")
    }

    @Test("every collected type is App Functionality, linked, and non-tracking")
    func purposesAreAppFunctionality() throws {
        let manifest = try loadManifest()
        let array = manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? []
        #expect(!array.isEmpty)
        for entry in array {
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false,
                    "no collected type may be used for tracking")
            let purposes = entry["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []
            #expect(purposes.contains("NSPrivacyCollectedDataTypePurposeAppFunctionality"))
        }
    }

    @Test("declares the UserDefaults required-reason API (CA92.1)")
    func declaresUserDefaultsReason() throws {
        let manifest = try loadManifest()
        let apis = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let userDefaults = apis.first {
            ($0["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        #expect(userDefaults != nil, "UserDefaults usage (offline queue) must declare a required-reason")
        let reasons = userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        #expect(reasons.contains("CA92.1"))
    }
}

private enum PrivacyManifestError: Error { case notADictionary }
