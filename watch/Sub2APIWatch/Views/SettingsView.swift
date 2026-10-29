import SwiftUI

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        WatchPage {
            Text("服务地址").font(.caption2).foregroundStyle(.secondary)
            TextField("https://watch.example.com", text: $address)
                .textContentType(.URL)
                .autocorrectionDisabled()
            Text("访问密钥").font(.caption2).foregroundStyle(.secondary)
            SecureField(store.isConfigured ? "留空保持现有密钥" : "输入专用查询密钥", text: $key)
            if let error { Notice(text: error) }
            Button {
                do {
                    try store.configure(address: address, key: key)
                    key = ""
                    dismiss()
                    Task { await store.refresh() }
                } catch { self.error = error.localizedDescription }
            } label: {
                Text("保存配置").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchStyle.green)
            .foregroundStyle(.black)
            .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("填写查询服务的专用密钥。打开应用时自动刷新。")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .navigationTitle("连接设置")
        .onAppear { address = store.serverAddress }
    }
}
