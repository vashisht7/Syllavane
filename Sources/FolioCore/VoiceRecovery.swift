import Foundation

public struct VoiceRecoverySnapshot: Codable, Sendable {
    public let projectID: UUID
    public let sceneID: UUID
    public let revision: Bool
    public let transcript: String
    public let wav: Data
    public init(projectID: UUID, sceneID: UUID, revision: Bool, transcript: String, wav: Data) {
        self.projectID = projectID; self.sceneID = sceneID; self.revision = revision; self.transcript = transcript; self.wav = wav
    }
}
/// A serial queue and atomic replacement keep audio and its destination together.
public final class VoiceRecoveryStore: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "studio.folio.voice-recovery", qos: .utility)
    public init(directory: URL) { url = directory.appendingPathComponent("interrupted-voice.plist") }
    public func checkpoint(_ snapshot: VoiceRecoverySnapshot) {
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
                try encoder.encode(snapshot).write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { /* The recognized transcript is independently saved in preferences. */ }
        }
    }
    public func read() -> VoiceRecoverySnapshot? {
        queue.sync {
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 50_000_000,
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? PropertyListDecoder().decode(VoiceRecoverySnapshot.self, from: data)
        }
    }
    public func drain() { queue.sync {} }
    public func clear() { queue.sync { try? FileManager.default.removeItem(at: url) } }
}
