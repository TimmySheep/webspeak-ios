import AVFoundation
import Foundation
import os
@preconcurrency import WebRTC

@MainActor
final class WebRTCAudioSession: NSObject {
    private let gatewaySocket: URLSessionWebSocketTask
    private let factory = RTCPeerConnectionFactory()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.echosixhiya.webspeak.ios",
        category: "Voice"
    )
    private var peerConnection: RTCPeerConnection?
    private var microphoneTrack: RTCAudioTrack?
    private var remoteAudioTracks: [RTCAudioTrack] = []
    private var speakerMuted = false
    private var gatheringContinuation: CheckedContinuation<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var generatedCandidateCount = 0
    private var isStopped = false
    private var didReportFailure = false

    private(set) var isConnected = false
    var onStatusChange: ((String) -> Void)?
    var onConnectionFailure: ((String) -> Void)?

    init(gatewaySocket: URLSessionWebSocketTask) {
        self.gatewaySocket = gatewaySocket
    }

    func start(muted: Bool) async throws {
        guard !isStopped else { throw MediaSessionError.stopped }
        let microphoneGranted = await requestMicrophonePermission()
        logger.info("WebRTC microphone permission result=\(microphoneGranted, privacy: .public)")
        guard microphoneGranted else { throw MediaSessionError.microphonePermissionDenied }

        try configureAudioSession()
        logger.info("Creating WebRTC peer connection and microphone track; initiallyMuted=\(muted, privacy: .public)")
        let configuration = RTCConfiguration()
        configuration.iceServers = []
        configuration.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
            throw MediaSessionError.peerConnectionUnavailable
        }
        peerConnection = peer

        let source = factory.audioSource(with: constraints)
        let track = factory.audioTrack(with: source, trackId: "webspeak-microphone")
        track.isEnabled = !muted
        microphoneTrack = track
        guard peer.add(track, streamIds: ["webspeak-audio"]) != nil else {
            throw MediaSessionError.microphoneTrackUnavailable
        }

        onStatusChange?(muted ? "正在建立 WebRTC；麥克風保持靜音" : "正在建立 WebRTC；麥克風已啟用")
        let offer = try await createOffer(for: peer, constraints: constraints)
        try await setLocalDescription(offer, on: peer)
        await waitForIceGathering(peer)
        guard !isStopped, let localDescription = peer.localDescription, !localDescription.sdp.isEmpty else {
            throw MediaSessionError.offerUnavailable
        }
        let sdp = localDescription.sdp
        logger.info("WebRTC ICE gathering finished; generatedCandidates=\(self.generatedCandidateCount, privacy: .public)")

        let payload: [String: Any] = [
            "type": "webrtcOffer",
            "payload": [
                "sdp": ["type": "offer", "sdp": sdp],
                "muted": muted,
                "accompanimentActive": false
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else { throw MediaSessionError.offerUnavailable }
        try await gatewaySocket.send(.string(text))
        logger.info("WebRTC offer sent to the gateway")
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !self.isStopped, !self.isConnected else { return }
            self.reportConnectionFailure("WebRTC 媒体连接超时；请重试或检查网关媒体设置。")
        }
    }

    func applyAnswer(_ value: Any?) async throws {
        guard let peerConnection,
              let object = value as? [String: Any],
              let type = object["type"] as? String,
              type == "answer",
              let sdp = object["sdp"] as? String,
              !sdp.isEmpty
        else {
            throw MediaSessionError.invalidAnswer
        }
        let description = RTCSessionDescription(type: .answer, sdp: sdp)
        try await setRemoteDescription(description, on: peerConnection)
        logger.info("WebRTC answer applied")
        onStatusChange?("WebRTC 信令已响应，正在等待媒体连接…")
    }

    func setMuted(_ muted: Bool) {
        microphoneTrack?.isEnabled = !muted
        logger.info("WebRTC microphone mute state changed; muted=\(muted, privacy: .public)")
        onStatusChange?(isConnected
            ? (muted ? "WebRTC 已连接；麦克风静音" : "WebRTC 已连接；麦克风已启用")
            : (muted ? "WebRTC 连接中；麦克风静音" : "WebRTC 连接中；麦克风已启用"))
    }

    func setSpeakerMuted(_ muted: Bool) {
        speakerMuted = muted
        remoteAudioTracks.forEach { $0.isEnabled = !muted }
    }

    func close() {
        guard !isStopped else { return }
        logger.info("Closing WebRTC audio session")
        isStopped = true
        isConnected = false
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        gatheringContinuation?.resume()
        gatheringContinuation = nil
        microphoneTrack?.isEnabled = false
        microphoneTrack = nil
        remoteAudioTracks.removeAll()
        peerConnection?.delegate = nil
        peerConnection?.close()
        peerConnection = nil
        onStatusChange?("語音媒體已停止")

        let rtcAudioSession = RTCAudioSession.sharedInstance()
        rtcAudioSession.lockForConfiguration()
        defer { rtcAudioSession.unlockForConfiguration() }
        try? rtcAudioSession.setActive(false)
    }

    private func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configureAudioSession() throws {
        let rtcAudioSession = RTCAudioSession.sharedInstance()
        rtcAudioSession.lockForConfiguration()
        defer { rtcAudioSession.unlockForConfiguration() }
        try rtcAudioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        try rtcAudioSession.setActive(true)
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputTypes = route.inputs.map(\.portType.rawValue).joined(separator: ",")
        let outputTypes = route.outputs.map(\.portType.rawValue).joined(separator: ",")
        logger.info("Audio session active; inputTypes=\(inputTypes, privacy: .public) outputTypes=\(outputTypes, privacy: .public)")
    }

    private func createOffer(for peer: RTCPeerConnection, constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peer.offer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: MediaSessionError.offerUnavailable)
                }
            }
        }
    }

    private func setLocalDescription(_ description: RTCSessionDescription, on peer: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func setRemoteDescription(_ description: RTCSessionDescription, on peer: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func waitForIceGathering(_ peer: RTCPeerConnection) async {
        if peer.iceGatheringState == .complete { return }
        await withCheckedContinuation { continuation in
            gatheringContinuation = continuation
            Task { [weak self, weak peer] in
                for _ in 0 ..< 50 {
                    guard let self, !self.isStopped, let peer else { break }
                    if peer.iceGatheringState == .complete { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard let self, let continuation = self.gatheringContinuation else { return }
                self.gatheringContinuation = nil
                continuation.resume()
            }
        }
    }

    private func reportConnectionFailure(_ detail: String) {
        guard !isStopped, !didReportFailure else { return }
        logger.error("WebRTC connection failure: \(detail, privacy: .private)")
        didReportFailure = true
        isConnected = false
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        onStatusChange?(detail)
        onConnectionFailure?(detail)
    }

    private enum MediaSessionError: LocalizedError {
        case stopped
        case microphonePermissionDenied
        case peerConnectionUnavailable
        case microphoneTrackUnavailable
        case offerUnavailable
        case invalidAnswer

        var errorDescription: String? {
            switch self {
            case .stopped: "語音媒體工作階段已停止。"
            case .microphonePermissionDenied: "iOS 未授予麥克風權限；可在系統設定中允許後重試。"
            case .peerConnectionUnavailable: "無法建立 WebRTC 語音連線。"
            case .microphoneTrackUnavailable: "無法建立麥克風音軌。"
            case .offerUnavailable: "無法完成 WebRTC 語音協商。"
            case .invalidAnswer: "網關返回的 WebRTC 響應無效。"
            }
        }
    }
}

extension WebRTCAudioSession: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("WebRTC ICE connection state changed; state=\(String(describing: newState), privacy: .public)")
            switch newState {
            case .connected, .completed:
                self.isConnected = true
                self.connectionTimeoutTask?.cancel()
                self.connectionTimeoutTask = nil
                self.onStatusChange?("WebRTC 語音已連線")
            case .failed:
                self.reportConnectionFailure("WebRTC 媒体直连失败；请重试或检查网络。")
            case .disconnected:
                self.isConnected = false
                self.onStatusChange?("WebRTC 語音連線中斷")
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        guard newState == .complete else { return }
        Task { @MainActor [weak self] in
            guard let self, let continuation = self.gatheringContinuation else { return }
            self.gatheringContinuation = nil
            continuation.resume()
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.generatedCandidateCount += 1
            if self.generatedCandidateCount == 1 || self.generatedCandidateCount.isMultiple(of: 10) {
                self.logger.debug("WebRTC ICE candidates generated; count=\(self.generatedCandidateCount, privacy: .public)")
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        if newState == .failed {
            Task { @MainActor [weak self] in
                self?.reportConnectionFailure("WebRTC 媒体连接失败。")
            }
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams mediaStreams: [RTCMediaStream]
    ) {
        let track = rtpReceiver.track as? RTCAudioTrack
        Task { @MainActor [weak self, weak track] in
            guard let self, let track else { return }
            if !self.remoteAudioTracks.contains(where: { $0 === track }) {
                self.remoteAudioTracks.append(track)
            }
            track.isEnabled = !self.speakerMuted
            self.logger.info("Remote WebRTC audio receiver track arrived; enabled=\(!self.speakerMuted, privacy: .public)")
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {}
}
