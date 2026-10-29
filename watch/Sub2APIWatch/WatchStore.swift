import Foundation
import Combine

private func attempt<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await operation()) }
    catch { return .failure(error) }
}

@MainActor
final class WatchStore: ObservableObject {
    @Published private(set) var serverAddress = ""
    @Published private(set) var isConfigured = false
    @Published private(set) var scope = UsageScope()
    @Published private(set) var accounts: [PoolAccount] = []
    @Published private(set) var accountsFetchedAt: String?
    @Published private(set) var usage: DailyUsage?
    @Published private(set) var users: [WatchUser] = []
    @Published private(set) var userKeys: [Int: [WatchKey]] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var accountsError: String?
    @Published private(set) var usageError: String?
    @Published private(set) var storageError: String?
    @Published private(set) var restoredCache = false

    private var accessKey = ""
    private var revision = UUID()
    private var refreshTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    private struct Snapshot: Codable {
        let serverAddress: String
        let scope: UsageScope
        let accounts: [PoolAccount]
        let accountsFetchedAt: String?
        let usage: DailyUsage?
    }

    init() {
        serverAddress = defaults.string(forKey: "serverAddress") ?? ""
        do { accessKey = try Keychain.read() }
        catch { storageError = error.localizedDescription }
        isConfigured = !accessKey.isEmpty && (try? APIClient.address(serverAddress)) != nil
        if let data = defaults.data(forKey: "snapshot"),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data),
           saved.serverAddress == serverAddress {
            scope = saved.scope
            accounts = saved.accounts
            accountsFetchedAt = saved.accountsFetchedAt
            if saved.usage?.userId == scope.userID && saved.usage?.apiKeyId == scope.keyID {
                usage = saved.usage
            }
            restoredCache = true
        }
    }

    private func client() throws -> APIClient {
        guard isConfigured else { throw BridgeError.configuration }
        return try APIClient(baseURL: APIClient.address(serverAddress), key: accessKey)
    }

    func configure(address: String, key: String) throws {
        let url = try APIClient.address(address)
        let normalized = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let changedServer = normalized != serverAddress
        let enteredKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let newKey = enteredKey.isEmpty && !changedServer ? accessKey : enteredKey
        guard !newKey.isEmpty else { throw BridgeError.keyRequired }
        try Keychain.save(newKey)
        invalidateRefresh()
        if changedServer || newKey != accessKey {
            accounts = []; accountsFetchedAt = nil; usage = nil
            users = []; userKeys = [:]; restoredCache = false
        }
        if changedServer { scope = UsageScope() }
        accessKey = newKey
        serverAddress = normalized
        isConfigured = true
        storageError = nil; accountsError = nil; usageError = nil
        defaults.set(serverAddress, forKey: "serverAddress")
        persist()
    }

    func select(user: WatchUser?, key: WatchKey? = nil) {
        invalidateRefresh()
        scope = UsageScope(userID: user?.id, email: user?.email,
                           keyID: user == nil ? nil : key?.id, keyName: user == nil ? nil : key?.name)
        usage = nil; usageError = nil
        persist()
    }

    private func invalidateRefresh() {
        revision = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }

    func refresh() async {
        guard let client = try? client() else { return }
        if let refreshTask { await refreshTask.value; return }
        let current = revision
        let selected = scope
        isRefreshing = true
        let task = Task {
            async let accountResult = attempt { try await client.accounts() }
            async let usageResult = attempt { try await client.today(scope: selected) }
            let results = await (accountResult, usageResult)
            guard !Task.isCancelled, current == self.revision else { return }
            switch results.0 {
            case .success(let response):
                self.accounts = response.accounts
                self.accountsFetchedAt = response.fetchedAt
                self.accountsError = nil
                self.restoredCache = false
            case .failure(let error): self.accountsError = error.localizedDescription
            }
            switch results.1 {
            case .success(let usage): self.usage = usage; self.usageError = nil
            case .failure(let error): self.usageError = error.localizedDescription
            }
            self.persist()
        }
        refreshTask = task
        await task.value
        if current == revision { isRefreshing = false; refreshTask = nil }
    }

    func loadUsers() async throws {
        let current = revision
        let response = try await client().users()
        guard current == revision, !Task.isCancelled else { throw CancellationError() }
        users = response
    }

    func loadKeys(for user: WatchUser) async throws {
        let current = revision
        let response = try await client().keys(userID: user.id)
        guard current == revision, !Task.isCancelled else { throw CancellationError() }
        userKeys[user.id] = response
    }

    private func persist() {
        let snapshot = Snapshot(serverAddress: serverAddress, scope: scope, accounts: accounts,
                                accountsFetchedAt: accountsFetchedAt, usage: usage)
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: "snapshot") }
    }
}
