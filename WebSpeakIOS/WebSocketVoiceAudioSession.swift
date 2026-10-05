import AVFoundation
import AudioToolbox
import Combine
import Darwin
import Foundation
import os

/// Legacy TeamSpeak audio carried by the voice WebSocket: mono Int16 PCM in,
/// and one Opus packet per remote speaker out. This is used only when the
/// gateway says its WebRTC audio path is disabled.
final class WebSocketVoiceAudioSession: @unchecked Sendable {
    private static let sampleRate = 48_000.0
    private static let frameSamples = 960
    private static let maxQueuedFrames = 5

    private let gatewaySocket: URLSessionWebSocketTask
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.echosixhiya.webspeak.ios",
        category: "LegacyVoice"
    )
    private let audioQueue = DispatchQueue(label: "com.echosixhiya.webspeak.legacy-voice-audio", qos: .userInitiated)
    private let sendQueue = DispatchQueue(label: "com.echosixhiya.webspeak.legacy-voice-send", qos: .userInitiated)
    private let stateLock = NSLock()

    private var isClosed = false
    private var microphoneMuted = true
    private var permissionGranted = false
    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var silentOutputNode: AVAudioPlayerNode?
    private var pcmFormat: AVAudioFormat?
    private var opusFormat: AVAudioFormat?
    private var inputConverter: AVAudioConverter?
    private var speakerDecoders: [Int: AVAudioConverter] = [:]
    private var speakerPlayers: [Int: AVAudioPlayerNode] = [:]
    private var speakerVolumes: [Int: Float] = [:]
    private var speakerMuted: Bool
    private var queuedPlaybackBuffers: [Int: Int] = [:]
    private var pendingSamples: [Float] = []
    private var pendingSendFrames: [Data] = []
    private var isSendingFrame = false
    private var microphoneMuteWaiters: [CheckedContinuation<Void, Never>] = []
    private var sentFrameCount = 0
    private var receivedFrameCount = 0
    private var droppedMicrophoneFrameCount = 0
    private var droppedPlaybackFrameCount = 0
    private var didReportCaptureError = false
    private var voiceActivityDetectionEnabled: Bool
    private var voiceActivityThreshold: Float
    private var voxReleaseFrames = 0
    private var lastLevelReportUptime: TimeInterval = 0
    private var noiseSuppressionEnabled: Bool

    var onStatusChange: ((String) -> Void)?
    var onMicrophoneLevel: ((Double) -> Void)?

    init(
        gatewaySocket: URLSessionWebSocketTask,
        voiceActivityDetectionEnabled: Bool = false,
        voiceActivityThreshold: Double = 0.008,
        noiseSuppressionEnabled: Bool = true,
        speakerMuted: Bool = false
    ) {
        self.gatewaySocket = gatewaySocket
        self.voiceActivityDetectionEnabled = voiceActivityDetectionEnabled
        self.voiceActivityThreshold = Float(min(0.08, max(0.001, voiceActivityThreshold)))
        self.noiseSuppressionEnabled = noiseSuppressionEnabled
        self.speakerMuted = speakerMuted
    }

    /// Starts playback regardless of microphone permission. If permission is
    /// denied, incoming voice still works and the caller can disable mic UI.
    func start(muted: Bool) async throws -> Bool {
        guard !isStopped() else { throw VoiceAudioError.stopped }
        updateMicrophoneMuteState(muted)

        updatePermissionGranted(await requestMicrophonePermission())
        guard !isStopped() else { throw VoiceAudioError.stopped }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        let audioEngine = AVAudioEngine()
        let outputNode = AVAudioPlayerNode()
        audioEngine.attach(outputNode)
        let micInput = audioEngine.inputNode
        var microphoneTapInstalled = false

        do {
            try session.setActive(true)
            let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
            var opusDescription = AudioStreamBasicDescription(
                mSampleRate: Self.sampleRate,
                mFormatID: kAudioFormatOpus,
                mFormatFlags: 0,
                mBytesPerPacket: 0,
                mFramesPerPacket: UInt32(Self.frameSamples),
                mBytesPerFrame: 0,
                mChannelsPerFrame: 1,
                mBitsPerChannel: 0,
                mReserved: 0
            )
            guard let compressedFormat = AVAudioFormat(streamDescription: &opusDescription) else {
                throw VoiceAudioError.opusFormatUnavailable
            }

            audioEngine.connect(outputNode, to: audioEngine.mainMixerNode, format: format)
            outputNode.play()

            if permissionGranted {
                do {
                    try micInput.setVoiceProcessingEnabled(noiseSuppressionEnabled)
                } catch {
                    logger.error("Could not configure system voice processing; enabled=\(self.noiseSuppressionEnabled, privacy: .public) code=\((error as NSError).code, privacy: .public)")
                    reportStatus("系统语音处理不可用；将继续使用当前麦克风输入。")
                }
                let inputFormat = micInput.outputFormat(forBus: 0)
                guard inputFormat.sampleRate > 0,
                      inputFormat.channelCount > 0,
                      let converter = AVAudioConverter(from: inputFormat, to: format)
                else {
                    throw VoiceAudioError.microphoneFormatUnavailable
                }
                inputConverter = converter
                inputNode = micInput
                micInput.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
                    guard let copiedBuffer = Self.copy(buffer) else { return }
                    self?.audioQueue.async { [weak self, copiedBuffer] in
                        self?.processMicrophoneBuffer(copiedBuffer)
                    }
                }
                microphoneTapInstalled = true
            }

            pcmFormat = format
            opusFormat = compressedFormat
            engine = audioEngine
            silentOutputNode = outputNode

            try audioEngine.start()
        } catch {
            if microphoneTapInstalled { micInput.removeTap(onBus: 0) }
            audioEngine.stop()
            engine = nil
            inputNode = nil
            silentOutputNode = nil
            inputConverter = nil
            pcmFormat = nil
            opusFormat = nil
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw error
        }

        logger.notice("Legacy WebSocket audio started; microphonePermission=\(self.permissionGranted, privacy: .public)")
        if !permissionGranted {
            reportStatus("可接收语音；麦克风权限未开启，可在系统设置中允许。")
        }
        return permissionGranted
    }

    func setMicrophoneMuted(_ muted: Bool) {
        updateMicrophoneMuteState(muted)
        if muted {
            audioQueue.async { [weak self] in
                self?.pendingSamples.removeAll(keepingCapacity: true)
                self?.voxReleaseFrames = 0
            }
            sendQueue.async { [weak self] in
                self?.pendingSendFrames.removeAll(keepingCapacity: true)
            }
        }
    }

    /// Closes the local capture gate and waits until any PCM WebSocket send
    /// already in flight completes, so a later gateway control frame cannot
    /// overtake older microphone audio.
    func muteAndWaitForPendingMicrophoneFrames() async {
        updateMicrophoneMuteState(true)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            audioQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.pendingSamples.removeAll(keepingCapacity: true)
                self.voxReleaseFrames = 0
                self.sendQueue.async {
                    self.pendingSendFrames.removeAll(keepingCapacity: true)
                    if self.isSendingFrame {
                        self.microphoneMuteWaiters.append(continuation)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func setVoiceActivityDetection(enabled: Bool, threshold: Double) {
        let normalizedThreshold = Float(min(0.08, max(0.001, threshold)))
        audioQueue.async { [weak self] in
            self?.voiceActivityDetectionEnabled = enabled
            self?.voiceActivityThreshold = normalizedThreshold
            if !enabled { self?.voxReleaseFrames = 0 }
        }
    }

    func setNoiseSuppressionEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.noiseSuppressionEnabled = enabled
            guard let inputNode = self.inputNode else { return }
            do {
                try inputNode.setVoiceProcessingEnabled(enabled)
                self.reportStatus(enabled ? "已启用 Apple 系统语音处理。" : "已关闭 Apple 系统语音处理。")
            } catch {
                self.reportStatus("无法切换系统语音处理；请在下次连接时重试。")
                self.logger.error("Could not update system voice processing; code=\((error as NSError).code, privacy: .public)")
            }
        }
    }

    func receiveAudioFrame(_ data: Data) {
        audioQueue.async { [weak self, data] in
            self?.decodeAndPlay(data)
        }
    }

    func setMemberVolume(_ clientID: Int, volume: Double) {
        let normalized = Float(min(4, max(0, volume)))
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.speakerVolumes[clientID] = normalized
            self.speakerPlayers[clientID]?.volume = self.speakerMuted ? 0 : normalized
        }
    }

    func setSpeakerMuted(_ muted: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.speakerMuted = muted
            for (clientID, player) in self.speakerPlayers {
                player.volume = muted ? 0 : (self.speakerVolumes[clientID] ?? 1)
            }
        }
    }

    func removeMember(_ clientID: Int) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.speakerDecoders.removeValue(forKey: clientID)
            self.queuedPlaybackBuffers.removeValue(forKey: clientID)
            if let player = self.speakerPlayers.removeValue(forKey: clientID) {
                player.stop()
                self.engine?.detach(player)
            }
        }
    }

    func close() {
        stateLock.lock()
        guard !isClosed else {
            stateLock.unlock()
            return
        }
        isClosed = true
        microphoneMuted = true
        stateLock.unlock()

        audioQueue.sync {
            inputNode?.removeTap(onBus: 0)
            for player in speakerPlayers.values { player.stop() }
            silentOutputNode?.stop()
            engine?.stop()
            speakerDecoders.removeAll()
            speakerPlayers.removeAll()
            queuedPlaybackBuffers.removeAll()
            pendingSamples.removeAll()
            voxReleaseFrames = 0
            inputConverter = nil
            pcmFormat = nil
            opusFormat = nil
            inputNode = nil
            silentOutputNode = nil
            engine = nil
        }
        sendQueue.async { [weak self] in
            guard let self else { return }
            self.pendingSendFrames.removeAll()
            let waiters = self.microphoneMuteWaiters
            self.microphoneMuteWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        logger.info("Legacy WebSocket audio stopped")
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func processMicrophoneBuffer(_ input: AVAudioPCMBuffer) {
        stateLock.lock()
        let shouldSend = !isClosed && !microphoneMuted && permissionGranted
        stateLock.unlock()
        guard shouldSend else {
            pendingSamples.removeAll(keepingCapacity: true)
            voxReleaseFrames = 0
            return
        }
        reportMicrophoneLevel(for: input)
        guard let inputConverter, let pcmFormat else { return }

        let ratio = Self.sampleRate / max(1, input.format.sampleRate)
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio) + 128)
        guard let converted = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: max(1, capacity)) else { return }
        var didProvideInput = false
        var conversionError: NSError?
        let result = inputConverter.convert(to: converted, error: &conversionError) { _, inputStatus in
            guard !didProvideInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            inputStatus.pointee = .haveData
            return input
        }
        guard result != .error, conversionError == nil else {
            if !didReportCaptureError {
                didReportCaptureError = true
                logger.error("Microphone format conversion failed; domain=\(conversionError?.domain ?? "unknown", privacy: .public) code=\(conversionError?.code ?? 0, privacy: .public)")
                reportStatus("麦克风音频格式转换失败；可重试语音连接。")
            }
            return
        }
        guard converted.frameLength > 0, let samples = converted.floatChannelData?[0] else { return }

        for index in 0 ..< Int(converted.frameLength) {
            let sample = max(-1, min(1, samples[index]))
            let scale: Float = sample < 0 ? 32_768 : 32_767
            pendingSamples.append(sample * scale)
        }
        while pendingSamples.count >= Self.frameSamples {
            var frame = [Int16](repeating: 0, count: Self.frameSamples)
            for index in 0 ..< Self.frameSamples {
                frame[index] = Int16(clamping: Int(pendingSamples[index].rounded())).littleEndian
            }
            pendingSamples.removeFirst(Self.frameSamples)
            guard shouldTransmitPCMFrame(frame) else { continue }
            let frameData = frame.withUnsafeBytes { Data($0) }
            enqueueMicrophoneFrame(frameData)
        }
    }

    private func shouldTransmitPCMFrame(_ samples: [Int16]) -> Bool {
        guard voiceActivityDetectionEnabled else { return true }
        let squareSum = samples.reduce(0.0) { partial, sample in
            let normalized = Double(sample) / 32_768
            return partial + normalized * normalized
        }
        let rms = sqrt(squareSum / Double(samples.count))
        if rms >= Double(voiceActivityThreshold) {
            voxReleaseFrames = 15
            return true
        }
        guard voxReleaseFrames > 0 else { return false }
        voxReleaseFrames -= 1
        return true
    }

    private func reportMicrophoneLevel(for buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLevelReportUptime >= 0.08 else { return }
        lastLevelReportUptime = now
        let samples = channels[0]
        var squareSum = 0.0
        for index in 0 ..< Int(buffer.frameLength) {
            let sample = Double(samples[index])
            squareSum += sample * sample
        }
        let level = min(1, sqrt(squareSum / Double(buffer.frameLength)) * 4)
        Task { @MainActor [weak self] in self?.onMicrophoneLevel?(level) }
    }

    private func enqueueMicrophoneFrame(_ data: Data) {
        sendQueue.async { [weak self, data] in
            guard let self else { return }
            guard self.canCaptureMicrophone() else {
                self.pendingSendFrames.removeAll(keepingCapacity: true)
                return
            }
            guard self.gatewaySocket.state == .running else { return }
            if self.pendingSendFrames.count >= Self.maxQueuedFrames {
                self.pendingSendFrames.removeFirst()
                self.droppedMicrophoneFrameCount += 1
                if self.droppedMicrophoneFrameCount.isMultiple(of: 50) {
                    self.logger.warning("Legacy microphone queue dropped frames; total=\(self.droppedMicrophoneFrameCount, privacy: .public)")
                }
            }
            self.pendingSendFrames.append(data)
            self.sendNextMicrophoneFrame()
        }
    }

    private func sendNextMicrophoneFrame() {
        guard !isSendingFrame else { return }
        guard canCaptureMicrophone() else {
            pendingSendFrames.removeAll(keepingCapacity: true)
            resumeMicrophoneMuteWaitersIfIdle()
            return
        }
        guard !pendingSendFrames.isEmpty else { return }
        isSendingFrame = true
        let frame = pendingSendFrames.removeFirst()
        let socket = gatewaySocket
        Task { [weak self, socket, frame] in
            do {
                try await socket.send(.data(frame))
                self?.sendQueue.async { [weak self] in
                    guard let self else { return }
                    guard !self.isStopped() else {
                        self.isSendingFrame = false
                        self.pendingSendFrames.removeAll()
                        return
                    }
                    self.sentFrameCount += 1
                    if self.sentFrameCount == 1 || self.sentFrameCount.isMultiple(of: 100) {
                        self.logger.debug("Legacy microphone PCM sent; frames=\(self.sentFrameCount, privacy: .public)")
                    }
                    self.isSendingFrame = false
                    self.sendNextMicrophoneFrame()
                    self.resumeMicrophoneMuteWaitersIfIdle()
                }
            } catch {
                self?.sendQueue.async { [weak self] in
                    guard let self else { return }
                    self.isSendingFrame = false
                    self.pendingSendFrames.removeAll()
                    self.resumeMicrophoneMuteWaitersIfIdle()
                    let value = error as NSError
                    self.logger.error("Legacy microphone WebSocket send failed; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
                    self.reportStatus("WebSocket 麦克风发送失败；请检查连接并重试。")
                }
            }
        }
    }

    private func resumeMicrophoneMuteWaitersIfIdle() {
        guard !isSendingFrame, !microphoneMuteWaiters.isEmpty else { return }
        let waiters = microphoneMuteWaiters
        microphoneMuteWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func decodeAndPlay(_ data: Data) {
        guard !isStopped(), data.count > 3, let pcmFormat, let opusFormat, let engine else { return }
        let codec = Int(data[data.startIndex])
        guard codec == 4 || codec == 5 else { return }
        let clientID = Int(data[data.startIndex + 1]) << 8 | Int(data[data.startIndex + 2])
        guard clientID > 0 else { return }
        let packet = data.subdata(in: 3 ..< data.count)
        guard packet.count <= 4_000 else { return }

        let decoder: AVAudioConverter
        if let current = speakerDecoders[clientID] {
            decoder = current
        } else {
            guard let created = AVAudioConverter(from: opusFormat, to: pcmFormat) else {
                logger.error("Could not create a legacy Opus decoder")
                return
            }
            speakerDecoders[clientID] = created
            decoder = created
        }

        let compressed = AVAudioCompressedBuffer(
            format: opusFormat,
            packetCapacity: 1,
            maximumPacketSize: max(1_024, packet.count)
        )
        compressed.byteLength = UInt32(packet.count)
        compressed.packetCount = 1
        packet.withUnsafeBytes { source in
            if let baseAddress = source.baseAddress {
                memcpy(compressed.data, baseAddress, packet.count)
            }
        }
        compressed.packetDescriptions?[0] = AudioStreamPacketDescription(
            mStartOffset: 0,
            mVariableFramesInPacket: UInt32(Self.frameSamples),
            mDataByteSize: UInt32(packet.count)
        )

        guard let decoded = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: 1_920) else { return }
        var didProvidePacket = false
        var decodeError: NSError?
        let status = decoder.convert(to: decoded, error: &decodeError) { _, inputStatus in
            guard !didProvidePacket else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            didProvidePacket = true
            inputStatus.pointee = .haveData
            return compressed
        }
        guard status != .error, decodeError == nil, decoded.frameLength > 0 else {
            logger.error("Legacy Opus decode failed; domain=\(decodeError?.domain ?? "unknown", privacy: .public) code=\(decodeError?.code ?? 0, privacy: .public)")
            return
        }

        let queued = queuedPlaybackBuffers[clientID, default: 0]
        guard queued < Self.maxQueuedFrames else {
            droppedPlaybackFrameCount += 1
            if droppedPlaybackFrameCount.isMultiple(of: 50) {
                logger.warning("Legacy remote playback queue dropped frames; total=\(self.droppedPlaybackFrameCount, privacy: .public)")
            }
            return
        }
        let player: AVAudioPlayerNode
        if let existing = speakerPlayers[clientID] {
            player = existing
        } else {
            let created = AVAudioPlayerNode()
            created.volume = speakerMuted ? 0 : (speakerVolumes[clientID] ?? 1)
            engine.attach(created)
            engine.connect(created, to: engine.mainMixerNode, format: pcmFormat)
            speakerPlayers[clientID] = created
            player = created
            player.play()
        }

        queuedPlaybackBuffers[clientID] = queued + 1
        player.scheduleBuffer(decoded) { [weak self] in
            self?.audioQueue.async { [weak self] in
                guard let self else { return }
                self.queuedPlaybackBuffers[clientID] = max(0, self.queuedPlaybackBuffers[clientID, default: 1] - 1)
            }
        }
        receivedFrameCount += 1
        if receivedFrameCount == 1 || receivedFrameCount.isMultiple(of: 100) {
            logger.debug("Legacy remote Opus decoded; frames=\(self.receivedFrameCount, privacy: .public) speakers=\(self.speakerDecoders.count, privacy: .public)")
        }
    }

    private func isStopped() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isClosed
    }

    private func canCaptureMicrophone() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return !isClosed && !microphoneMuted && permissionGranted
    }

    private func updateMicrophoneMuteState(_ muted: Bool) {
        stateLock.lock()
        microphoneMuted = muted
        stateLock.unlock()
    }

    private func updatePermissionGranted(_ granted: Bool) {
        stateLock.lock()
        permissionGranted = granted
        stateLock.unlock()
    }

    private func reportStatus(_ status: String) {
        Task { @MainActor [weak self] in
            self?.onStatusChange?(status)
        }
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let result = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        result.frameLength = source.frameLength
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(result.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else { return nil }
        for index in 0 ..< sourceBuffers.count {
            guard let sourceData = sourceBuffers[index].mData,
                  let destinationData = destinationBuffers[index].mData
            else {
                return nil
            }
            let byteCount = Int(sourceBuffers[index].mDataByteSize)
            memcpy(destinationData, sourceData, byteCount)
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }
        return result
    }

    private enum VoiceAudioError: LocalizedError {
        case stopped
        case opusFormatUnavailable
        case microphoneFormatUnavailable

        var errorDescription: String? {
            switch self {
            case .stopped: "语音连接已停止。"
            case .opusFormatUnavailable: "系统 Opus 音频格式不可用。"
            case .microphoneFormatUnavailable: "无法读取或转换麦克风音频格式。"
            }
        }
    }
}

/// A local-only microphone meter used before joining a voice session. It never
/// records, persists, or sends captured samples.
@MainActor
final class MicrophoneTestSession: ObservableObject {
    @Published private(set) var isStarting = false
    @Published private(set) var isRunning = false
    @Published private(set) var level = 0.0
    @Published private(set) var errorMessage: String?

    private var engine: AVAudioEngine?
    private var lastLevelReportUptime: TimeInterval = 0
    private var startRequestID = UUID()

    func start() async {
        guard !isRunning, !isStarting else { return }
        let requestID = UUID()
        startRequestID = requestID
        isStarting = true
        errorMessage = nil
        level = 0
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard startRequestID == requestID else { return }
        guard granted else {
            isStarting = false
            errorMessage = "麦克风权限未开启；可在系统设置中允许 WebSpeak 使用麦克风。"
            return
        }

        let session = AVAudioSession.sharedInstance()
        var testEngine: AVAudioEngine?
        var microphoneTapInstalled = false
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)
            let audioEngine = AVAudioEngine()
            testEngine = audioEngine
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw MicrophoneTestError.inputUnavailable
            }
            input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, _ in
                guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
                var squareSum = 0.0
                for index in 0 ..< Int(buffer.frameLength) {
                    let sample = Double(samples[index])
                    squareSum += sample * sample
                }
                let measuredLevel = min(1, sqrt(squareSum / Double(buffer.frameLength)) * 4)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    guard now - self.lastLevelReportUptime >= 0.08 else { return }
                    self.lastLevelReportUptime = now
                    self.level = measuredLevel
                }
            }
            microphoneTapInstalled = true
            try audioEngine.start()
            engine = audioEngine
            testEngine = nil
            isStarting = false
            isRunning = true
        } catch {
            if microphoneTapInstalled { testEngine?.inputNode.removeTap(onBus: 0) }
            testEngine?.stop()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            errorMessage = "无法启动麦克风测试：\(error.localizedDescription)"
            engine = nil
            isStarting = false
            isRunning = false
            level = 0
        }
    }

    func stop() {
        startRequestID = UUID()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        isStarting = false
        isRunning = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private enum MicrophoneTestError: LocalizedError {
        case inputUnavailable

        var errorDescription: String? { "当前没有可用的麦克风输入。" }
    }
}
