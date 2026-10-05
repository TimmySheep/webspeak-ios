import Combine
import Foundation
import WebRTC
import os

@MainActor
final class ScreenShareViewerSession: NSObject, ObservableObject {
    @Published private(set) var videoTrack: RTCVideoTrack?
    @Published private(set) var audioTrack: RTCAudioTrack?
    @Published private(set) var audioVolume = 1.0
    @Published private(set) var status = "正在建立 P2P 連線…"

    let stream: ScreenShareStream

    private let gatewaySocket: URLSessionWebSocketTask
    private let iceServers: [GatewayIceServer]
    private let factory = RTCPeerConnectionFactory()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.echosixhiya.webspeak.ios",
        category: "ScreenShare"
    )
    private var peerConnection: RTCPeerConnection?
    private var pendingCandidates: [RTCIceCandidate] = []
    private var isStopped = false

    init(stream: ScreenShareStream, iceServers: [GatewayIceServer], gatewaySocket: URLSessionWebSocketTask) {
        self.stream = stream
        self.iceServers = iceServers
        self.gatewaySocket = gatewaySocket
    }

    func start() async throws {
        guard !isStopped else { throw ViewerError.stopped }
        guard peerConnection == nil else { return }
        logger.info("Starting screen-share viewer; source=\(self.stream.source, privacy: .public) audio=\(self.stream.audio, privacy: .public)")

        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers.map { server in
            RTCIceServer(
                urlStrings: server.urls,
                username: server.username ?? "",
                credential: server.credential ?? ""
            )
        }
        configuration.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
            throw ViewerError.peerConnectionUnavailable
        }
        peerConnection = peer

        let videoInit = RTCRtpTransceiverInit()
        videoInit.direction = .recvOnly
        guard peer.addTransceiver(of: .video, init: videoInit) != nil else {
            throw ViewerError.videoReceiverUnavailable
        }
        if stream.audio {
            let audioInit = RTCRtpTransceiverInit()
            audioInit.direction = .recvOnly
            _ = peer.addTransceiver(of: .audio, init: audioInit)
        }

        if stream.source == "browser" {
            let offer = try await createOffer(for: peer, constraints: constraints)
            try await setLocalDescription(offer, on: peer)
            guard !isStopped, let local = peer.localDescription, !local.sdp.isEmpty else {
                throw ViewerError.offerUnavailable
            }
            sendSignal(["kind": "offer", "sdp": local.sdp])
        } else {
            status = "等待 TeamSpeak 共享端發起協商…"
        }
    }

    func receiveSignal(_ value: [String: Any]) {
        guard !isStopped,
              let kind = value["kind"] as? String
        else {
            return
        }
        logger.debug("Screen-share signal received; kind=\(kind, privacy: .public)")

        switch kind {
        case "iceCandidate":
            guard let rawCandidate = value["candidate"] as? String, !rawCandidate.isEmpty else { return }
            let candidate = RTCIceCandidate(
                sdp: rawCandidate,
                sdpMLineIndex: Int32((value["sdpMLineIndex"] as? NSNumber)?.intValue ?? 0),
                sdpMid: value["sdpMid"] as? String
            )
            guard let peerConnection else { return }
            if peerConnection.remoteDescription == nil {
                pendingCandidates.append(candidate)
            } else {
                add(candidate, to: peerConnection)
            }

        case "answer":
            guard stream.source == "browser",
                  let sdp = value["sdp"] as? String,
                  !sdp.isEmpty,
                  let peerConnection
            else {
                return
            }
            let answer = RTCSessionDescription(type: .answer, sdp: sdp)
            Task { [weak self, weak peerConnection] in
                guard let self, let peerConnection else { return }
                do {
                    try await self.setRemoteDescription(answer, on: peerConnection)
                    await self.flushPendingCandidates(on: peerConnection)
                    self.status = "已連接共享端，等待畫面…"
                } catch {
                    let value = error as NSError
                    self.logger.error("Screen-share answer application failed; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
                    self.status = "共享端返回的協商響應無效。"
                }
            }

        case "offer":
            guard stream.source == "teamspeak",
                  let sdp = value["sdp"] as? String,
                  !sdp.isEmpty,
                  let peerConnection
            else {
                return
            }
            let offer = RTCSessionDescription(type: .offer, sdp: sdp)
            Task { [weak self, weak peerConnection] in
                guard let self, let peerConnection else { return }
                do {
                    try await self.setRemoteDescription(offer, on: peerConnection)
                    await self.flushPendingCandidates(on: peerConnection)
                    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                    let answer = try await self.createAnswer(for: peerConnection, constraints: constraints)
                    try await self.setLocalDescription(answer, on: peerConnection)
                    guard let local = peerConnection.localDescription, !local.sdp.isEmpty else {
                        throw ViewerError.offerUnavailable
                    }
                    self.sendSignal(["kind": "answer", "sdp": local.sdp])
                    self.status = "已回复 TeamSpeak 共享端，等待畫面…"
                } catch {
                    let value = error as NSError
                    self.logger.error("Screen-share offer handling failed; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
                    self.status = "無法完成 TeamSpeak 共享協商：\(error.localizedDescription)"
                }
            }

        case "close":
            close(sendLeave: false)

        default:
            break
        }
    }

    func close(sendLeave: Bool = true) {
        guard !isStopped else { return }
        logger.info("Stopping screen-share viewer; videoTrackAvailable=\(self.videoTrack != nil, privacy: .public)")
        isStopped = true
        if sendLeave {
            sendGatewayMessage(["type": "screenShareLeave", "streamId": stream.streamId])
        }
        videoTrack = nil
        audioTrack = nil
        pendingCandidates.removeAll()
        peerConnection?.delegate = nil
        peerConnection?.close()
        peerConnection = nil
        status = "已退出共享"
    }

    func setAudioVolume(_ volume: Double) {
        let normalized = min(1, max(0, volume))
        audioVolume = normalized
        audioTrack?.source.volume = normalized
    }

    private func sendSignal(_ signal: [String: Any]) {
        if let kind = signal["kind"] as? String, kind == "offer" || kind == "answer" {
            logger.info("Screen-share session description sent; kind=\(kind, privacy: .public)")
        }
        sendGatewayMessage([
            "type": "screenShareSignal",
            "streamId": stream.streamId,
            "targetPeerId": stream.ownerPeerId,
            "signal": signal
        ])
    }

    private func sendGatewayMessage(_ message: [String: Any]) {
        guard !isStopped || message["type"] as? String == "screenShareLeave",
              JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8)
        else {
            return
        }
        Task { [weak self, gatewaySocket] in
            do {
                try await gatewaySocket.send(.string(text))
            } catch {
                let value = error as NSError
                self?.logger.error("Screen-share signaling send failed; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
            }
        }
    }

    private func createOffer(for peer: RTCPeerConnection, constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peer.offer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: ViewerError.offerUnavailable)
                }
            }
        }
    }

    private func createAnswer(for peer: RTCPeerConnection, constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peer.answer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: ViewerError.answerUnavailable)
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

    private func add(_ candidate: RTCIceCandidate, to peer: RTCPeerConnection) {
        peer.add(candidate) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.status = "部分 ICE 候選無法加入：\(error.localizedDescription)"
            }
        }
    }

    private func flushPendingCandidates(on peer: RTCPeerConnection) async {
        let candidates = pendingCandidates
        pendingCandidates.removeAll()
        for candidate in candidates {
            add(candidate, to: peer)
        }
    }

    private enum ViewerError: LocalizedError {
        case stopped
        case peerConnectionUnavailable
        case videoReceiverUnavailable
        case offerUnavailable
        case answerUnavailable

        var errorDescription: String? {
            switch self {
            case .stopped: "屏幕共享觀看已停止。"
            case .peerConnectionUnavailable: "無法建立屏幕共享 P2P 連接。"
            case .videoReceiverUnavailable: "無法建立屏幕畫面接收器。"
            case .offerUnavailable: "無法建立屏幕共享 SDP offer。"
            case .answerUnavailable: "無法建立屏幕共享 SDP answer。"
            }
        }
    }
}

extension ScreenShareViewerSession: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let track = stream.videoTracks.first
        Task { @MainActor [weak self] in
            guard let self, !self.isStopped, let track else { return }
            self.videoTrack = track
            self.logger.info("Remote screen-share video track arrived")
            self.status = "正在接收屏幕畫面"
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        Task { @MainActor [weak self] in
            self?.videoTrack = nil
        }
    }

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, !self.isStopped else { return }
            switch newState {
            case .connected, .completed:
                self.logger.info("Screen-share viewer ICE connected")
                self.status = self.videoTrack == nil ? "P2P 已連接，等待畫面…" : "正在接收屏幕畫面"
            case .failed:
                self.logger.error("Screen-share viewer ICE connection failed")
                self.status = "無法與共享端建立 P2P 連線；網關不會中繼畫面。"
            case .disconnected:
                self.logger.warning("Screen-share viewer ICE disconnected")
                self.status = "屏幕共享 P2P 連線中斷。"
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let signal: [String: Any] = [
            "kind": "iceCandidate",
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid as Any? ?? NSNull(),
            "sdpMLineIndex": candidate.sdpMLineIndex
        ]
        Task { @MainActor [weak self] in
            self?.sendSignal(signal)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        if newState == .failed {
            Task { @MainActor [weak self] in
                self?.status = "屏幕共享 P2P 連線失敗。"
            }
        }
    }

    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams mediaStreams: [RTCMediaStream]
    ) {
        let receivedTrack = rtpReceiver.track
        Task { @MainActor [weak self] in
            guard let self, !self.isStopped else { return }
            if let track = receivedTrack as? RTCVideoTrack {
                self.videoTrack = track
                self.logger.info("Remote screen-share video receiver track arrived")
                self.status = "正在接收屏幕画面"
            } else if let track = receivedTrack as? RTCAudioTrack {
                self.audioTrack = track
                track.source.volume = self.audioVolume
                self.status = self.videoTrack == nil ? "P2P 已连接，等待画面与共享音频…" : "正在接收屏幕画面与共享音频"
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        guard let track = rtpReceiver.track as? RTCAudioTrack else { return }
        Task { @MainActor [weak self] in
            guard let self, self.audioTrack === track else { return }
            self.audioTrack = nil
        }
    }

}
