import CryptoKit
import Foundation
import Security

public struct RelayIdentity: Sendable {
    private let signing: Curve25519.Signing.PrivateKey
    private let encryption: Curve25519.KeyAgreement.PrivateKey
    public init() { signing = .init(); encryption = .init() }
    public init(privateRepresentation: Data) throws {
        guard privateRepresentation.count == 64 else { throw RemoteError.invalidConfiguration }
        signing = try .init(rawRepresentation: privateRepresentation.prefix(32))
        encryption = try .init(rawRepresentation: privateRepresentation.suffix(32))
    }
    public var privateRepresentation: Data { signing.rawRepresentation + encryption.rawRepresentation }
    public var peer: RelayPeer {
        .init(id: Self.digest(signing.publicKey.rawRepresentation),
              signingKey: signing.publicKey.rawRepresentation.hex, encryptionKey: encryption.publicKey.rawRepresentation.hex)
    }
    public var journalKey: SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: .init(data: privateRepresentation),
                              salt: Data(), info: Data("GATTO-JOURNAL/1".utf8), outputByteCount: 32)
    }
    public static func digest(_ data: Data) -> String { Data(SHA256.hash(data: data)).hex }
    public static func randomToken() -> String {
        Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    public static func validate(peer: RelayPeer) throws {
        guard let signing = Data(hex: peer.signingKey), signing.count == 32,
              let encryption = Data(hex: peer.encryptionKey), encryption.count == 32,
              peer.id == digest(signing) else { throw RemoteError.identityMismatch }
    }
    public func headers(method: String, path: String, body: Data, time: Int64 = relayMilliseconds(),
                        nonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()) throws -> [String: String] {
        let input = ["GATTO/1", method, path, peer.signingKey, String(time), nonce, Self.digest(body), ""].joined(separator: "\n")
        return ["X-Gatto-Key": peer.signingKey, "X-Gatto-Time": String(time), "X-Gatto-Nonce": nonce,
                "X-Gatto-Signature": try signing.signature(for: Data(input.utf8)).hex]
    }
    private func key(peer: RelayPeer, envelope: RelayEnvelope) throws -> SymmetricKey {
        try Self.validate(peer: peer)
        guard let bytes = Data(hex: peer.encryptionKey) else { throw RemoteError.identityMismatch }
        let shared = try encryption.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: bytes))
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(envelope.pairingId.utf8),
            sharedInfo: Data("GATTO-KEY/1\n\(envelope.senderId)\n\(envelope.recipientId)\n".utf8), outputByteCount: 32)
    }
    public func seal(_ data: Data, to other: RelayPeer, pairingId: String, repositoryId: String,
                     expiresAt: Int64 = relayMilliseconds() + 300_000) throws -> RelayEnvelope {
        guard data.count <= 60_000 else { throw RemoteError.capacity }
        var envelope = RelayEnvelope(version: 1, id: UUID().uuidString.lowercased(), pairingId: pairingId,
            senderId: peer.id, recipientId: other.id, repositoryId: repositoryId, expiresAt: expiresAt, sealed: "")
        let box = try AES.GCM.seal(data, using: key(peer: other, envelope: envelope), authenticating: envelope.aad)
        guard let bytes = box.combined else { throw RemoteError.invalidMessage }
        envelope.sealed = bytes.base64EncodedString()
        return envelope
    }
    public func open(_ envelope: RelayEnvelope, from other: RelayPeer, now: Int64 = relayMilliseconds()) throws -> Data {
        guard envelope.version == 1, envelope.recipientId == peer.id, envelope.senderId == other.id,
              envelope.expiresAt > now, envelope.expiresAt <= now + 600_000,
              UUID(uuidString: envelope.id) != nil, UUID(uuidString: envelope.pairingId) != nil,
              let bytes = Data(base64Encoded: envelope.sealed), bytes.count <= 65_536 else { throw RemoteError.invalidMessage }
        return try AES.GCM.open(.init(combined: bytes), using: key(peer: other, envelope: envelope), authenticating: envelope.aad)
    }
    public static func pairingFingerprint(id: String, host: RelayPeer, mobile: RelayPeer) -> String {
        digest(Data(["GATTO-PAIR/1", id, host.signingKey, host.encryptionKey,
                     mobile.signingKey, mobile.encryptionKey, ""].joined(separator: "\n").utf8))
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    init?(hex: String) {
        guard hex.count % 2 == 0, hex.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil else { return nil }
        var bytes: [UInt8] = []; var cursor = hex.startIndex
        while cursor < hex.endIndex {
            let next = hex.index(cursor, offsetBy: 2)
            guard let value = UInt8(hex[cursor..<next], radix: 16) else { return nil }
            bytes.append(value); cursor = next
        }
        self.init(bytes)
    }
}

public enum RelayKeychain {
    public static func loadOrCreate(account: String, create: Bool) throws -> RelayIdentity {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.gitgatto.remote.identity", kSecAttrAccount as String: account,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        var read = query; read[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return try RelayIdentity(privateRepresentation: data) }
        guard status == errSecItemNotFound, create else { throw RemoteError.storage }
        let identity = RelayIdentity()
        var insertion = query; insertion[kSecUseAuthenticationUI as String] = nil
        insertion[kSecValueData as String] = identity.privateRepresentation
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(insertion as CFDictionary, nil)
        if added == errSecDuplicateItem { return try loadOrCreate(account: account, create: false) }
        guard added == errSecSuccess else { throw RemoteError.storage }
        return identity
    }
}
