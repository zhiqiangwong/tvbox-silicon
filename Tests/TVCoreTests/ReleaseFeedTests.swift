import Foundation
import Testing
@testable import TVCore

private func release(_ version: String, build: Int? = nil, platforms: [String] = ["macos", "ios", "tvos"], features: [ReleaseFeed.Feature] = [
    .init(symbol: "sparkles", title: "New", detail: "Something new")
]) -> ReleaseFeed.Release {
    .init(version: version, build: build, links: Dictionary(uniqueKeysWithValues: platforms.map { ($0, URL(string: "https://example.com/\($0)")!) }), features: features)
}

@Test func versionsCompareNumerically() {
    #expect(AppVersion("1.0.1") > AppVersion("1.0"))
    #expect(AppVersion("1.10") > AppVersion("1.9.9"))
    #expect(AppVersion("1.1") == AppVersion("1.1.0"))
    #expect(AppVersion("2.0b3") > AppVersion("1.9"))
    #expect(!(AppVersion("1.0") < AppVersion("1.0.0")))
}

@Test func updatesListNewerReleasesForThisPlatformNewestFirst() {
    let feed = ReleaseFeed(releases: [release("1.0.1"), release("1.2", platforms: ["macos"]), release("1.1"), release("1.0")])
    #expect(feed.updates(after: "1.0.1", platform: "macos").map(\.version) == ["1.2", "1.1"])
    #expect(feed.updates(after: "1.0.1", platform: "tvos").map(\.version) == ["1.1"])
    #expect(feed.updates(after: "1.2", platform: "macos").isEmpty)
}

@Test func compatibleBuildResolutionPreservesVersionWithoutDirectUpstreamLinkOnIOS16() {
    let feed = ReleaseFeed(releases: [release("1.8.2"), release("1.8.3"), release("1.8.4")])

    let ios16 = feed.resolveUpdate(after: "1.8.2", platform: "ios", requiresCompatibleBuild: true)
    #expect(!ios16.isLatestVersion)
    #expect(ios16.latest?.version == "1.8.4")
    #expect(ios16.directDownloadURL == nil)
    #expect(ios16.compatibilityGuidance?.contains("1.8.4") == true)
    #expect(ios16.compatibilityGuidance?.contains("iOS 16") == true)

    let ios17 = feed.resolveUpdate(after: "1.8.2", platform: "ios", requiresCompatibleBuild: false)
    #expect(!ios17.isLatestVersion)
    #expect(ios17.latest?.version == "1.8.4")
    #expect(ios17.directDownloadURL?.absoluteString == "https://example.com/ios")
    #expect(ios17.compatibilityGuidance == nil)

    let upToDate = feed.resolveUpdate(after: "1.8.4", platform: "ios", requiresCompatibleBuild: true)
    #expect(upToDate.isLatestVersion)
    #expect(upToDate.latest == nil)
    #expect(upToDate.compatibilityGuidance == nil)
}

@Test func intelMacsUseTheirOwnPackageAndSkipReleasesWithoutOne() {
    let feed = ReleaseFeed(releases: [release("1.7.2"), release("1.7.3", platforms: ["macos", ReleaseFeed.intelMacKey])])
    #expect(feed.updates(after: "1.7.1", platform: "macos", intelMac: true).map(\.version) == ["1.7.3"])
    #expect(feed.updates(after: "1.7.1", platform: "macos", intelMac: false).map(\.version) == ["1.7.3", "1.7.2"])
    #expect(feed.releases[1].link(for: "macos", intelMac: true)?.absoluteString == "https://example.com/macos-x86_64")
    #expect(feed.releases[1].link(for: "macos", intelMac: false)?.absoluteString == "https://example.com/macos")
    #expect(feed.releases[1].link(for: "ios", intelMac: true) == nil)
}

@Test func whatsNewCoversSkippedReleasesWithFeatures() {
    let macOnly = ReleaseFeed.Feature(symbol: "macwindow", title: "Mac", detail: "Mac only", platforms: ["macos"])
    let feed = ReleaseFeed(releases: [release("1.0"), release("1.1"), release("1.2", features: [macOnly]), release("1.3"), release("1.4")])
    #expect(feed.whatsNew(since: "1.0", current: "1.3", platform: "macos").map(\.version) == ["1.3", "1.2", "1.1"])
    #expect(feed.whatsNew(since: "1.0", current: "1.3", platform: "ios").map(\.version) == ["1.3", "1.1"])
    #expect(feed.whatsNew(since: nil, current: "1.3", platform: "ios").map(\.version) == ["1.3"])
    #expect(feed.whatsNew(since: "1.3", current: "1.3", platform: "ios").isEmpty)
    #expect(feed.release("1.2").features(for: "tvos").isEmpty)
}

@Test func fetchedEntriesReplaceBundledOnes() {
    let bundled = ReleaseFeed(releases: [release("1.0"), release("1.1", features: [])])
    let fetched = ReleaseFeed(releases: [release("1.1.0"), release("1.2")])
    let merged = bundled.merged(with: fetched)
    #expect(merged.releases.map(\.version).sorted() == ["1.0", "1.1.0", "1.2"])
    #expect(merged.release("1.1").features.count == 1)
}

/// TestFlight builds are all 1.7.7; build numbers decide, and only up to the build testers can install.
@Test func testFlightUpdatesWaitForTheLiveBuild() {
    let releases = [release("1.7.8", build: 27), release("1.7.9", build: 28, platforms: ["ios"]), release("1.7.10", build: 29), release("1.7.11", build: 30)]
    let link = URL(string: "https://testflight.apple.com/join/x")!
    let feed = ReleaseFeed(releases: releases, testflight: ["ios": .init(build: 29, link: link), "tvos": .init(build: 27)])
    #expect(feed.testFlightUpdates(after: 27, platform: "ios").map(\.version) == ["1.7.10", "1.7.9"])
    #expect(feed.testFlightUpdates(after: 29, platform: "ios").isEmpty)
    #expect(feed.testFlightUpdates(after: 25, platform: "tvos").map(\.version) == ["1.7.8"])
    #expect(feed.testFlightUpdates(after: 27, platform: "tvos").isEmpty)
    #expect(feed.testFlightUpdates(after: 27, platform: "macos").isEmpty)
    #expect(ReleaseFeed(releases: releases).testFlightUpdates(after: 27, platform: "ios").isEmpty)
}

@Test func testFlightWhatsNewCoversSkippedBuilds() {
    let feed = ReleaseFeed(releases: [release("1.7.6"), release("1.7.8", build: 27), release("1.7.9", build: 28, platforms: ["ios"]),
                                      release("1.7.10", build: 29)])
    #expect(feed.testFlightWhatsNew(since: 27, current: 29, platform: "ios").map(\.version) == ["1.7.10", "1.7.9"])
    #expect(feed.testFlightWhatsNew(since: nil, current: 29, platform: "ios").map(\.version) == ["1.7.10"])
    #expect(feed.testFlightWhatsNew(since: nil, current: 26, platform: "ios").isEmpty)
    #expect(feed.testFlightWhatsNew(since: 29, current: 29, platform: "ios").isEmpty)
}

@Test func fetchedTestFlightBuildsReplaceBundledOnes() {
    let bundled = ReleaseFeed(releases: [release("1.0")], testflight: ["ios": .init(build: 1)])
    #expect(bundled.merged(with: ReleaseFeed(releases: [])).testflight?["ios"]?.build == 1)
    #expect(bundled.merged(with: ReleaseFeed(releases: [], testflight: ["ios": .init(build: 2)])).testflight?["ios"]?.build == 2)
}

@Test func localizedTextFallsBackToEnglish() throws {
    let text = try JSONDecoder().decode(LocalizedText.self, from: Data(#"{"en": "New", "zh-Hans": "新"}"#.utf8))
    #expect(text.text(language: "zh-CN") == "新")
    #expect(text.text(language: "ja") == "New")
    #expect(try JSONDecoder().decode(LocalizedText.self, from: Data(#""Plain""#.utf8)).text(language: "ja") == "Plain")
}

/// Sparkle reads one appcast per Mac package; Scripts/make-appcast.sh writes them where the website publishes them.
@Test func eachMacPackageHasItsOwnPublishedAppcast() throws {
    let site = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../website/public")
    for intel in [false, true] {
        let address = ReleaseFeed.appcastAddress(intelMac: intel)
        #expect(address.lastPathComponent == (intel ? "macos-x86_64.xml" : "macos-arm64.xml"))
        let appcast = try String(contentsOf: site.appending(path: String(address.path.dropFirst())), encoding: .utf8)
        #expect(appcast.contains("<channel>"))
    }
}

/// The feed the website publishes and the apps bundle.
@Test func publishedFeedIsValidAndTranslated() throws {
    let file = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../website/public/releases.json")
    let feed = try JSONDecoder().decode(ReleaseFeed.self, from: Data(contentsOf: file))
    #expect(!feed.releases.isEmpty)
    #expect(Set(feed.releases.map { AppVersion($0.version) }).count == feed.releases.count)
    // TestFlight builds find their release by build number, so every release has one, newer releases higher.
    let builds = feed.releases.sorted { AppVersion($0.version) > AppVersion($1.version) }.map { $0.build ?? 0 }
    #expect(!builds.contains(0), "a release has no build")
    #expect(builds == builds.sorted(by: >) && Set(builds).count == builds.count, "builds don't rise with versions")
    let project = try String(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../project.yml"), encoding: .utf8)
    let projectBuild = project.firstMatch(of: /CURRENT_PROJECT_VERSION: '(\d+)'/).flatMap { Int($0.1) }
    #expect(builds.first == projectBuild, "the newest release's build is not CURRENT_PROJECT_VERSION in project.yml")
    for (platform, testflight) in feed.testflight ?? [:] {
        #expect(["ios", "tvos"].contains(platform) && testflight.link != nil, "testflight.\(platform)")
        #expect(testflight.build <= builds.first ?? 0, "testflight.\(platform) is ahead of the newest release")
    }
    for entry in feed.releases {
        #expect(!entry.links.isEmpty, "\(entry.version) has no links")
        #expect(Set(entry.links.keys).isSubset(of: ["macos", ReleaseFeed.intelMacKey, "ios", "tvos"]), "\(entry.version) has an unknown platform")
        for feature in entry.features {
            for language in L10n.supportedLanguages {
                #expect(!(feature.title.values[language] ?? "").isEmpty, "\(entry.version) \(feature.symbol): no \(language) title")
                #expect(!(feature.detail.values[language] ?? "").isEmpty, "\(entry.version) \(feature.symbol): no \(language) detail")
            }
        }
    }
}

/// The AltStore source the website publishes; Scripts/make-altstore-source.py adds each iOS release from its IPA.
@Test func altStoreSourceListsReleasedIPAsNewestFirst() throws {
    let site = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../website/public")
    let feed = try JSONDecoder().decode(ReleaseFeed.self, from: Data(contentsOf: site.appending(path: "releases.json")))
    let source = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: site.appending(path: "altstore.json"))) as? [String: Any])
    let apps = try #require(source["apps"] as? [[String: Any]])
    #expect(apps.count == 1)
    let app = try #require(apps.first)
    #expect((app["bundleIdentifier"] as? String)?.hasSuffix(".yingxia.ios") == true)
    #expect(source["featuredApps"] as? [String] == [app["bundleIdentifier"] as? String].compactMap { $0 })
    let permissions = try #require(app["appPermissions"] as? [String: Any])
    #expect(permissions["entitlements"] is [Any] && permissions["privacy"] is [String: String])
    let versions = try #require(app["versions"] as? [[String: Any]])
    #expect(!versions.isEmpty)
    let numbers = versions.compactMap { $0["version"] as? String }
    #expect(numbers.count == versions.count)
    #expect(numbers.map(AppVersion.init) == numbers.map(AppVersion.init).sorted(by: >), "versions are not newest first")
    for version in versions {
        let number = version["version"] as? String ?? ""
        #expect(version["downloadURL"] as? String == "https://download.getmegaportal.com/yingxia/\(number)/Yingxia-\(number)-ios.ipa")
        #expect((version["sha256"] as? String)?.wholeMatch(of: /[0-9a-f]{64}/) != nil, "\(number) has no SHA-256")
        #expect((version["size"] as? Int ?? 0) > 0, "\(number) has no size")
        for key in ["buildVersion", "date", "minOSVersion", "localizedDescription"] {
            #expect(!(version[key] as? String ?? "").isEmpty, "\(number) has no \(key)")
        }
        #expect(feed.releases.contains { AppVersion($0.version) == AppVersion(number) && $0.links["ios"] != nil },
                "\(number) is not an iOS release in releases.json")
    }
}

private extension ReleaseFeed {
    func release(_ version: String) -> Release { releases.first { AppVersion($0.version) == AppVersion(version) }! }
}

@Test func pendingRelaunchReportsSlowAndMissedUpdates() throws {
    let requested = Date(timeIntervalSince1970: 1_000_000)
    let pending = PendingRelaunch(from: "1.7.12", to: "1.7.13", build: "32", requested: requested)
    let decoded = try JSONDecoder().decode(PendingRelaunch.self, from: JSONEncoder().encode(pending))
    #expect(decoded == pending)

    let quick = pending.outcome(version: "1.7.13", build: "32", now: requested.addingTimeInterval(9))
    #expect(quick.level == .info)
    #expect(quick.message == "Updated from 1.7.12 to 1.7.13; relaunched in 9 s")
    // Someone had to force-quit: the update went in, but long after Relaunch.
    let slow = pending.outcome(version: "1.7.13", build: "32", now: requested.addingTimeInterval(PendingRelaunch.slow + 30))
    #expect(slow.level == .error)
    #expect(slow.message.contains("took 90 s"))
    let missed = pending.outcome(version: "1.7.12", build: "31", now: requested.addingTimeInterval(20))
    #expect(missed.level == .error)
    #expect(missed.message == "Update to 1.7.13 (32) didn't install: opened 1.7.12 (31) 20 s after Relaunch")
}

@Test func relaunchFailureIsTranslated() {
    let key = "Yingxia couldn't relaunch to finish the update. Quit Yingxia and open it again."
    #expect(L10n.text(key, language: "en") == key)
    for language in L10n.supportedLanguages where language != "en" { #expect(L10n.text(key, language: language) != key) }
}
