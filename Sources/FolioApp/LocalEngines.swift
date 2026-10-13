import Foundation
import SwiftUI
import CryptoKit
import FolioCore

struct ModelSpec: Codable, Identifiable {
    let id: String
    let name: String
    let file: String
    let url: String
    let sha256: String
    let bytes: Int64
    let license: String
}

enum AppPaths {
    static let support: URL = {
        if let override = ProcessInfo.processInfo.environment["FOLIO_DATA_DIR"] { return URL(fileURLWithPath: override) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Folio", isDirectory: true)
    }()
    static let models = support.appendingPathComponent("Models", isDirectory: true)
    static let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
}

@MainActor
final class LocalEngines: ObservableObject {
    @Published var status = "Not started"
    @Published var ready = false
    @Published var preparing = false
    @Published var downloadProgress: Double = 0
    @Published var modelStatus: [String: Bool] = [:]
    @Published var error: String?
    // Injectable transports keep workflow tests local and independent of model weights.
    var completionTransport: ((String, String) async throws -> String)?
    var embeddingTransport: ((String) async throws -> [Float])?
    private let modelDirectory: URL
    private let resourceDirectory: URL
    private let runtimeDirectory: URL
    let specs: [ModelSpec]
    private var processes: [Process] = []
    private var logHandles: [FileHandle] = []
    private var writerPort = 0
    private var embeddingPort = 0
    private var speechPort = 0
    private let key = UUID().uuidString
    private var startup: Task<Void, Never>?
    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }
    private let session: URLSession
    init(modelDirectory: URL = AppPaths.models, resourceDirectory: URL = AppPaths.resources, runtimeDirectory: URL = AppPaths.support, session: URLSession? = nil) {
        self.session = session ?? Self.makeSession()
        self.modelDirectory = modelDirectory; self.resourceDirectory = resourceDirectory; self.runtimeDirectory = runtimeDirectory
        specs = (try? JSONDecoder().decode([ModelSpec].self, from: Data(contentsOf: resourceDirectory.appendingPathComponent("models.json")))) ?? []
        refresh()
    }
    func refresh() {
        for spec in specs {
            let path = modelDirectory.appendingPathComponent(spec.file)
            let size = (try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            modelStatus[spec.id] = Int64(size) == spec.bytes
        }
    }
    var totalModelBytes: Int64 { specs.reduce(0) { $0 + $1.bytes } }
    var installed: Bool { specs.count == 3 && specs.allSatisfy { modelStatus[$0.id] == true } }
    func start() {
        guard !preparing && !ready else { return }
        preparing = true
        startup = Task { guard !Task.isCancelled else { self.preparing = false; return }; self.preparing = false; await prepare() }
    }
    func cancelSetup() { startup?.cancel(); stop(); status = "Setup paused" }
    func prepare() async {
        guard !preparing && !ready else { return }
        preparing = true; error = nil
        defer { preparing = false }
        do {
            guard specs.count == 3 else { throw FolioError.message("The app’s local model configuration is missing. Reinstall Syllavane.") }
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            for spec in specs where modelStatus[spec.id] == true {
                try Task.checkCancellation()
                status = "Checking \(spec.name)"
                let file = modelDirectory.appendingPathComponent(spec.file)
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let fingerprint = "\(spec.sha256):\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                let stamp = runtimeDirectory.appendingPathComponent("verified-" + spec.id + ".txt")
                if (try? String(contentsOf: stamp, encoding: .utf8)) != fingerprint {
                    let checksum = try await Task.detached { try Self.checksum(file) }.value
                    try Task.checkCancellation()
                    guard checksum == spec.sha256 else {
                        modelStatus[spec.id] = false
                        throw FolioError.message("The \(spec.name) model failed its integrity check. Run setup again to replace it.")
                    }
                    try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
                    try fingerprint.write(to: stamp, atomically: true, encoding: .utf8)
                }
            }
            for spec in specs where modelStatus[spec.id] != true {
                try Task.checkCancellation()
                status = "Downloading \(spec.name)"; downloadProgress = 0
                let downloader = ModelDownloader()
                let temporary = try await downloader.download(URL(string: spec.url)!) { [weak self] value in
                    Task { @MainActor in self?.downloadProgress = value }
                }
                defer { try? FileManager.default.removeItem(at: temporary) }
                status = "Verifying \(spec.name)"
                let checksum = try await Task.detached { try Self.checksum(temporary) }.value
                guard checksum == spec.sha256 else { throw FolioError.message("The \(spec.name) download did not pass verification. Try setup again.") }
                try Task.checkCancellation()
                let destination = modelDirectory.appendingPathComponent(spec.file)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.moveItem(at: temporary, to: destination)
                refresh()
            }
            try Task.checkCancellation()
            status = "Starting local writing engine"
            writerPort = Int.random(in: 43000...47000)
            embeddingPort = writerPort + 1; speechPort = writerPort + 2
            try launch(engine: "llama", executable: "llama-server", arguments: ["-m", path("writer"), "--host", "127.0.0.1", "--port", "\(writerPort)", "--api-key", key, "-c", "8192", "-ngl", "99", "-t", "4", "--parallel", "1", "--jinja", "--chat-template-kwargs", "{\"enable_thinking\":false}"])
            try await waitFor(port: writerPort)
            status = "Starting semantic memory"
            try launch(engine: "llama", executable: "llama-server", arguments: ["-m", path("embedding"), "--host", "127.0.0.1", "--port", "\(embeddingPort)", "--api-key", key, "--embedding", "--pooling", "mean", "-c", "512", "-b", "512", "-ub", "512", "-ngl", "99", "--parallel", "1"])
            try await waitFor(port: embeddingPort)
            status = "Starting offline dictation"
            try launch(engine: "whisper", executable: "whisper-server", arguments: ["-m", path("speech"), "--host", "127.0.0.1", "--port", "\(speechPort)", "-t", "4", "-l", "en"])
            try await waitFor(port: speechPort, route: "/")
            ready = true; status = "All models on this Mac"
        } catch is CancellationError { stop(); status = "Setup paused" }
        catch { stop(); self.error = error.localizedDescription; status = "Setup needs attention" }
    }
    nonisolated static func checksum(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func path(_ id: String) -> String { modelDirectory.appendingPathComponent(specs.first { $0.id == id }!.file).path }
    private func launch(engine: String, executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = resourceDirectory.appendingPathComponent("Engines/\(engine)/\(executable)")
        guard FileManager.default.isExecutableFile(atPath: process.executableURL!.path) else { throw FolioError.message("A required local engine is missing. Reinstall Syllavane.") }
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["FOLIO_ENGINE_TOKEN"] = key
        process.environment = environment
        let logs = runtimeDirectory.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let file = logs.appendingPathComponent("\(executable)-\(processes.count).log")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        process.standardOutput = handle; process.standardError = handle
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard let self, self.ready, self.processes.contains(where: { $0 === process }) else { return }
                self.ready = false; self.status = "Local engine stopped"; self.error = "A local engine stopped unexpectedly. Restart the engines in Settings."
            }
        }
        try process.run(); processes.append(process); logHandles.append(handle)
    }
    private func waitFor(port: Int, route: String = "/health") async throws {
        for _ in 0..<180 {
            try Task.checkCancellation()
            if processes.contains(where: { !$0.isRunning }) { throw FolioError.message("A local engine could not start. See the engine logs in Settings.") }
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(route)")!)
            request.timeoutInterval = 2; request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            if let (_, response) = try? await session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw FolioError.message("The local model took too long to start. Close other memory-heavy apps and try again.")
    }
    func stop() {
        startup?.cancel(); startup = nil
        ready = false
        for process in processes where process.isRunning { process.terminate() }
        processes.removeAll()
        for handle in logHandles { try? handle.close() }; logHandles.removeAll()
    }
    func complete(system: String, user: String, maxTokens: Int = 1200, jsonSchema: [String: Any]? = nil, temperature: Double? = nil, onToken: @escaping (String) -> Void) async throws -> String {
        guard ready else { throw FolioError.message("Start the local models in Settings first.") }
        if let completionTransport { return try await completionTransport(system, user) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(writerPort)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        var payload: [String: Any] = ["messages": [["role":"system", "content":system], ["role":"user", "content":user]], "stream": true, "cache_prompt": true, "max_tokens":maxTokens, "temperature":temperature ?? (jsonSchema == nil ? 0.3 : 0.1), "repeat_penalty":jsonSchema == nil ? 1.08 : 1.0, "chat_template_kwargs":["enable_thinking":false]]
        if let jsonSchema { payload["response_format"] = ["type":"json_schema", "json_schema":["name":"story_memory", "strict":true, "schema":jsonSchema]] }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FolioError.message("The writing engine could not process this scene. Try a shorter brief.") }
        var stream = GenerationStream()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            try stream.consume(line)
            onToken(PromptBuilder.cleanTranscript(stream.text))
            if stream.done { break }
        }
        return try stream.result()
    }
    func embed(_ text: String) async throws -> [Float] {
        guard ready else { throw FolioError.message("Semantic search is unavailable. Restart the local engines in Settings.") }
        if let embeddingTransport { return try await embeddingTransport(text) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(embeddingPort)/v1/embeddings")!)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["input": String(text.prefix(650)), "model":"local"])
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FolioError.message("Semantic search is temporarily unavailable.") }
        struct Response: Decodable { struct Item: Decodable { let embedding: [Float] }; let data: [Item] }
        let vector = try JSONDecoder().decode(Response.self, from: data).data.first?.embedding ?? []
        guard !vector.isEmpty, vector.allSatisfy({ $0.isFinite }) else { throw FolioError.message("Semantic search returned an invalid result. Restart the local engines.") }
        return vector
    }
    func transcribe(wav: Data, names: [String]) async throws -> String {
        guard ready else { throw FolioError.message("Start the local models before recording.") }
        let boundary = "Folio-" + UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) { body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8)) }
        field("response_format", "json"); field("temperature", "0.0"); field("language", "en")
        field("suppress_non_speech", "true"); field("no_speech_thold", "0.5")
        if !names.isEmpty { field("prompt", "Names: " + names.prefix(30).joined(separator: ", ")) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(speechPort)/inference")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "POST"; request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"); request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FolioError.message("Dictation could not be transcribed. Your recording is still available to retry.") }
        struct Response: Decodable { let text: String }
        return TranscriptFilter.clean(try JSONDecoder().decode(Response.self, from: data).text, removeFillers: UserDefaults.standard.object(forKey: "removeFillers") as? Bool ?? true)
    }
}

private final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var continuation: CheckedContinuation<URL, Error>?
    private var progress: ((Double) -> Void)?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    func download(_ url: URL, progress: @escaping (Double) -> Void) async throws -> URL {
        self.progress = progress
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForResource = 3600
                self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.task = session!.downloadTask(with: url); self.task!.resume(); lock.unlock()
            }
        } onCancel: { self.lock.lock(); self.cancelled = true; let task = self.task; self.lock.unlock(); task?.cancel() }
    }
    private func finish(url: URL?, error: Error?) {
        lock.lock(); let continuation = self.continuation; self.continuation = nil; let cancelled = self.cancelled; lock.unlock()
        if cancelled {
            if let url { try? FileManager.default.removeItem(at: url) }
            continuation?.resume(throwing: CancellationError())
        } else if let error { continuation?.resume(throwing: error) }
        else if let url { continuation?.resume(returning: url) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else { throw FolioError.message("Model download failed. Check your internet connection and try again.") }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(url: destination, error: nil)
        } catch { finish(url: nil, error: error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(url: nil, error: error) }
        session.finishTasksAndInvalidate(); self.session = nil; lock.lock(); self.task = nil; lock.unlock()
    }
}
