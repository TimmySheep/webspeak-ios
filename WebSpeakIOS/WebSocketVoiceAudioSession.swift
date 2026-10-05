import AVFoundation
import AudioToolbox
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
    private var queuedPlaybackBuffers: [Int: Int] = [:]
    private var pendingSamples: [Float] = []
    private var pendingSendFrames: [Data] = []
    private var isSendingFrame = false
    private var sentFrameCount = 0
    private var receivedFrameCount = 0
    private var droppedMicrophoneFrameCount = 0
    private var droppedPlaybackFrameCount = 0
    private var didReportCaptureError = false

    var onStatusChange: ((String) -> Void)?

    init(gatewaySocket: URLSessionWebSocketTask) {
        self.gatewaySocket = gatewaySocket
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
            }
            sendQueue.async { [weak self] in
                self?.pendingSendFrames.removeAll(keepingCapacity: true)
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
            self.speakerPlayers[clientID]?.volume = normalized
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
            inputConverter = nil
            pcmFormat = nil
            opusFormat = nil
            inputNode = nil
            silentOutputNode = nil
            engine = nil
        }
        sendQueue.async { [weak self] in
            self?.pendingSendFrames.removeAll()
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
            return
        }
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
            let frameData = frame.withUnsafeBytes { Data($0) }
            enqueueMicrophoneFrame(frameData)
        }
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
                }
            } catch {
                self?.sendQueue.async { [weak self] in
                    guard let self else { return }
                    self.isSendingFrame = false
                    self.pendingSendFrames.removeAll()
                    let value = error as NSError
                    self.logger.error("Legacy microphone WebSocket send failed; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
                    self.reportStatus("WebSocket 麦克风发送失败；请检查连接并重试。")
                }
            }
        }
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
            created.volume = speakerVolumes[clientID] ?? 1
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
