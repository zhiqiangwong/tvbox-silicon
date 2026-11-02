import Foundation

/// Release announcements published with the website (`website/public/releases.json`).
/// The apps bundle a copy too, so "What's New" works offline right after an update.
public struct ReleaseFeed: Codable, Sendable, Equatable {
    public static let address = URL(string: "https://yingxia.getmegaportal.com/releases.json")!
    public var releases: [Release]
    /// The build TestFlight testers can install now, keyed by `ReleaseFeed.platform`. Every TestFlight build is
    /// called 1.7.7 and carries the build number of the release it was made from, so builds are what compare;
    /// a build is only listed once it is live on the public link, which can be days after the release.
    public var testflight: [String: TestFlight]?
    public init(releases: [Release], testflight: [String: TestFlight]? = nil) { self.releases = releases; self.testflight = testflight }

    public struct Release: Codable, Sendable, Equatable, Identifiable {
        public var version: String
        /// The release's build number (CFBundleVersion), which its TestFlight build shares.
        public var build: Int?
        /// ISO date, e.g. "2026-10-09".
        public var date: String?
        /// Where to get this release, keyed by `ReleaseFeed.platform`, plus `ReleaseFeed.intelMacKey` for the Intel
        /// Mac package. A platform without a link did not get this release, so its users are not told about it.
        public var links: [String: URL]
        public var features: [Feature]
        public var id: String { version }
        public init(version: String, build: Int? = nil, date: String? = nil, links: [String: URL], features: [Feature]) {
            self.version = version; self.build = build; self.date = date; self.links = links; self.features = features
        }
        /// Intel Macs get their own package; the `macos` link is the Apple silicon one.
        public func link(for platform: String = ReleaseFeed.platform, intelMac: Bool = ReleaseFeed.isIntelMac) -> URL? {
            links[platform == "macos" && intelMac ? ReleaseFeed.intelMacKey : platform]
        }
        /// The features that apply to `platform`.
        public func features(for platform: String = ReleaseFeed.platform) -> [Feature] {
            features.filter { $0.platforms?.contains(platform) ?? true }
        }
    }

    public struct Feature: Codable, Sendable, Hashable {
        /// SF Symbol name.
        public var symbol: String
        public var title: LocalizedText
        public var detail: LocalizedText
        /// Limits the feature to some platforms; nil means every platform.
        public var platforms: [String]?
        public init(symbol: String, title: LocalizedText, detail: LocalizedText, platforms: [String]? = nil) {
            self.symbol = symbol; self.title = title; self.detail = detail; self.platforms = platforms
        }
    }

    public struct TestFlight: Codable, Sendable, Equatable {
        public var build: Int
        /// The public link, which opens the app's page in the TestFlight app.
        public var link: URL?
        public init(build: Int, link: URL? = nil) { self.build = build; self.link = link }
    }

    public static var platform: String {
        #if os(macOS)
        "macos"
        #elseif os(tvOS)
        "tvos"
        #else
        "ios"
        #endif
    }

    /// The Mac's Sparkle appcast, published with the website by Scripts/make-appcast.sh. One per package:
    /// a feed's entry has a single download, so Apple silicon and Intel Macs read different files.
    public static var appcastAddress: URL { appcastAddress(intelMac: isIntelMac) }
    public static func appcastAddress(intelMac: Bool) -> URL {
        URL(string: "https://yingxia.getmegaportal.com/appcast/macos-\(intelMac ? "x86_64" : "arm64").xml")!
    }

    /// The key of the Intel Mac package in `Release.links` (from 1.7.3 on).
    public static let intelMacKey = "macos-x86_64"

    public static var isIntelMac: Bool {
        #if os(macOS) && arch(x86_64)
        true
        #else
        false
        #endif
    }

    /// Releases for `platform` newer than `version`, newest first.
    public func updates(after version: String, platform: String = ReleaseFeed.platform, intelMac: Bool = ReleaseFeed.isIntelMac) -> [Release] {
        let current = AppVersion(version)
        return newestFirst.filter { AppVersion($0.version) > current && $0.link(for: platform, intelMac: intelMac) != nil }
    }

    /// Resolution of an update check, separating upstream release availability from whether the current OS can install the upstream package directly.
    public struct UpdateResolution: Equatable, Sendable {
        public let latest: Release?
        public let isLatestVersion: Bool
        public let directDownloadURL: URL?
        public let compatibilityGuidance: String?

        public init(latest: Release?, isLatestVersion: Bool, directDownloadURL: URL?, compatibilityGuidance: String?) {
            self.latest = latest
            self.isLatestVersion = isLatestVersion
            self.directDownloadURL = directDownloadURL
            self.compatibilityGuidance = compatibilityGuidance
        }
    }

    public func resolveUpdate(
        after current: String,
        platform: String = ReleaseFeed.platform,
        intelMac: Bool = ReleaseFeed.isIntelMac,
        requiresCompatibleBuild: Bool = false
    ) -> UpdateResolution {
        let newer = updates(after: current, platform: platform, intelMac: intelMac)
        guard let latest = newer.first else {
            return UpdateResolution(latest: nil, isLatestVersion: true, directDownloadURL: nil, compatibilityGuidance: nil)
        }
        if requiresCompatibleBuild {
            let guidance = L10n.text(
                "Yingxia %@ is available upstream. iOS 16 requires a verified iOS 16-compatible build rather than the default iOS 17+ release package.",
                latest.version
            )
            return UpdateResolution(
                latest: latest,
                isLatestVersion: false,
                directDownloadURL: nil,
                compatibilityGuidance: guidance
            )
        }
        return UpdateResolution(
            latest: latest,
            isLatestVersion: false,
            directDownloadURL: latest.link(for: platform, intelMac: intelMac),
            compatibilityGuidance: nil
        )
    }

    /// The releases someone skipped over when updating from `previous` to `current`, newest first.
    /// Without a previous version only the current release counts.
    public func whatsNew(since previous: String?, current: String, platform: String = ReleaseFeed.platform) -> [Release] {
        let now = AppVersion(current)
        return newestFirst.filter { release in
            let version = AppVersion(release.version)
            let skipped = previous.map { version > AppVersion($0) && version <= now } ?? (version == now)
            return skipped && !release.features(for: platform).isEmpty
        }
    }

    /// For a TestFlight build: the releases after `build` up to the build live in TestFlight, newest first.
    public func testFlightUpdates(after build: Int, platform: String = ReleaseFeed.platform) -> [Release] {
        guard let live = testflight?[platform]?.build, live > build else { return [] }
        return newestFirst.filter { release in
            release.build.map { $0 > build && $0 <= live } == true && release.link(for: platform) != nil
        }
    }

    /// For a TestFlight build: the releases someone skipped when updating from build `previous` to `current`,
    /// newest first. Without a previous build only the current build's release counts.
    public func testFlightWhatsNew(since previous: Int?, current: Int, platform: String = ReleaseFeed.platform) -> [Release] {
        newestFirst.filter { release in
            guard let build = release.build else { return false }
            let skipped = previous.map { build > $0 && build <= current } ?? (build == current)
            return skipped && !release.features(for: platform).isEmpty
        }
    }

    /// Entries from `newer` replace same-version entries here; the rest are kept.
    public func merged(with newer: ReleaseFeed) -> ReleaseFeed {
        let replaced = Set(newer.releases.map { AppVersion($0.version) })
        return ReleaseFeed(releases: newer.releases + releases.filter { !replaced.contains(AppVersion($0.version)) },
                           testflight: newer.testflight ?? testflight)
    }

    private var newestFirst: [Release] { releases.sorted { AppVersion($0.version) > AppVersion($1.version) } }

    public static func fetch(_ url: URL = address, session: URLSession = .shared) async throws -> ReleaseFeed {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw TVError.http(http.statusCode) }
        return try JSONDecoder().decode(ReleaseFeed.self, from: data)
    }
}

/// Text in several languages, keyed by the app's localization names ("en", "zh-Hans", ...).
/// A plain string in the feed counts as English.
public struct LocalizedText: Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public var values: [String: String]
    public init(_ values: [String: String]) { self.values = values }
    public init(stringLiteral value: String) { values = ["en": value] }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) { values = ["en": text] }
        else { values = try container.decode([String: String].self) }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
    /// The text in the app's current language, else English.
    public func text(language: String? = nil) -> String {
        values[L10n.resolvedLanguage(language)] ?? values["en"] ?? values.values.first ?? ""
    }
}

/// A dotted version number; missing parts count as zero, so 1.1 == 1.1.0.
public struct AppVersion: Comparable, Hashable, Sendable {
    public let parts: [Int]
    public init(_ text: String) {
        var parts = text.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        while parts.count > 1, parts.last == 0 { parts.removeLast() }
        self.parts = parts
    }
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
