import SwiftUI
import Testing
@testable import IOS16ObservationSpike
import Perception

@MainActor
@Suite("iOS 16 Observation (swift-perception) 小范围验证套件")
struct ObservationSpikeTests {

    @Test("Task 3.3: 验证异步搜索更新、嵌套对象变化、双向绑定与延迟列表行模型观察")
    func subscriptionAndNestedObservation() async {
        let store = SpikeSubscriptionStore()
        var queryObservedChanges = 0

        withPerceptionTracking {
            _ = store.searchQuery
        } onChange: {
            Task { @MainActor in queryObservedChanges += 1 }
        }

        // 1. 验证双向绑定 (@AppBindable) 修改属性
        let bindableStore = AppBindable(store)
        bindableStore.searchQuery.wrappedValue = "漫长的季节"
        await Task.yield()
        #expect(store.searchQuery == "漫长的季节")
        #expect(queryObservedChanges == 1)

        // 2. 验证嵌套模型 (SpikeNestedFilter) 属性变化能被外层追踪捕获
        var nestedObservedChanges = 0
        withPerceptionTracking {
            _ = store.filter.selectedCategory
        } onChange: {
            Task { @MainActor in nestedObservedChanges += 1 }
        }
        store.filter.selectedCategory = "电视剧"
        await Task.yield()
        #expect(nestedObservedChanges == 1)

        // 3. 验证异步搜索结果刷新
        await store.performAsyncSearch()
        #expect(!store.isSearching)
        #expect(store.searchResults == ["电视剧:漫长的季节-结果1", "电视剧:漫长的季节-结果2"])

        // 4. 验证列表行独立可观察对象刷新 (延迟创建的列表行模型)
        let firstRow = store.sites[0]
        var rowObservedChanges = 0
        withPerceptionTracking {
            _ = firstRow.latencyMs
            _ = firstRow.isFavorite
        } onChange: {
            Task { @MainActor in rowObservedChanges += 1 }
        }
        firstRow.latencyMs = 48
        await Task.yield()
        #expect(rowObservedChanges == 1)
    }

    @Test("Task 3.4: 验证播放会话生命周期、页面重建/弹层不重复启动任务、进度更新与手动追踪重建")
    func playbackLifecycleAndManualTracking() async {
        let session = SpikePlaybackSession()
        let observer = SpikeRemoteObserver(session: session)
        observer.startObserving()
        #expect(observer.observedSnapshots == ["pause@0"])

        // 1. 首次进入播放页启动任务
        session.loadIfNeeded(url: "https://example.invalid/live.m3u8")
        #expect(session.startTaskCount == 1)
        await Task.yield()
        #expect(observer.observedSnapshots.last == "play@0")

        // 2. 模拟打开弹层、修改进度、关闭弹层以及视图销毁重建再次调用 loadIfNeeded
        session.isPresentingDetailSheet = true
        session.seek(to: 35)
        await Task.yield()
        #expect(observer.observedSnapshots.last == "play@35")

        session.isPresentingDetailSheet = false
        session.loadIfNeeded(url: "https://example.invalid/live.m3u8")
        // 确认未重复启动底层任务，且播放控制与进度未丢失
        #expect(session.startTaskCount == 1)
        #expect(session.isPlaying == true)
        #expect(session.positionSeconds == 35)

        // 3. 模拟暂停并确认手动追踪器连续捕获变化
        session.togglePlayPause()
        await Task.yield()
        #expect(observer.observedSnapshots.last == "pause@35")
        observer.stopObserving()
    }
}
