import Foundation
import Perception
import SwiftUI

// MARK: - 1. 订阅与搜索结构对应的最小可观察模型 (对应 Task 3.3)

@Perceptible
@MainActor
public final class SpikeNestedFilter {
    public var selectedCategory: String = "全部"
    public var includeAdult: Bool = false
    public init() {}
}

@Perceptible
@MainActor
public final class SpikeSiteRowModel: Identifiable {
    public let id: String
    public var title: String
    public var latencyMs: Int?
    public var isFavorite: Bool

    public init(id: String, title: String, latencyMs: Int? = nil, isFavorite: Bool = false) {
        self.id = id
        self.title = title
        self.latencyMs = latencyMs
        self.isFavorite = isFavorite
    }
}

public protocol SpikeSubscriptionServiceStub: Sendable {
    func search(query: String, category: String) async -> [String]
}

public struct ControlledSubscriptionServiceStub: SpikeSubscriptionServiceStub {
    public init() {}
    public func search(query: String, category: String) async -> [String] {
        try? await Task.sleep(nanoseconds: 10_000_000)
        guard !query.isEmpty else { return [] }
        return ["\(category):\(query)-结果1", "\(category):\(query)-结果2"]
    }
}

@Perceptible
@MainActor
public final class SpikeSubscriptionStore {
    public var subscriptionURL: String = "https://example.invalid/sub.json"
    public var searchQuery: String = ""
    public var isSearching: Bool = false
    public var searchResults: [String] = []
    public var sites: [SpikeSiteRowModel] = [
        SpikeSiteRowModel(id: "site-1", title: "测试源 A"),
        SpikeSiteRowModel(id: "site-2", title: "测试源 B")
    ]
    public var filter: SpikeNestedFilter = SpikeNestedFilter()

    @PerceptionIgnored
    private let service: any SpikeSubscriptionServiceStub

    public init(service: any SpikeSubscriptionServiceStub = ControlledSubscriptionServiceStub()) {
        self.service = service
    }

    public func performAsyncSearch() async {
        isSearching = true
        let q = searchQuery
        let cat = filter.selectedCategory
        let items = await service.search(query: q, category: cat)
        searchResults = items
        isSearching = false
    }
}

// MARK: - 2. 播放会话与手动追踪对应的最小可观察模型 (对应 Task 3.4)

@Perceptible
@MainActor
public final class SpikePlaybackSession {
    public private(set) var activeMediaURL: String?
    public var isPlaying: Bool = false
    public var positionSeconds: Double = 0
    public var durationSeconds: Double = 120
    public var isPresentingDetailSheet: Bool = false
    public private(set) var startTaskCount: Int = 0

    @PerceptionIgnored
    public var internalPlayerToken: UUID = UUID()

    public init() {}

    /// 模拟开始播放会话：若同一媒体已在播放会话中，页面重建或弹层切换不应重复启动底层加载任务
    public func loadIfNeeded(url: String) {
        guard activeMediaURL != url else { return }
        activeMediaURL = url
        startTaskCount += 1
        isPlaying = true
        positionSeconds = 0
    }

    public func togglePlayPause() {
        isPlaying.toggle()
    }

    public func seek(to seconds: Double) {
        positionSeconds = min(max(0, seconds), durationSeconds)
    }
}

/// 对应 App/MusicRemoteControl.swift 中使用 withObservationTracking 持续监听播放状态变化的手动追踪器
@MainActor
public final class SpikeRemoteObserver {
    public private(set) var observedSnapshots: [String] = []
    private weak var session: SpikePlaybackSession?
    private var isObserving = false

    public init(session: SpikePlaybackSession) {
        self.session = session
    }

    public func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        observeLoop()
    }

    public func stopObserving() {
        isObserving = false
    }

    private func observeLoop() {
        guard isObserving, let session else { return }
        withPerceptionTracking {
            let state = "\(session.isPlaying ? "play" : "pause")@\(Int(session.positionSeconds))"
            observedSnapshots.append(state)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeLoop()
            }
        }
    }
}

// MARK: - 3. 跨平台 (iOS 16+ / macOS 14+ / tvOS 17+) Bindable 统一类型别名

#if os(iOS)
public typealias AppBindable<Value: AnyObject & Perceptible> = Perception.Bindable<Value>
#else
public typealias AppBindable<Value: AnyObject & Observable> = SwiftUI.Bindable<Value>
#endif
