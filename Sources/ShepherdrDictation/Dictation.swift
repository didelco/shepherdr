import AVFoundation
import FluidAudio
import Foundation
import Observation

/// On-device dictation with NVIDIA Parakeet TDT v3 through FluidAudio, the engine behind
/// theam/scribe. Audio never leaves the Mac and is held in memory only while recording.
@MainActor @Observable
public final class Dictation {
    public enum State: Equatable, Sendable {
        case idle
        case recording(since: Date)
        case transcribing
        case failed(String)
    }

    public enum ModelState: Equatable, Sendable {
        case notLoaded
        /// Fetching the model for the first time; progress runs from 0 to 1.
        case downloading(progress: Double)
        /// Loading into memory, which takes a few seconds once per launch.
        case loading
        case ready
    }

    public private(set) var state: State = .idle
    public private(set) var model: ModelState = .notLoaded
    /// Recent input loudness from 0 to 1, for a level meter.
    public private(set) var level: Float = 0

    @ObservationIgnored private var manager: AsrManager?
    @ObservationIgnored private var loading: Task<Void, Error>?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var recording: Recording?

    public init() {}

    /// Whether the model is on this Mac. It lives in FluidAudio's shared cache, so scribe and
    /// other FluidAudio apps reuse the same download.
    public static var isModelInstalled: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
    }

    public static let modelDownloadSize = "about 460 MB"

    public var isRecording: Bool {
        if case .recording = state { true } else { false }
    }

    /// Whether a recording can start now.
    public var isReady: Bool {
        switch state {
        case .idle, .failed: true
        default: false
        }
    }

    /// Starts recording at once; the model loads (or downloads) meanwhile.
    public func start() async {
        guard isReady else { return }
        // Without a usage description, macOS terminates an app that opens the microphone.
        guard Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil else {
            return fail("Dictation needs the Shepherdr app; this build does not declare microphone use.")
        }
        guard await Self.microphoneAllowed() else {
            return fail("Shepherdr cannot use the microphone. Allow it in System Settings → Privacy & Security → Microphone.")
        }
        do {
            try startRecording()
        } catch {
            stopEngine()
            return fail("Dictation could not start: \(error.localizedDescription)")
        }
        Task { try? await prepare() }
    }

    /// Stops recording and returns what was said, or nil for silence or a very short take.
    public func stop() async -> String? {
        guard isRecording, let recording else { return nil }
        stopEngine()
        self.recording = nil
        let samples = recording.samples()
        // Less than half a second is a stray click, not a prompt.
        guard samples.count >= Recording.sampleRate / 2 else {
            state = .idle
            return nil
        }
        state = .transcribing
        do {
            let text = try await transcribe(samples)
            state = .idle
            return text.isEmpty ? nil : text
        } catch {
            fail("Transcription failed: \(error.localizedDescription)")
            return nil
        }
    }

    public func cancel() {
        stopEngine()
        recording = nil
        state = .idle
    }

    public func dismissFailure() {
        if case .failed = state { state = .idle }
    }

    /// Loads the model once, downloading it first if needed. Concurrent callers share one load.
    public func prepare() async throws {
        if manager != nil { return }
        if let loading { return try await loading.value }
        let task = Task { try await load() }
        loading = task
        do {
            try await task.value
        } catch {
            loading = nil
            model = .notLoaded
            throw error
        }
    }

    /// Transcribes 16 kHz mono samples. Parakeet detects the language among 25 European ones.
    public func transcribe(_ samples: [Float]) async throws -> String {
        try await prepare()
        guard let manager else { return "" }
        let result = try await manager.transcribe(samples, source: .microphone)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() async throws {
        let installed = Self.isModelInstalled
        model = installed ? .loading : .downloading(progress: 0)
        let models = try await AsrModels.downloadAndLoad(version: .v3) { progress in
            guard !installed else { return }
            Task { @MainActor [weak self] in
                guard let self, case .downloading = self.model else { return }
                self.model = progress.fractionCompleted < 1 ? .downloading(progress: progress.fractionCompleted) : .loading
            }
        }
        model = .loading
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        self.manager = manager
        model = .ready
    }

    private func startRecording() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, let recording = Recording(from: format) else {
            throw DictationError.noMicrophone
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format,
                         block: Self.tap(into: recording) { [weak self] level in Task { @MainActor in self?.level = level } })
        engine.prepare()
        try engine.start()
        self.engine = engine
        self.recording = recording
        state = .recording(since: Date())
    }

    /// AVFAudio calls taps on its own queue. A tap written inside this main-actor class would be
    /// main-actor isolated, and Swift stops the app the first time audio arrives off the main thread.
    nonisolated private static func tap(into recording: Recording,
                                        level: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in level(recording.append(buffer)) }
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        level = 0
    }

    private func fail(_ message: String) {
        state = .failed(message)
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }
}

enum DictationError: LocalizedError {
    case noMicrophone

    var errorDescription: String? { "no microphone input is available" }
}

/// Collects microphone audio as 16 kHz mono samples, converting each buffer as it arrives on
/// the audio thread. Only appends and reads cross threads, under a lock.
private final class Recording: @unchecked Sendable {
    static let sampleRate = 16_000
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let lock = NSLock()
    private var collected: [Float] = []

    init?(from format: AVAudioFormat) {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(Self.sampleRate),
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else { return nil }
        self.target = target
        self.converter = converter
    }

    /// Converts and keeps one buffer; returns its loudness for the level meter.
    func append(_ buffer: AVAudioPCMBuffer) -> Float {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return 0 }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0], output.frameLength > 0 else { return 0 }
        let frames = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        lock.lock()
        collected.append(contentsOf: frames)
        lock.unlock()
        let rms = (frames.reduce(0) { $0 + $1 * $1 } / Float(frames.count)).squareRoot()
        return min(1, rms * 6)
    }

    func samples() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }
}
