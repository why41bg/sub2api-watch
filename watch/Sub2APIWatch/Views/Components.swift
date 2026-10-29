import SwiftUI

enum WatchStyle {
    static let green = Color(red: 0.72, green: 0.96, blue: 0.49)
    static let blue = Color(red: 0.51, green: 0.74, blue: 1)
    static let orange = Color(red: 1, green: 0.71, blue: 0.42)
    static let card = Color(red: 0.105, green: 0.11, blue: 0.12)
}

struct WatchPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(.horizontal, 4)
                .padding(.bottom, 16)
        }
        .background(Color.black)
    }
}

struct WatchCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(WatchStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct TokenNumber: View {
    let value: Int64

    var body: some View {
        let formatted = WatchFormat.compact(value)
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(formatted.number).font(.system(size: 36, weight: .semibold, design: .rounded))
            Text(formatted.unit).font(.system(size: 16, weight: .medium))
        }
        .foregroundStyle(WatchStyle.green)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value.formatted()) token")
    }
}

struct MenuRow: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    var selected = false

    var body: some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).foregroundStyle(WatchStyle.green) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(3)
                if let subtitle { Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: selected ? "checkmark" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? WatchStyle.green : Color.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(selected ? WatchStyle.green.opacity(0.12) : WatchStyle.card,
                    in: RoundedRectangle(cornerRadius: 16))
    }
}

struct Notice: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 11))
            .foregroundStyle(WatchStyle.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(WatchStyle.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct UpdatedFooter: View {
    let timestamp: String?
    var cached = false

    var body: some View {
        VStack(spacing: 3) {
            if cached { Text("显示上次数据").foregroundStyle(WatchStyle.orange) }
            if let date = WatchFormat.timestamp(timestamp) {
                Text("更新于 \(date.formatted(.dateTime.month().day().hour().minute()))")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

@MainActor
struct RefreshButton: View {
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        Button { Task { await store.refresh() } } label: {
            Group {
                if store.isRefreshing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .tint(WatchStyle.green)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WatchStyle.green)
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(store.isRefreshing || !store.isConfigured)
        .accessibilityLabel(store.isRefreshing ? "正在刷新" : "刷新数据")
    }
}

struct QuotaPair: View {
    let account: PoolAccount

    var body: some View {
        HStack(spacing: 14) {
            window("5 小时剩余", quota: account.fiveHour, color: WatchStyle.green)
            window("7 天剩余", quota: account.sevenDay, color: WatchStyle.blue)
        }
    }

    private func window(_ title: String, quota: QuotaWindow, color: Color) -> some View {
        let tint = (quota.percent ?? 100) <= 20 ? WatchStyle.orange : color
        return VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(quota.percent.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(tint).minimumScaleFactor(0.6).lineLimit(1)
            GeometryReader { geometry in
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(tint).frame(width: geometry.size.width * (quota.percent ?? 0) / 100)
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(quota.percent.map { String(format: "%.0f%%", $0) } ?? "未知")")
    }
}
