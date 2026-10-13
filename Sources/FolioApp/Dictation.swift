import AVFoundation
import Foundation
import FolioCore

private final class AudioAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var pcm = Data()
    private var meter: Float = 0
    private var speechFrames = 0
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var samples = [Int16](); samples.reserveCapacity(count)
        var sum: Float = 0
        for i in 0..<count { let raw = channel[i]; let sample: Float = raw.isFinite ? max(-1, min(1, raw)) : 0; sum += sample * sample; samples.append(Int16(sample * 32767)) }
        let rms = sqrt(sum / Float(max(count, 1)))
        lock.lock(); defer { lock.unlock() }

        samples.withUnsafeBytes { pcm.append(contentsOf: $0) }
        meter = min(1, rms * 10)
        if rms > 0.006 { speechFrames += count }
    }
    func snapshot() -> (Data, Float, Bool) {
        lock.lock(); defer { lock.unlock() }
        return (pcm, meter, speechFrames > 3200)
    }
    func reset() { lock.lock(); pcm.removeAll(keepingCapacity: true); meter = 0; speechFrames = 0; lock.unlock() }
}

@MainActor
final class Dictation: ObservableObject {
    @Published var removeFillers = UserDefaults.standard.object(forKey: "removeFillers") as? Bool ?? true { didSet { UserDefaults.standard.set(removeFillers, forKey: "removeFillers") } }
    @Published var recording = false
    @Published var transcribing = false
    @Published var preview = ""
    @Published var level: Float = 0
    @Published var seconds = 0
    @Published var error: String?
    @Published private(set) var starting = false
    var busy: Bool { starting || recording || transcribing }
    private var tapInstalled = false
    private var deviceObserver: NSObjectProtocol?
    private let engine = AVAudioEngine()
    private let audio = AudioAccumulator()
    private var timer: Timer?
    private var started = Date()
    private var previewTask: Task<Void, Never>?
    private var generation = UUID()
    private var processedBytes = 0
    private var committed = ""
    private(set) var lastRecording: Data?
    var onLimit: (() -> Void)?
    var onPreview: ((String) -> Void)?
    var onCheckpoint: ((Data, String) -> Void)?
    init() {
        deviceObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.recording else { return }
                self.error = "Your audio device changed. The captured recording is being saved; reconnect your microphone to continue."
                self.onLimit?()
            }
        }
    }
    deinit { if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver) } }

    func start(models: LocalEngines, names: [String]) async {
        guard !recording && !transcribing && !starting else { return }
        starting = true; generation = UUID(); let requestID = generation; defer { starting = false }
        guard models.ready else { error = "Start the local models in Settings before recording."; return }
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard requestID == generation else { return }
        guard allowed else { error = "Microphone access is off. Enable Syllavane in System Settings → Privacy & Security → Microphone."; return }
        do {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0,
                  let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: format, to: target) else { throw FolioError.message("No working microphone was found.") }
            audio.reset(); processedBytes = 0; committed = ""; preview = ""; seconds = 0; error = nil; lastRecording = nil
            let accumulator = audio
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / format.sampleRate + 16)
                guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
                var supplied = false
                var conversionError: NSError?
                converter.convert(to: output, error: &conversionError) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true; status.pointee = .haveData; return buffer
                }
                if conversionError == nil { accumulator.append(output) }
            }
            tapInstalled = true
            engine.prepare(); try engine.start()
            recording = true; started = Date(); generation = UUID()
            let current = generation
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.recording else { return }
                    self.level = self.audio.snapshot().1
                    let elapsed = Int(Date().timeIntervalSince(self.started))
                    if elapsed != self.seconds {
                        self.seconds = elapsed
                        if elapsed >= 1200 { self.onLimit?(); return }
                        if elapsed > 0 && elapsed % 5 == 0 {
                            let snapshot = self.audio.snapshot()
                            if snapshot.2 { self.onCheckpoint?(Self.wav(snapshot.0), self.preview) }
                        }
                        if elapsed > 0 && elapsed % 5 == 0 && self.previewTask == nil {
                            let snapshot = self.audio.snapshot()
                            if snapshot.2 {
                                let offset = self.processedBytes
                                let pending = snapshot.0.count - offset
                                guard pending >= 16000 else { return }
                                let pendingPCM = Data(snapshot.0.dropFirst(offset))
                                guard TranscriptFilter.hasVoiceEnergy(pendingPCM) else { self.processedBytes = max(offset, snapshot.0.count - 32000); return }
                                let wav = Self.wav(pendingPCM)
                                let commit = (pending >= 16000 * 2 * 5 && snapshot.1 < 0.08) || pending >= 16000 * 2 * 25
                                self.previewTask = Task {
                                    defer { self.previewTask = nil }
                                    do {
                                        let result = try await models.transcribe(wav: wav, names: names)
                                        if !Task.isCancelled && self.generation == current && self.recording {
                                            self.preview = Self.join(self.committed, result)
                                            self.onPreview?(self.preview)
                                            if commit { self.committed = self.preview; self.processedBytes = max(offset, snapshot.0.count - 16000 * 2) }
                                        }
                                    } catch { /* Final transcription reports actionable errors. */ }
                                }
                            }
                        }

                    }
                }
            }
        } catch { if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }; self.error = error.localizedDescription }
    }
    func finish(models: LocalEngines, names: [String]) async throws -> String {
        guard recording else { return "" }
        stopCapture(); transcribing = true
        defer { transcribing = false }
        let (pcm, _, hasSpeech) = audio.snapshot()
        guard hasSpeech else { preview = ""; return "" }
        lastRecording = Self.wav(pcm)
        onCheckpoint?(lastRecording!, preview)
        let pendingPCM = Data(pcm.dropFirst(processedBytes))
        let result = TranscriptFilter.hasVoiceEnergy(pendingPCM) ? try await models.transcribe(wav: Self.wav(pendingPCM), names: names) : ""
        preview = Self.join(committed, result); return preview
    }
    func restoreRecording(_ wav: Data) { lastRecording = wav }
    func checkpointCapture() { guard recording || transcribing else { return }; let snapshot = audio.snapshot(); if snapshot.2 { onCheckpoint?(Self.wav(snapshot.0), preview) } }
    func retry(models: LocalEngines, names: [String]) async throws -> String {
        guard let lastRecording else { return "" }
        transcribing = true; defer { transcribing = false }
        let result = try await models.transcribe(wav: lastRecording, names: names); preview = result; return result
    }
    func pauseForInterruption() { checkpointCapture(); stopCapture() }
    func discard() { stopCapture(); audio.reset(); lastRecording = nil; preview = ""; transcribing = false }
    private func stopCapture() {
        generation = UUID(); previewTask?.cancel(); previewTask = nil; timer?.invalidate(); timer = nil
        if recording { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        recording = false; level = 0
    }
    static func join(_ prior: String, _ next: String) -> String {
        let a = prior.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = next.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !a.isEmpty else { return next }
        guard !b.isEmpty else { return prior }
        let limit = min(12, min(a.count, b.count))
        if limit > 0 {
            for count in stride(from: limit, through: 1, by: -1) {
                let lhs = a.suffix(count).map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
                let rhs = b.prefix(count).map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
                if lhs == rhs { return prior + (b.count > count ? " " + b.dropFirst(count).joined(separator: " ") : "") }
            }
        }
        return prior + " " + next
    }
    static func wav(_ pcm: Data) -> Data {
        var result = Data()
        func text(_ value: String) { result.append(Data(value.utf8)) }
        func u32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { result.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { result.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(pcm.count + 36)); text("WAVEfmt "); u32(16); u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16); text("data"); u32(UInt32(pcm.count)); result.append(pcm)
        return result
    }
}
