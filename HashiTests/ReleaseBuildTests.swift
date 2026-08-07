import Foundation
import Testing
@testable import Hashi

/// Guards against shipping something that only makes sense while developing.
@Suite struct ReleaseBuildTests {

    /// The privacy manifest must use Apple's key names exactly.
    ///
    /// Kakuro's builds 2 and 3 were rejected with ITMS-91056 because the
    /// manifest said `NSPrivacyAccessedAPIReasons` instead of
    /// `NSPrivacyAccessedAPITypeReasons`. Nothing local catches that: the file
    /// is valid property list, so `plutil -lint` passes, `altool
    /// --validate-app` passes, and the build processes to VALID. Apple's own
    /// validator runs afterwards and reports by email only — roughly an hour
    /// per attempt.
    ///
    /// The key sets below are written out **by hand from Apple's
    /// documentation**. That is the whole point: the check that missed this the
    /// first time built its allowlist by reading the manifest, so the
    /// misspelling was compared against itself and passed.
    @Test func privacyManifestUsesApplesKeyNames() throws {
        let topLevel: Set<String> = [
            "NSPrivacyTracking",
            "NSPrivacyTrackingDomains",
            "NSPrivacyCollectedDataTypes",
            "NSPrivacyAccessedAPITypes",
        ]
        let accessedAPI: Set<String> = [
            "NSPrivacyAccessedAPIType",
            "NSPrivacyAccessedAPITypeReasons",
        ]

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "Hashi/PrivacyInfo.xcprivacy"))
        guard let manifest = try PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: Any] else {
            Issue.record("the privacy manifest is not a dictionary")
            return
        }

        for key in manifest.keys {
            #expect(topLevel.contains(key), "\(key) is not a privacy manifest key")
        }

        let entries = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        #expect(!entries.isEmpty, "the app uses UserDefaults, so it must declare a reason")
        for entry in entries {
            for key in entry.keys {
                #expect(accessedAPI.contains(key), "\(key) is not an accessed-API key")
            }
            for required in accessedAPI {
                #expect(entry[required] != nil, "the entry is missing \(required)")
            }
            let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            #expect(!reasons.isEmpty, "a declared API needs at least one reason code")
        }
    }

    /// A release build should not carry developer logging.
    @Test func noPrintOrNSLogInShippedSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Hashi")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "found no sources to scan")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), !code.hasPrefix("///") else { continue }
                for banned in ["print(", "NSLog(", "debugPrint("] {
                    #expect(!code.contains(banned),
                            "\(file.lastPathComponent):\(index + 1) uses \(banned)")
                }
            }
        }
    }

    /// The screenshot unlock grants the paid tier from a launch argument. It is
    /// wrapped in `#if DEBUG` so it cannot exist in the binary that ships; this
    /// fails the moment someone lifts it out of that block.
    @Test func screenshotUnlockIsDebugOnly() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Hashi/App/HashiApp.swift"),
                                encoding: .utf8)
        guard let use = source.range(of: "screenshotUnlockFlag)") else {
            Issue.record("the screenshot unlock flag is no longer read; delete this test")
            return
        }
        let before = source[source.startIndex..<use.lowerBound]
        let lastDebug = before.range(of: "#if DEBUG", options: .backwards)
        let lastEndif = before.range(of: "#endif", options: .backwards)
        #expect(lastDebug != nil, "the screenshot unlock is not inside #if DEBUG")
        if let lastDebug, let lastEndif {
            #expect(lastDebug.lowerBound > lastEndif.lowerBound,
                    "the screenshot unlock sits outside its #if DEBUG block")
        }
    }

    /// The StoreKit config must live outside `Hashi/`. The synchronized root
    /// group copies anything under there into the app bundle, and a .storekit
    /// file in a shipping bundle is noise at best.
    @Test func storeKitConfigLivesOutsideTheAppFolderAndMatchesTheProduct() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()

        let appFolder = root.appending(path: "Hashi")
        let strays = FileManager.default.enumerator(at: appFolder, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "storekit" }
        #expect(strays.isEmpty,
                "a .storekit under Hashi/ ships inside the app bundle: \(strays.map(\.lastPathComponent))")

        let data = try Data(contentsOf: root.appending(path: "StoreKit/Hashi.storekit"))
        let config = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let products = config?["products"] as? [[String: Any]] ?? []
        #expect(products.count == 1, "this app sells exactly one thing")
        let product = try #require(products.first)
        #expect(product["productID"] as? String == StoreProduct.fullUnlock)
        #expect(product["type"] as? String == "NonConsumable")
        #expect(product["familyShareable"] as? Bool == true)
        #expect(product["displayPrice"] as? String == "4.99")
    }

    /// The shared scheme must point at the config, and must not carry an empty
    /// `<TestPlans>`: that makes xcodebuild report "not configured for the test
    /// action", which reads exactly like a broken project.
    @Test func schemeWiresTheStoreKitConfigAndKeepsTestActionClean() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let scheme = try String(
            contentsOf: root.appending(path: "Hashi.xcodeproj/xcshareddata/xcschemes/Hashi.xcscheme"),
            encoding: .utf8)
        #expect(scheme.contains("../../../StoreKit/Hashi.storekit"),
                "the scheme does not reference the StoreKit config, so purchases cannot be tested")
        #expect(!scheme.contains("<TestPlans"),
                "an empty <TestPlans> element breaks `xcodebuild test`")
    }

    /// The engine must stay UI-free: it compiles into the CLI bench, and
    /// generation runs off the main actor. A stray SwiftUI import there breaks
    /// both, and the compile failure would surface far from the cause.
    @Test func engineImportsNoUIFrameworks() throws {
        let engine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Hashi/Engine")
        let files = FileManager.default.enumerator(at: engine, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 7, "found only \(files.count) engine sources")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for banned in ["import SwiftUI", "import UIKit", "import AppKit", "import Observation"] {
                #expect(!text.contains(banned),
                        "\(file.lastPathComponent) imports \(banned) — the engine must stay pure")
            }
        }
    }
}
