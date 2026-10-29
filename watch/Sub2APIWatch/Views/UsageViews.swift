import SwiftUI

@MainActor
struct UsageView: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        WatchPage {
            if let error = store.usageError { Notice(text: error) }
            NavigationLink(value: Route.users) {
                MenuRow(title: store.scope.title, subtitle: store.scope.subtitle, symbol: "line.3.horizontal.decrease")
            }
            .buttonStyle(.plain)
            if let usage = store.usage {
                if !usage.isToday { Notice(text: "\(usage.date) 的缓存数据，尚未获取今日用量。") }
                WatchCard {
                    Text(usage.isToday ? "今日累计 token" : "缓存 token 用量").font(.system(size: 11)).foregroundStyle(.secondary)
                    TokenNumber(value: usage.tokens.total)
                    Text("\(usage.tokens.total.formatted()) tokens").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                WatchCard {
                    metric("输入", value: usage.tokens.input, color: WatchStyle.blue)
                    Divider()
                    metric("输出", value: usage.tokens.output, color: WatchStyle.green)
                    Divider()
                    metric("缓存读取", value: usage.tokens.cacheRead, color: .purple)
                    Divider()
                    metric("缓存创建", value: usage.tokens.cacheCreation)
                    Divider()
                    metric("请求数", value: usage.requests, compact: false)
                }
                if usage.tokens.total == 0 {
                    Text("这个范围当天还没有用量").font(.caption2).foregroundStyle(.secondary)
                }
                Text(usage.isToday ? "\(usage.timezone == "Asia/Shanghai" ? "北京时间" : usage.timezone) 00:00 至今" : usage.date)
                    .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                UpdatedFooter(timestamp: usage.updatedAt, cached: store.usageError != nil || store.restoredCache)
            } else if store.isRefreshing { ProgressView().frame(maxWidth: .infinity).padding() }
            else { Text("尚未获取用量").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("今日用量")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RefreshButton() } }
    }

    private func metric(_ title: String, value: Int64, color: Color? = nil, compact: Bool = true) -> some View {
        let formatted = WatchFormat.compact(value)
        return HStack(spacing: 5) {
            if let color { Circle().fill(color).frame(width: 5, height: 5) }
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(compact ? formatted.number + formatted.unit : value.formatted()).monospacedDigit()
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(value.formatted())")
    }
}

@MainActor
struct UsersView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var loading = false
    @State private var error: String?
    let finish: () -> Void

    var body: some View {
        WatchPage {
            Text("按绑定邮箱选择").font(.caption2).foregroundStyle(.secondary)
            Button {
                store.select(user: nil)
                finish()
                Task { await store.refresh() }
            } label: {
                MenuRow(title: "全部用户", subtitle: "查看全站今日用量", selected: store.scope.userID == nil)
            }
            .buttonStyle(.plain)
            ForEach(store.users) { user in
                NavigationLink(value: Route.keys(user)) {
                    MenuRow(title: user.email, selected: store.scope.userID == user.id)
                }
                .buttonStyle(.plain)
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if let error {
                Notice(text: error)
                Button("重新加载") { Task { await load() } }.disabled(loading)
            } else if !loading && store.users.isEmpty {
                Text("暂无用户").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("选择用户")
        .task { await load() }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { try await store.loadUsers() }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

@MainActor
struct KeysView: View {
    @EnvironmentObject private var store: WatchStore
    @State private var loading = false
    @State private var error: String?
    let user: WatchUser
    let finish: () -> Void

    var body: some View {
        WatchPage {
            Text(user.email).font(.caption2).foregroundStyle(.secondary)
            Button { choose(nil) } label: {
                MenuRow(title: "全部 Key", subtitle: "该用户的今日合计",
                        selected: store.scope.userID == user.id && store.scope.keyID == nil)
            }
            .buttonStyle(.plain)
            ForEach(store.userKeys[user.id] ?? []) { key in
                Button { choose(key) } label: {
                    MenuRow(title: key.name, selected: store.scope.userID == user.id && store.scope.keyID == key.id)
                }
                .buttonStyle(.plain)
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if let error {
                Notice(text: error)
                Button("重新加载") { Task { await load() } }.disabled(loading)
            } else if !loading && (store.userKeys[user.id] ?? []).isEmpty {
                Text("此用户暂无 Key").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("选择 Key")
        .task { await load() }
    }

    private func choose(_ key: WatchKey?) {
        store.select(user: user, key: key)
        finish()
        Task { await store.refresh() }
    }

    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { try await store.loadKeys(for: user) }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
