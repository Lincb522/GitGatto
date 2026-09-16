import Foundation

public enum RemoteError: Error, Sendable, Equatable {
    case invalidConfiguration, invalidMessage, identityMismatch, unauthorized, expired, capacity
    case interrupted, unsupported, storage, transport(Int, String)
}
public struct RelayPeer: Codable, Sendable, Equatable {
    public var id: String
    public var signingKey: String
    public var encryptionKey: String
    public init(id: String, signingKey: String, encryptionKey: String) {
        self.id = id; self.signingKey = signingKey; self.encryptionKey = encryptionKey
    }
}
public struct RelayPairing: Codable, Sendable {
    public var id: String
    public var hostId: String
    public var mobileId: String?
    public var state: String
    public var expiresAt: Int64
    public var repositories: [String]
    public var host: RelayPeer
    public var mobile: RelayPeer?
}
public struct RelayInvitation: Codable, Sendable {
    public var id: String
    public var token: String
    public var encryptionKey: String
    public init(identity: RelayIdentity) {
        id = UUID().uuidString.lowercased(); token = RelayIdentity.randomToken(); encryptionKey = identity.peer.encryptionKey
    }
}
public struct RelayEnvelope: Codable, Sendable, Equatable {
    public var version: Int
    public var id: String
    public var pairingId: String
    public var senderId: String
    public var recipientId: String
    public var repositoryId: String
    public var expiresAt: Int64
    public var sealed: String
    public var aad: Data {
        Data(["GATTO-BOX/1", id, pairingId, senderId, recipientId, repositoryId, String(expiresAt), ""].joined(separator: "\n").utf8)
    }
}
public struct RemoteRepository: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var path: String
    public init(id: String, name: String, path: String) { self.id = id; self.name = name; self.path = path }
}
public struct RemoteGrant: Codable, Sendable, Equatable {
    public var pairingId: String
    public var mobile: RelayPeer
    public var repositories: [RemoteRepository]
    public var allowsAgentAnalysis: Bool
    public var allowsAgentEdits: Bool
    public init(pairingId: String, mobile: RelayPeer, repositories: [RemoteRepository],
                allowsAgentAnalysis: Bool = false, allowsAgentEdits: Bool = false) {
        self.pairingId = pairingId; self.mobile = mobile; self.repositories = repositories
        self.allowsAgentAnalysis = allowsAgentAnalysis; self.allowsAgentEdits = allowsAgentEdits
    }
}
public enum RemoteCommandKind: String, Codable, Sendable, CaseIterable {
    case capabilities, repositories = "repositories.list", status = "repository.status"
    case diff = "repository.diff", backups = "backup.list", analyze = "agent.analyze", edit = "agent.edit"
    case taskStatus = "task.status", cancel = "task.cancel"
}
public struct RemoteCommand: Codable, Sendable {
    public var id: String
    public var kind: RemoteCommandKind
    public var prompt: String?
    public var expectedHead: String?
    public var targetTaskID: String?
    public init(id: String = UUID().uuidString.lowercased(), kind: RemoteCommandKind,
                prompt: String? = nil, expectedHead: String? = nil, targetTaskID: String? = nil) {
        self.id = id; self.kind = kind; self.prompt = prompt; self.expectedHead = expectedHead; self.targetTaskID = targetTaskID
    }
}
public struct RemoteReply: Codable, Sendable, Equatable {
    public var taskId: String
    public var state: String
    public var text: String
    public var fields: [String: String]
    public init(taskId: String, state: String, text: String = "", fields: [String: String] = [:]) {
        self.taskId = taskId; self.state = state; self.text = text; self.fields = fields
    }
}
public protocol RemoteCommandExecuting: Sendable {
    func execute(_ command: RemoteCommand, repository: RemoteRepository,
                 progress: @escaping @Sendable (String) async -> Void) async throws -> RemoteReply
}
public struct RemoteConnectionConfiguration: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var serverURL: URL
    public var grants: [RemoteGrant]
    public init(enabled: Bool, serverURL: URL, grants: [RemoteGrant]) {
        self.enabled = enabled; self.serverURL = serverURL; self.grants = grants
    }
    public func validate() throws {
        guard serverURL.scheme == "https", serverURL.host != nil, serverURL.user == nil,
              serverURL.password == nil, serverURL.query == nil, serverURL.fragment == nil,
              serverURL.path.isEmpty || serverURL.path == "/", grants.count <= 20,
              Set(grants.map(\.pairingId)).count == grants.count else { throw RemoteError.invalidConfiguration }
        for grant in grants {
            guard UUID(uuidString: grant.pairingId) != nil,
                  (1...100).contains(grant.repositories.count),
                  Set(grant.repositories.map(\.id)).count == grant.repositories.count else { throw RemoteError.invalidConfiguration }
            try RelayIdentity.validate(peer: grant.mobile)
            for repository in grant.repositories {
                guard repository.id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil,
                      repository.path.hasPrefix("/"), !repository.name.isEmpty else { throw RemoteError.invalidConfiguration }
            }
        }
    }
}
public func relayMilliseconds(_ date: Date = Date()) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }
