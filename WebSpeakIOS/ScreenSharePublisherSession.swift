import Foundation
import WebRTC
import Combine
import os

@MainActor
class ScreenSharePublisherSession: NSObject, ObservableObject {
    @Published fileprivate(set) var status = "此设备无法启动系统屏幕采集。"
    @Published fileprivate(set) var isCapturing = false

    let stream: ScreenShareStream
    let gatewaySocket: URLSessionWebSocketTask
    let iceServers: [GatewayIceServer]

    init(stream: ScreenShareStream, iceServers: [GatewayIceServer], gatewaySocket: URLSessionWebSocketTask) {
        self.stream = stream
        self.iceServers = iceServers
        self.gatewaySocket = gatewaySocket
        super.init()
    }

    static func make(stream: ScreenShareStream, iceServers: [GatewayIceServer], gatewaySocket: URLSessionWebSocketTask) -> ScreenSharePublisherSession {
        #if canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            return ScreenCaptureKitPublisherSession(stream: stream, iceServers: iceServers, gatewaySocket: gatewaySocket)
        }
        #endif
        return ScreenSharePublisherSession(stream: stream, iceServers: iceServers, gatewaySocket: gatewaySocket)
    }

    func presentSystemPicker() {}
    func viewerJoined(peerID: String) {}
    func viewerLeft(peerID: String) {}
    func receiveSignal(from peerID: String, signal: [String: Any]) {}

    func stop(sendGatewayStop: Bool = true) {
        if sendGatewayStop {
            let message: [String: Any] = ["type": "screenShareStop", "streamId": stream.streamId]
            if let data = try? JSONSerialization.data(withJSONObject: message),
               let text = String(data: data, encoding: .utf8)
            {
                Task { [gatewaySocket] in try? await gatewaySocket.send(.string(text)) }
            }
        }
        isCapturing = false
        status = "屏幕共享已停止"
    }
}

#if canImport(ScreenCaptureKit)
import CoreMedia
import CoreVideo
import ScreenCaptureKit

@available(iOS 27.0, *)
@MainActor
final class ScreenCaptureKitPublisherSession: ScreenSharePublisherSession, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate, RTCPeerConnectionDelegate {
    private let factory: RTCPeerConnectionFactory = {
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        encoderFactory.preferredCodec = RTCVideoCodecInfo(name: "VP8")
        return RTCPeerConnectionFactory(
            encoderFactory: encoderFactory,
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()
    private var captureStream: SCStream?
    private var videoSource: RTCVideoSource?
    private var videoCapturer: RTCVideoCapturer?
    private var videoTrack: RTCVideoTrack?
    private var peers: [String: RTCPeerConnection] = [:]
    private var pendingCandidates: [String: [RTCIceCandidate]] = [:]
    private var pendingIncomingSignals: [String: [[String: Any]]] = [:]
    private var pendingViewerPeerIDs: Set<String> = []
    private var localDescriptionsSignaled: Set<String> = []
    private var pendingLocalCandidates: [String: [RTCIceCandidate]] = [:]
    private var gatewaySendTask: Task<Void, Never>?
    private var isStopped = false
    private var capturedFrameCount = 0
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.echosixhiya.webspeak.ios",
        category: "ScreenShare"
    )

    override init(stream: ScreenShareStream, iceServers: [GatewayIceServer], gatewaySocket: URLSessionWebSocketTask) {
        super.init(stream: stream, iceServers: iceServers, gatewaySocket: gatewaySocket)
    }

    override func presentSystemPicker() {
        guard !isStopped else { return }
        logger.info("Presenting the system screen-sharing picker")
        let picker = SCContentSharingPicker.shared
        picker.add(self)
        picker.isActive = true
        picker.present(using: .display)
        status = "請在 iOS 系統選擇要共享的畫面；目前僅傳送畫面，不含系統音訊。"
    }

    override func viewerJoined(peerID: String) {
        guard !isStopped, !peerID.isEmpty else { return }
        if peers[peerID] != nil { return }
        logger.info("Screen-share viewer joined; activePeerCount=\(self.peers.count + 1, privacy: .public)")
        guard let videoTrack else {
            pendingViewerPeerIDs.insert(peerID)
            status = "系統尚未開始畫面擷取；已暫存觀看者連線。"
            return
        }
        guard let peer = makePeer(for: peerID, track: videoTrack) else {
            status = "無法建立觀看者的 WebRTC 連線。"
            return
        }
        let queuedSignals = pendingIncomingSignals.removeValue(forKey: peerID) ?? []
        for signal in queuedSignals { receiveSignal(from: peerID, signal: signal) }

        if peerID.hasPrefix("ts-viewer-") {
            Task { [weak self, weak peer] in
                guard let self, let peer else { return }
                do {
                    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                    let offer = try await self.createOffer(for: peer, constraints: constraints)
                    try await self.setLocalDescription(offer, on: peer)
                    guard let local = peer.localDescription, !local.sdp.isEmpty else {
                        throw PublisherError.invalidSessionDescription
                    }
                    self.sendSignal(to: peerID, signal: ["kind": "offer", "sdp": local.sdp])
                } catch {
                    self.status = "無法向 TeamSpeak 觀看者發起連線：\(error.localizedDescription)"
                    self.closePeer(peerID)
                }
            }
        }
    }

    override func viewerLeft(peerID: String) {
        pendingViewerPeerIDs.remove(peerID)
        closePeer(peerID)
    }

    override func receiveSignal(from peerID: String, signal: [String: Any]) {
        guard !isStopped, let kind = signal["kind"] as? String else { return }
        logger.debug("Screen-share signal received; kind=\(kind, privacy: .public)")
        if kind == "close" {
            closePeer(peerID)
            return
        }

        if peers[peerID] == nil {
            guard kind == "offer" || kind == "iceCandidate" else { return }
            guard let videoTrack else {
                pendingViewerPeerIDs.insert(peerID)
                guard pendingIncomingSignals[peerID, default: []].count < 256 else { return }
                pendingIncomingSignals[peerID, default: []].append(signal)
                return
            }
            guard makePeer(for: peerID, track: videoTrack) != nil else {
                status = "無法建立觀看者的 WebRTC 連線。"
                return
            }
        }
        guard let peer = peers[peerID] else { return }

        switch kind {
        case "iceCandidate":
            guard let candidateText = signal["candidate"] as? String, !candidateText.isEmpty else { return }
            let candidate = RTCIceCandidate(
                sdp: candidateText,
                sdpMLineIndex: Int32((signal["sdpMLineIndex"] as? NSNumber)?.intValue ?? 0),
                sdpMid: signal["sdpMid"] as? String
            )
            if peer.remoteDescription == nil {
                pendingCandidates[peerID, default: []].append(candidate)
            } else {
                add(candidate, to: peer, peerID: peerID)
            }

        case "offer":
            guard let sdp = signal["sdp"] as? String, !sdp.isEmpty else { return }
            let offer = RTCSessionDescription(type: .offer, sdp: sdp)
            Task { [weak self, weak peer] in
                guard let self, let peer else { return }
                do {
                    try await self.setRemoteDescription(offer, on: peer)
                    await self.flushCandidates(for: peerID, on: peer)
                    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
                    let answer = try await self.createAnswer(for: peer, constraints: constraints)
                    try await self.setLocalDescription(answer, on: peer)
                    guard let local = peer.localDescription, !local.sdp.isEmpty else {
                        throw PublisherError.invalidSessionDescription
                    }
                    self.sendSignal(to: peerID, signal: ["kind": "answer", "sdp": local.sdp])
                } catch {
                    self.status = "無法回覆觀看端的 WebRTC offer：\(error.localizedDescription)"
                    self.closePeer(peerID)
                }
            }

        case "answer":
            guard let sdp = signal["sdp"] as? String, !sdp.isEmpty else { return }
            let answer = RTCSessionDescription(type: .answer, sdp: sdp)
            Task { [weak self, weak peer] in
                guard let self, let peer else { return }
                do {
                    try await self.setRemoteDescription(answer, on: peer)
                    await self.flushCandidates(for: peerID, on: peer)
                } catch {
                    self.status = "觀看端的 WebRTC answer 無效。"
                    self.closePeer(peerID)
                }
            }

        default:
            break
        }
    }

    override func stop(sendGatewayStop: Bool = true) {
        guard !isStopped else { return }
        logger.info("Stopping screen-share publisher; capturedFrames=\(self.capturedFrameCount, privacy: .public) peers=\(self.peers.count, privacy: .public)")
        isStopped = true
        if sendGatewayStop {
            sendGatewayMessage(["type": "screenShareStop", "streamId": stream.streamId])
        }
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        let currentCapture = captureStream
        captureStream = nil
        if currentCapture?.isCapturing == true {
            currentCapture?.stopCapture()
        }
        isCapturing = false
        videoTrack = nil
        videoCapturer = nil
        videoSource = nil
        for peerID in Array(peers.keys) { closePeer(peerID) }
        pendingCandidates.removeAll()
        pendingIncomingSignals.removeAll()
        pendingViewerPeerIDs.removeAll()
        localDescriptionsSignaled.removeAll()
        pendingLocalCandidates.removeAll()
        status = "屏幕共享已停止"
    }

    private func startCapture(using filter: SCContentFilter) {
        guard !isStopped, captureStream == nil else { return }
        do {
            let configuration = SCStreamConfiguration()
            let pixelScale = CGFloat(filter.pointPixelScale)
            let sourceWidth = max(2, Int(filter.contentRect.width * pixelScale))
            let sourceHeight = max(2, Int(filter.contentRect.height * pixelScale))
            let downscale = min(1, min(1920.0 / Double(sourceWidth), 1080.0 / Double(sourceHeight)))
            configuration.width = max(2, Int(Double(sourceWidth) * downscale) / 2 * 2)
            configuration.height = max(2, Int(Double(sourceHeight) * downscale) / 2 * 2)
            configuration.capturesAudio = false

            let source = factory.videoSource(forScreenCast: true)
            let capturer = RTCVideoCapturer(delegate: source)
            let track = factory.videoTrack(with: source, trackId: "webspeak-screen-\(stream.streamId)")
            videoSource = source
            videoCapturer = capturer
            videoTrack = track

            let capture = SCStream(filter: filter, configuration: configuration, delegate: self)
            try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.echosixhiya.webspeak.screen-capture"))
            captureStream = capture
            Task { [weak self, weak capture] in
                guard let self, let capture else { return }
                do {
                    try await capture.startCapture()
                    guard !self.isStopped else {
                        try? await capture.stopCapture()
                        return
                    }
                    self.isCapturing = true
                    self.status = "正在以 WebRTC P2P 共享畫面；媒體不經網關中繼。"
                    self.logger.info("Screen capture started; width=\(configuration.width, privacy: .public) height=\(configuration.height, privacy: .public)")
                    let pendingPeerIDs = self.pendingViewerPeerIDs
                    self.pendingViewerPeerIDs.removeAll()
                    for peerID in pendingPeerIDs { self.viewerJoined(peerID: peerID) }
                } catch {
                    let value = error as NSError
                    self.logger.error("Screen capture start failed; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
                    self.status = "系統無法開始畫面擷取：\(error.localizedDescription)"
                    self.stop()
                }
            }
        } catch {
            let value = error as NSError
            logger.error("Screen capture setup failed; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
            status = "無法初始化系統畫面擷取：\(error.localizedDescription)"
            stop()
        }
    }

    private func makePeer(for peerID: String, track: RTCVideoTrack) -> RTCPeerConnection? {
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
        guard let peer = factory.peerConnection(with: configuration, constraints: constraints, delegate: self),
              peer.add(track, streamIds: ["webspeak-screen-\(stream.streamId)"]) != nil
        else {
            return nil
        }
        preferVP8ForScreenShare(on: peer)
        peers[peerID] = peer
        return peer
    }

    private func preferVP8ForScreenShare(on peer: RTCPeerConnection) {
        let capabilities = factory.rtpSenderCapabilities(forKind: "video").codecs
        let vp8 = capabilities.filter { $0.mimeType.caseInsensitiveCompare("video/vp8") == .orderedSame }
        guard !vp8.isEmpty,
              let transceiver = peer.transceivers.first(where: { $0.sender.track?.kind == "video" })
        else {
            logger.warning("VP8 screen-share codec preference is unavailable")
            return
        }

        let remaining = capabilities.filter { $0.mimeType.caseInsensitiveCompare("video/vp8") != .orderedSame }
        do {
            try transceiver.setCodecPreferences(vp8 + remaining, error: ())
        } catch {
            let value = error as NSError
            logger.warning("Could not apply VP8 screen-share codec preference; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
            return
        }
        logger.info("VP8 is prioritized for screen-share negotiation")
    }

    private func closePeer(_ peerID: String) {
        peers.removeValue(forKey: peerID)?.close()
        pendingCandidates.removeValue(forKey: peerID)
        pendingIncomingSignals.removeValue(forKey: peerID)
        pendingViewerPeerIDs.remove(peerID)
        localDescriptionsSignaled.remove(peerID)
        pendingLocalCandidates.removeValue(forKey: peerID)
    }

    private func sendSignal(to peerID: String, signal: [String: Any]) {
        if let kind = signal["kind"] as? String, kind == "offer" || kind == "answer" {
            logger.info("Screen-share session description sent; kind=\(kind, privacy: .public)")
        }
        sendGatewayMessage([
            "type": "screenShareSignal",
            "streamId": stream.streamId,
            "targetPeerId": peerID,
            "signal": signal
        ])
        if let kind = signal["kind"] as? String, kind == "offer" || kind == "answer" {
            localDescriptionsSignaled.insert(peerID)
            let candidates = pendingLocalCandidates.removeValue(forKey: peerID) ?? []
            for candidate in candidates { sendCandidate(candidate, to: peerID) }
        }
    }

    private func queueLocalCandidate(_ candidate: RTCIceCandidate, for peerID: String) {
        guard peers[peerID] != nil else { return }
        guard localDescriptionsSignaled.contains(peerID) else {
            guard pendingLocalCandidates[peerID, default: []].count < 256 else { return }
            pendingLocalCandidates[peerID, default: []].append(candidate)
            return
        }
        sendCandidate(candidate, to: peerID)
    }

    private func sendCandidate(_ candidate: RTCIceCandidate, to peerID: String) {
        sendSignal(to: peerID, signal: [
            "kind": "iceCandidate",
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid as Any? ?? NSNull(),
            "sdpMLineIndex": candidate.sdpMLineIndex
        ])
    }

    private func sendGatewayMessage(_ message: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8)
        else {
            return
        }
        let previous = gatewaySendTask
        gatewaySendTask = Task { [weak self, gatewaySocket] in
            await previous?.value
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
                    continuation.resume(throwing: PublisherError.invalidSessionDescription)
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
                    continuation.resume(throwing: PublisherError.invalidSessionDescription)
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

    private func add(_ candidate: RTCIceCandidate, to peer: RTCPeerConnection, peerID: String) {
        peer.add(candidate) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.status = "觀看端 ICE 候選無法加入：\(error.localizedDescription)"
                self?.closePeer(peerID)
            }
        }
    }

    private func flushCandidates(for peerID: String, on peer: RTCPeerConnection) async {
        let candidates = pendingCandidates.removeValue(forKey: peerID) ?? []
        for candidate in candidates {
            add(candidate, to: peer, peerID: peerID)
        }
    }

    private enum PublisherError: LocalizedError {
        case invalidSessionDescription

        var errorDescription: String? { "無法建立屏幕共享 WebRTC session description。" }
    }
}

@available(iOS 27.0, *)
extension ScreenCaptureKitPublisherSession {
    nonisolated func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            self?.logger.info("System screen-sharing picker returned a selection")
            self?.startCapture(using: filter)
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in
            self?.logger.info("System screen-sharing picker was cancelled")
            self?.stop()
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor [weak self] in
            let value = error as NSError
            self?.logger.error("System screen-sharing picker failed; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
            self?.status = "無法開啟系統屏幕共享選擇器：\(error.localizedDescription)"
            self?.stop()
        }
    }
}

@available(iOS 27.0, *)
extension ScreenCaptureKitPublisherSession {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }
        let pixelBuffer = RTCCVPixelBuffer(pixelBuffer: imageBuffer)
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampNs = CMTimeConvertScale(time, timescale: 1_000_000_000, method: .default).value
        let frame = RTCVideoFrame(buffer: pixelBuffer, rotation: ._0, timeStampNs: timestampNs)
        Task { @MainActor [weak self] in
            guard let self, !self.isStopped, let videoSource = self.videoSource, let videoCapturer = self.videoCapturer else { return }
            videoSource.capturer(videoCapturer, didCapture: frame)
            self.capturedFrameCount += 1
            if self.capturedFrameCount == 1 || self.capturedFrameCount.isMultiple(of: 150) {
                self.logger.debug("Screen capture frames received; count=\(self.capturedFrameCount, privacy: .public)")
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, !self.isStopped else { return }
            self.status = "系統停止了屏幕擷取：\(error.localizedDescription)"
            self.stop()
        }
    }
}

@available(iOS 27.0, *)
extension ScreenCaptureKitPublisherSession {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor [weak self, weak peerConnection] in
            guard let self, let peerConnection,
                  let peerID = self.peers.first(where: { $0.value === peerConnection })?.key
            else {
                return
            }
            self.queueLocalCandidate(candidate, for: peerID)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self, weak peerConnection] in
            guard let self, let peerConnection,
                  let peerID = self.peers.first(where: { $0.value === peerConnection })?.key
            else {
                return
            }
            switch newState {
            case .connected, .completed:
                self.logger.info("Screen-share ICE connected; activePeers=\(self.peers.count, privacy: .public)")
                self.status = "畫面正在向 \(peerID) 直接傳送"
            case .failed:
                self.logger.error("Screen-share ICE connection failed; activePeers=\(self.peers.count, privacy: .public)")
                self.status = "與 \(peerID) 建立 P2P 連線失敗。"
                self.closePeer(peerID)
            case .disconnected:
                self.logger.warning("Screen-share ICE connection disconnected; activePeers=\(self.peers.count, privacy: .public)")
                self.status = "與 \(peerID) 的畫面連線中斷。"
            default:
                break
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        guard newState == .failed else { return }
        Task { @MainActor [weak self, weak peerConnection] in
            guard let self, let peerConnection,
                  let peerID = self.peers.first(where: { $0.value === peerConnection })?.key
            else {
                return
            }
            self.closePeer(peerID)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    nonisolated func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd rtpReceiver: RTCRtpReceiver,
        streams mediaStreams: [RTCMediaStream]
    ) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {}
}
#endif
