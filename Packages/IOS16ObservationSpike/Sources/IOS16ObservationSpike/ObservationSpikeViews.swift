import Perception
import SwiftUI

public struct SpikeLazySiteRowView: View {
    @AppBindable var site: SpikeSiteRowModel

    public init(site: SpikeSiteRowModel) {
        self.site = site
    }

    public var body: some View {
        WithPerceptionTracking {
            HStack {
                Text(site.title)
                Spacer()
                if let latency = site.latencyMs {
                    Text("\(latency) ms")
                }
                Toggle("收藏", isOn: $site.isFavorite)
            }
        }
    }
}

public struct SpikeSubscriptionView: View {
    @Environment(SpikeSubscriptionStore.self) private var store

    public init() {}

    public var body: some View {
        WithPerceptionTracking {
            SpikeSubscriptionContentView(store: store)
        }
    }
}

struct SpikeSubscriptionContentView: View {
    @AppBindable var store: SpikeSubscriptionStore
    @AppBindable var filter: SpikeNestedFilter

    init(store: SpikeSubscriptionStore) {
        self.store = store
        self.filter = store.filter
    }

    var body: some View {
        WithPerceptionTracking {
            VStack {
                TextField("搜索关键字", text: $store.searchQuery)
                Toggle("包含限制级", isOn: $filter.includeAdult)
                Text("当前分类: \(store.filter.selectedCategory)")
                List {
                    ForEach(store.sites) { site in
                        SpikeLazySiteRowView(site: site)
                    }
                }
            }
        }
    }
}

public struct SpikePlaybackContainerView: View {
    @AppBindable var session: SpikePlaybackSession

    public init(session: SpikePlaybackSession) {
        self.session = session
    }

    public var body: some View {
        WithPerceptionTracking {
            VStack {
                Text(session.isPlaying ? "播放中" : "已暂停")
                Text("进度: \(Int(session.positionSeconds)) / \(Int(session.durationSeconds))")
                Button("切换弹层") {
                    session.isPresentingDetailSheet.toggle()
                }
            }
            .onAppear {
                session.loadIfNeeded(url: "https://example.invalid/video.mp4")
            }
            .sheet(isPresented: $session.isPresentingDetailSheet) {
                WithPerceptionTracking {
                    VStack {
                        Text("弹层内进度: \(Int(session.positionSeconds))")
                        Button(session.isPlaying ? "暂停" : "继续") {
                            session.togglePlayPause()
                        }
                    }
                }
            }
        }
    }
}
