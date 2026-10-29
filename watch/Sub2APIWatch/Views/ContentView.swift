import SwiftUI

enum Route: Hashable {
    case accounts, account(Int), usage, users, keys(WatchUser), settings
}

@MainActor
struct ContentView: View {
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            OverviewView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .accounts: AccountsView()
                    case .account(let id): AccountDetailView(accountID: id)
                    case .usage: UsageView()
                    case .users: UsersView { path = [.usage] }
                    case .keys(let user): KeysView(user: user) { path = [.usage] }
                    case .settings: SettingsView()
                    }
                }
        }
    }
}

@MainActor
struct OverviewView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        WatchPage {
            if !store.isConfigured {
                WatchCard {
                    Image(systemName: "waveform.path.ecg").font(.title).foregroundStyle(WatchStyle.green)
                    Text("把用量，戴在手腕上。").font(.headline)
                    Text("连接自己的查询服务，查看窗口额度与今日用量。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = store.storageError { Notice(text: error) }
            } else {
                if let error = store.usageError ?? store.accountsError { Notice(text: error) }
                NavigationLink(value: Route.usage) {
                    WatchCard {
                        Text("今日 token · \(store.scope.title)").font(.system(size: 11)).foregroundStyle(.secondary)
                        if let usage = store.usage {
                            TokenNumber(value: usage.tokens.total)
                            if !usage.isToday { Text("\(usage.date) · 缓存数据").font(.caption2).foregroundStyle(WatchStyle.orange) }
                            Text("\(usage.requests.formatted()) 次请求 · 含缓存用量")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        } else if store.isRefreshing { ProgressView().padding(.vertical, 6) }
                        else { Text("暂无数据").foregroundStyle(.secondary) }
                    }
                }
                .buttonStyle(.plain)
                NavigationLink(value: Route.accounts) {
                    WatchCard {
                        HStack {
                            Text("账号池").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(store.accounts.count) 个账号").font(.system(size: 10)).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        if let account = store.accounts.first {
                            Text(account.name).font(.system(size: 10)).foregroundStyle(.secondary)
                            if account.stale || store.accountsError != nil || store.restoredCache {
                                Text("上次额度快照").font(.system(size: 10)).foregroundStyle(WatchStyle.orange)
                            }
                            QuotaPair(account: account)
                        } else { Text(store.accountsFetchedAt == nil ? "等待获取额度" : "暂无 OpenAI 账号").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                .buttonStyle(.plain)
                NavigationLink(value: Route.users) {
                    MenuRow(title: store.scope.title, subtitle: store.scope.subtitle, symbol: "line.3.horizontal.decrease")
                }
                .buttonStyle(.plain)
            }
            NavigationLink(value: Route.settings) { MenuRow(title: "连接设置", symbol: "slider.horizontal.3") }
                .buttonStyle(.plain)
            if store.isConfigured {
                UpdatedFooter(timestamp: store.usage?.updatedAt, cached: store.usageError != nil || store.restoredCache)
            }
        }
        .navigationTitle("总览")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RefreshButton() } }
    }
}

@MainActor
struct AccountsView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        WatchPage {
            if let error = store.accountsError { Notice(text: error) }
            Text("\(store.accounts.count) 个 OpenAI 账号").font(.caption2).foregroundStyle(.secondary)
            ForEach(store.accounts) { account in
                NavigationLink(value: Route.account(account.id)) {
                    WatchCard {
                        HStack {
                            Text(account.name).font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 3)
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Text(account.stale ? "旧快照" : account.status == "active" ? "正常可用" : "账号状态异常")
                            .font(.system(size: 10)).foregroundStyle(account.stale ? WatchStyle.orange : Color.secondary)
                        QuotaPair(account: account)
                    }
                }
                .buttonStyle(.plain)
            }
            if store.accounts.isEmpty {
                if store.isRefreshing { ProgressView().frame(maxWidth: .infinity) }
                else { Text(store.accountsFetchedAt == nil ? "尚未获取账号数据" : "暂无 OpenAI 账号").font(.footnote).foregroundStyle(.secondary) }
            }
            UpdatedFooter(timestamp: store.accountsFetchedAt, cached: store.accountsError != nil || store.restoredCache)
        }
        .navigationTitle("账号池")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RefreshButton() } }
    }
}

@MainActor
struct AccountDetailView: View {
    @EnvironmentObject private var store: WatchStore
    let accountID: Int

    var body: some View {
        WatchPage {
            if let account = store.accounts.first(where: { $0.id == accountID }) {
                Text(account.name).font(.caption2).foregroundStyle(.secondary)
                if let error = store.accountsError { Notice(text: error) }
                if account.stale { Notice(text: "额度刷新失败，显示上次快照。") }
                WindowCard(title: "5 小时窗口", quota: account.fiveHour, color: WatchStyle.green)
                WindowCard(title: "7 天窗口", quota: account.sevenDay, color: WatchStyle.blue)
                UpdatedFooter(timestamp: account.updatedAt, cached: account.stale || store.accountsError != nil || store.restoredCache)
            } else { Notice(text: "此账号已不在账号池中。") }
        }
        .navigationTitle("账号详情")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RefreshButton() } }
    }
}

private struct WindowCard: View {
    let title: String
    let quota: QuotaWindow
    let color: Color

    var body: some View {
        let tint = (quota.percent ?? 100) <= 20 ? WatchStyle.orange : color
        WatchCard {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 6)
                    Circle().trim(from: 0, to: (quota.percent ?? 0) / 100)
                        .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(quota.percent.map { String(format: "%.0f%%", $0) } ?? "—")
                        .font(.system(size: 18, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6)
                }
                .frame(width: 60, height: 60).padding(3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text("剩余额度").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let reset = WatchFormat.timestamp(quota.resetsAt), reset > context.date {
                    Text("\(reset.formatted(.dateTime.month().day().hour().minute())) 重置")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text("暂无有效重置时间").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
