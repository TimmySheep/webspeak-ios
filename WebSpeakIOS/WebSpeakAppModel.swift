import Combine
import Foundation
import os
import UIKit
import UserNotifications

@MainActor
final class WebSpeakAppModel: ObservableObject {
    @Published var gatewayAddress: String {
        didSet {
            UserDefaults.standard.set(gatewayAddress, forKey: "webspeak.gateway")
            if oldValue != gatewayAddress {
                publicConfigRequestID = UUID()
                configLoading = false
                publicConfig = nil
                configError = nil
                configuredGatewayKey = nil
            }
        }
    }
    @Published var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: "webspeak.nickname") }
    }
    @Published var serverTarget = ""
    @Published var channelName = ""
    @Published var serverPassword = ""
    @Published var inviteToken = ""
    @Published var selectedLanguageCode: String = UserDefaults.standard.string(forKey: "webspeak.language") ?? "system" {
        didSet {
            UserDefaults.standard.set(selectedLanguageCode, forKey: "webspeak.language")
            refreshVoiceLiveActivity()
        }
    }
    @Published var rememberIdentity = UserDefaults.standard.bool(forKey: "webspeak.rememberIdentity") {
        didSet { UserDefaults.standard.set(rememberIdentity, forKey: "webspeak.rememberIdentity") }
    }
    @Published var selectedRelayID = ""
    @Published private(set) var recentConnections: [RecentConnectionRecord] = WebSpeakAppModel.loadRecentConnections()

    @Published private(set) var publicConfig: GatewayPublicConfig?
    @Published private(set) var configLoading = false
    @Published private(set) var configError: String?
    @Published private(set) var phase: VoiceConnectionPhase = .disconnected {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var connectionError: String?
    @Published private(set) var operationError: String?
    @Published private(set) var channels: [VoiceChannel] = [] {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var members: [VoiceMember] = [] {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var chatMessages: [ChatMessage] = []
    @Published private(set) var serverEvents: [ServerEvent] = []
    @Published private(set) var screenShares: [ScreenShareStream] = []
    @Published private(set) var activeScreenShare: ScreenShareStream? {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var screenShareViewerSession: ScreenShareViewerSession? {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var screenSharePublisherSession: ScreenSharePublisherSession? {
        didSet {
            screenSharePublisherObservation?.cancel()
            screenSharePublisherObservation = nil
            if let session = screenSharePublisherSession {
                screenSharePublisherObservation = session.$isCapturing
                    .removeDuplicates()
                    .sink { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.refreshVoiceLiveActivity()
                        }
                    }
            }
            refreshVoiceLiveActivity()
        }
    }
    @Published private(set) var isScreenShareStarting = false {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var speakingClientIDs: Set<Int> = []
    @Published private(set) var memberVolumes: [Int: Double] = [:]
    @Published private(set) var savedMemberVolumesByUID: [String: Double] = UserDefaults.standard.object(forKey: "webspeak.memberVolumesByUID") as? [String: Double] ?? [:]
    @Published private(set) var whisperTargetIDs: Set<Int> = []
    @Published private(set) var whisperActive = false
    @Published private(set) var isWhisperPushToTalkActive = false
    @Published private(set) var isWhisperPushToTalkBusy = false {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var isAway = false
    @Published private(set) var awayMessage = ""
    @Published private(set) var isVoiceMediaStarting = false {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var isVoiceMediaConnected = false {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var canEnableMicrophone = false {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var microphoneInputLevel = 0.0
    @Published private(set) var isPushToTalkActive = false {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var microphoneControlMode: MicrophoneControlMode = {
        let rawValue = UserDefaults.standard.string(forKey: "webspeak.microphoneControlMode") ?? ""
        return MicrophoneControlMode(rawValue: rawValue) ?? .toggle
    }() {
        didSet { refreshVoiceLiveActivity() }
    }
    @Published private(set) var gatewayWebRTCAvailable = false
    @Published var voiceActivityDetectionEnabled: Bool = UserDefaults.standard.object(forKey: "webspeak.voxEnabled") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(voiceActivityDetectionEnabled, forKey: "webspeak.voxEnabled")
            legacyVoiceSession?.setVoiceActivityDetection(enabled: voiceActivityDetectionEnabled, threshold: voiceActivityThreshold)
        }
    }
    @Published var voiceActivityThreshold: Double = min(
        0.08,
        max(0.001, UserDefaults.standard.object(forKey: "webspeak.voxThreshold") as? Double ?? 0.008)
    ) {
        didSet {
            voiceActivityThreshold = min(0.08, max(0.001, voiceActivityThreshold))
            UserDefaults.standard.set(voiceActivityThreshold, forKey: "webspeak.voxThreshold")
            legacyVoiceSession?.setVoiceActivityDetection(enabled: voiceActivityDetectionEnabled, threshold: voiceActivityThreshold)
        }
    }
    @Published var noiseSuppressionEnabled: Bool = UserDefaults.standard.object(forKey: "webspeak.noiseSuppression") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(noiseSuppressionEnabled, forKey: "webspeak.noiseSuppression")
            legacyVoiceSession?.setNoiseSuppressionEnabled(noiseSuppressionEnabled)
        }
    }
    @Published var pokeNotificationsEnabled: Bool = UserDefaults.standard.bool(forKey: "webspeak.pokeNotifications")
    @Published private(set) var microphoneMuted: Bool = (UserDefaults.standard.object(forKey: "webspeak.microphoneMuted") as? Bool) ?? true {
        didSet {
            UserDefaults.standard.set(microphoneMuted, forKey: "webspeak.microphoneMuted")
            refreshVoiceLiveActivity()
        }
    }
    @Published private(set) var speakerMuted: Bool = UserDefaults.standard.bool(forKey: "webspeak.speakerMuted") {
        didSet {
            UserDefaults.standard.set(speakerMuted, forKey: "webspeak.speakerMuted")
            refreshVoiceLiveActivity()
        }
    }
    @Published private(set) var localClientID = 0
    @Published private(set) var mediaStatus = "语音媒体尚未连接"
    @Published private(set) var browserRoundTripMs: Int?
    @Published private(set) var teamSpeakLatencyMs: Int?
    @Published var selectedChatScope: ChatScope = .channel
    @Published var privateRecipientID: Int?
    @Published private(set) var channelPasswordRequest: VoiceChannel?
    @Published private(set) var channelPasswordError: String?
    @Published private(set) var isSwitchingChannel = false

    private let api = GatewayAPI()
    private let identityStore = KeychainIdentityStore()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.echosixhiya.webspeak.ios",
        category: "WebSpeak"
    )
    private let voiceLiveActivityController = VoiceSessionLiveActivityController()
    private var voiceLiveActivitySessionID: String?
    private var screenSharePublisherObservation: AnyCancellable?
    private var webSocket: URLSessionWebSocketTask?
    private var queuedGatewayMessages: [(socket: URLSessionWebSocketTask, text: String)] = []
    private var gatewaySendTask: Task<Void, Never>?
    private var pendingGatewayCommandWaiters: [String: CheckedContinuation<Bool, Never>] = [:]
    private var gatewayCommandTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var pokeNotificationRequestID = UUID()
    private var receiveTask: Task<Void, Never>?
    private var connectTask: Task<Void, Never>?
    private var connectionAttemptID = UUID()
    private var activeGatewayURL: URL?
    private var nativeVoiceSession: WebRTCAudioSession?
    private var legacyVoiceSession: WebSocketVoiceAudioSession?
    private var screenShareIceServers: [GatewayIceServer] = []
    private var pendingRequests: [String: String] = [:]
    private var pendingChannelSwitch: (requestID: String, channel: VoiceChannel, submittedPassword: Bool)?
    private var latencyStartedAt: [String: TimeInterval] = [:]
    private var whisperPushToTalkPreviousMute: Bool?
    private var whisperPushToTalkPreviousWhisperState: Bool?
    private var whisperPushToTalkTask: Task<Void, Never>?
    private var whisperPushToTalkReleaseContinuation: CheckedContinuation<Void, Never>?
    private var configuredGatewayKey: String?
    private var publicConfigRequestID = UUID()
    private var memberVolumeSendTasks: [Int: Task<Void, Never>] = [:]
    private var pendingScreenShareStartRequestID: String?

    init() {
        gatewayAddress = UserDefaults.standard.string(forKey: "webspeak.gateway") ?? ""
        nickname = UserDefaults.standard.string(forKey: "webspeak.nickname") ?? ""
        if speakerMuted || microphoneControlMode == .pushToTalk {
            microphoneMuted = true
        }
        LiveActivityIntentBridge.shared.registerMicrophoneToggleHandler { [weak self] sessionID in
            self?.toggleMicrophoneFromLiveActivity(sessionID: sessionID)
        }
        LiveActivityIntentBridge.shared.registerSpeakerToggleHandler { [weak self] sessionID in
            self?.toggleSpeakerFromLiveActivity(sessionID: sessionID)
        }
    }

    var isBusy: Bool {
        phase == .connecting
    }

    var appLocale: Locale {
        selectedLanguageCode == "system" ? .current : Locale(identifier: selectedLanguageCode)
    }

    var webInviteShareURL: URL? {
        guard let gateway = try? api.gatewayURL(from: gatewayAddress),
              var components = URLComponents(url: gateway, resolvingAgainstBaseURL: false)
        else { return nil }
        var items: [URLQueryItem] = []
        if !inviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "invite", value: inviteToken.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if publicConfig?.accessMode == .open,
           !serverTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            items.append(URLQueryItem(name: "server", value: serverTarget.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if !channelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "channel", value: channelName.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }

    var nativeInviteShareURL: URL? {
        guard let webInviteShareURL,
              let gateway = try? api.gatewayURL(from: gatewayAddress)
        else { return nil }
        var components = URLComponents()
        components.scheme = "webspeak"
        components.host = "join"
        var items = [URLQueryItem(name: "gateway", value: gateway.absoluteString)]
        for item in URLComponents(url: webInviteShareURL, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            items.append(item)
        }
        components.queryItems = items
        return components.url
    }

    var currentChannel: VoiceChannel? {
        channels.first { $0.members?.contains(where: { $0.isSelf == true }) == true }
    }

    private func refreshVoiceLiveActivity() {
        guard phase == .connected || (phase == .reconnecting && voiceLiveActivitySessionID != nil) else {
            if let sessionID = voiceLiveActivitySessionID {
                voiceLiveActivitySessionID = nil
                voiceLiveActivityController.end(sessionID: sessionID)
            }
            return
        }

        let sessionID = voiceLiveActivitySessionID ?? UUID().uuidString
        voiceLiveActivitySessionID = sessionID

        let connectionStatus: WebSpeakVoiceLiveActivityAttributes.ContentState.ConnectionStatus
        if phase == .reconnecting {
            connectionStatus = .reconnecting
        } else if isVoiceMediaConnected {
            connectionStatus = .connected
        } else if isVoiceMediaStarting {
            connectionStatus = .connecting
        } else {
            connectionStatus = .unavailable
        }

        let screenShareStatus: WebSpeakVoiceLiveActivityAttributes.ContentState.ScreenShareStatus
        if screenSharePublisherSession?.isCapturing == true {
            screenShareStatus = .sharing
        } else if screenSharePublisherSession != nil || isScreenShareStarting {
            screenShareStatus = .preparing
        } else if screenShareViewerSession != nil || activeScreenShare != nil {
            screenShareStatus = .watching
        } else {
            screenShareStatus = .none
        }

        let state = WebSpeakVoiceLiveActivityAttributes.ContentState(
            channelName: String((currentChannel?.name ?? "TeamSpeak").prefix(64)),
            memberCount: currentChannel?.members?.count ?? members.count,
            localeIdentifier: appLocale.identifier,
            connectionStatus: connectionStatus,
            microphoneMuted: microphoneMuted,
            microphoneMode: microphoneControlMode == .pushToTalk ? .pushToTalk : .toggle,
            pushToTalkActive: isPushToTalkActive,
            microphoneToggleEnabled: microphoneControlMode == .toggle
                && phase == .connected
                && !isWhisperPushToTalkBusy
                && !isPushToTalkActive
                && (!microphoneMuted || (!speakerMuted && phase == .connected && isVoiceMediaConnected && canEnableMicrophone)),
            speakerMuted: speakerMuted,
            screenShareStatus: screenShareStatus
        )
        voiceLiveActivityController.update(sessionID: sessionID, state: state)
    }

    private func toggleMicrophoneFromLiveActivity(sessionID: String) {
        guard voiceLiveActivitySessionID == sessionID,
              phase == .connected,
              microphoneControlMode == .toggle,
              !isWhisperPushToTalkBusy,
              !isPushToTalkActive
        else { return }

        let targetMuted = !microphoneMuted
        if !targetMuted {
            guard !speakerMuted, isVoiceMediaConnected, canEnableMicrophone else { return }
        }
        setMicrophoneMuted(targetMuted)
    }

    private func toggleSpeakerFromLiveActivity(sessionID: String) {
        guard voiceLiveActivitySessionID == sessionID,
              phase == .connected || phase == .reconnecting
        else { return }

        setSpeakerMuted(!speakerMuted)
    }

    var currentChannelMembers: [VoiceMember] {
        currentChannel?.members ?? []
    }

    func refreshPublicConfig() async {
        let requestID = UUID()
        let requestedAddress = gatewayAddress
        publicConfigRequestID = requestID
        configLoading = true
        configError = nil
        defer {
            if publicConfigRequestID == requestID { configLoading = false }
        }
        do {
            let gateway = try api.gatewayURL(from: requestedAddress)
            let config = try await api.fetchPublicConfig(gateway: gateway)
            guard publicConfigRequestID == requestID,
                  requestedAddress == gatewayAddress,
                  !Task.isCancelled
            else {
                return
            }
            publicConfig = config
            let gatewayKey = Self.gatewayKey(gateway)
            if config.accessMode == .fixed || configuredGatewayKey != gatewayKey || serverTarget.isEmpty {
                serverTarget = config.target
            }
            configuredGatewayKey = gatewayKey
            if !config.accelerationRelays.orEmpty.contains(where: { $0.id == selectedRelayID }) {
                selectedRelayID = ""
            }
        } catch {
            guard publicConfigRequestID == requestID,
                  requestedAddress == gatewayAddress,
                  !Task.isCancelled
            else {
                return
            }
            publicConfig = nil
            configError = error.localizedDescription
        }
    }

    /// Accepts the ordinary HTTPS invite URL (when the gateway has Universal
    /// Links configured) and the app-owned webspeak://join fallback.
    func handleIncomingInviteURL(_ url: URL) {
        guard phase == .disconnected || phase == .failed else {
            operationError = "请先断开当前会话，再打开新的邀请链接。"
            return
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let query = Dictionary((components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        }, uniquingKeysWith: { _, newest in newest })
        let explicitServerTarget = query["server"] ?? query["target"]
        let hostAndPortTarget: String? = {
            guard let host = query["tsHost"]?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
                return nil
            }
            guard let port = query["tsPort"]?.trimmingCharacters(in: .whitespacesAndNewlines), !port.isEmpty else {
                return host
            }
            return "\(host):\(port)"
        }()

        let gatewayText: String
        if components.scheme?.lowercased() == "webspeak", components.host == "join" {
            guard let value = query["gateway"] else { return }
            gatewayText = value
        } else if components.scheme?.lowercased() == "https",
                  let host = components.host,
                  ["invite", "server", "target", "tsHost", "channel"].contains(where: { query[$0] != nil })
        {
            var origin = URLComponents()
            origin.scheme = "https"
            origin.host = host
            origin.port = components.port
            origin.path = components.path
            gatewayText = origin.string ?? ""
        } else {
            return
        }

        guard let gateway = try? api.gatewayURL(from: gatewayText) else {
            operationError = "邀请链接中的网关地址无效。"
            return
        }
        let incomingInvite = query["invite"] ?? ""
        guard incomingInvite.count <= 128 else {
            operationError = "邀请链接无效：邀请 Token 超出长度限制。"
            return
        }
        gatewayAddress = gateway.absoluteString
        inviteToken = incomingInvite
        channelName = query["channel"] ?? ""
        if let server = explicitServerTarget ?? hostAndPortTarget { serverTarget = server }
        selectedRelayID = ""
        connectionError = nil
        configError = nil
        Task { await refreshPublicConfig() }
    }

    func setPokeNotificationsEnabled(_ enabled: Bool) {
        let requestID = UUID()
        pokeNotificationRequestID = requestID
        guard enabled else {
            pokeNotificationsEnabled = false
            UserDefaults.standard.set(false, forKey: "webspeak.pokeNotifications")
            return
        }
        Task {
            do {
                let authorized = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                guard pokeNotificationRequestID == requestID else { return }
                pokeNotificationsEnabled = authorized
                UserDefaults.standard.set(authorized, forKey: "webspeak.pokeNotifications")
                if !authorized {
                    operationError = "系统未允许通知；可在 iOS 设置中为 WebSpeak 开启通知。"
                }
            } catch {
                guard pokeNotificationRequestID == requestID else { return }
                pokeNotificationsEnabled = false
                operationError = "无法请求通知权限：\(error.localizedDescription)"
            }
        }
    }

    func connect() {
        guard !isBusy else { return }
        let attemptID = UUID()
        connectionAttemptID = attemptID
        connectionError = nil
        configError = nil
        operationError = nil
        phase = .connecting
        connectTask = Task { await beginConnection(attemptID: attemptID) }
    }

    func cancelConnection() {
        disconnect()
    }

    private func beginConnection(attemptID: UUID) async {
        do {
            let gateway = try api.gatewayURL(from: gatewayAddress)
            let policy = try await api.fetchPublicConfig(gateway: gateway)
            guard !Task.isCancelled, connectionAttemptID == attemptID else { return }
            publicConfig = policy
            guard policy.initialized else {
                throw GatewayClientError.server("网关尚未完成初始化，请联系管理员。")
            }

            let cleanNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanNickname.isEmpty else {
                throw GatewayClientError.server("请输入昵称。")
            }
            if policy.accessMode == .open, serverTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw GatewayClientError.server("请输入 TeamSpeak 服务器地址。")
            }

            let gatewayKey = Self.gatewayKey(gateway)
            let identity: String?
            if rememberIdentity {
                identity = identityStore.read(for: gatewayKey)
            } else {
                try identityStore.delete(for: gatewayKey)
                identity = nil
            }

            let ticket = try await api.createJoinTicket(
                gateway: gateway,
                config: policy,
                nickname: cleanNickname,
                target: serverTarget,
                channel: channelName,
                invite: inviteToken,
                serverPassword: serverPassword,
                identity: identity,
                rememberIdentity: rememberIdentity,
                accelerationRelayId: selectedRelayID.isEmpty ? nil : selectedRelayID
            )

            guard !Task.isCancelled, connectionAttemptID == attemptID else { return }
            let request = try api.webSocketRequest(gateway: gateway, ticket: ticket)
            let task = URLSession.shared.webSocketTask(with: request)
            webSocket?.cancel(with: .goingAway, reason: nil)
            receiveTask?.cancel()
            webSocket = task
            activeGatewayURL = gateway
            task.resume()
            UserDefaults.standard.set(cleanNickname, forKey: "webspeak.nickname")
            inviteToken = ""
            receiveTask = Task { [weak self] in
                guard let self else { return }
                await self.receiveMessages(from: task)
            }
        } catch {
            guard !Task.isCancelled, connectionAttemptID == attemptID else { return }
            phase = .failed
            connectionError = error.localizedDescription
        }
    }

    func disconnect() {
        connectionAttemptID = UUID()
        connectTask?.cancel()
        connectTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        for sendTask in memberVolumeSendTasks.values { sendTask.cancel() }
        memberVolumeSendTasks.removeAll()
        pendingRequests.removeAll()
        pendingChannelSwitch = nil
        channelPasswordRequest = nil
        channelPasswordError = nil
        isSwitchingChannel = false
        latencyStartedAt.removeAll()
        stopVoiceMedia()
        queuedGatewayMessages.removeAll()
        gatewaySendTask?.cancel()
        gatewaySendTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        activeGatewayURL = nil
        phase = .disconnected
        connectionError = nil
        channels = []
        members = []
        chatMessages = []
        serverEvents = []
        screenShares = []
        leaveScreenShare(sendLeave: false)
        screenSharePublisherSession?.stop(sendGatewayStop: false)
        screenSharePublisherSession = nil
        isScreenShareStarting = false
        pendingScreenShareStartRequestID = nil
        speakingClientIDs = []
        whisperTargetIDs = []
        whisperActive = false
        localClientID = 0
        privateRecipientID = nil
        gatewayWebRTCAvailable = false
        screenShareIceServers = []
        mediaStatus = "语音媒体尚未连接"
        isVoiceMediaStarting = false
        isVoiceMediaConnected = false
        canEnableMicrophone = false
    }

    func switchChannel(_ channel: VoiceChannel, password: String = "") {
        let requestID = UUID().uuidString
        pendingChannelSwitch = (requestID, channel, !password.isEmpty)
        channelPasswordError = nil
        isSwitchingChannel = true
        sendCommand("switchChannel", payload: [
            "channelId": channel.id,
            "password": password
        ], requestID: requestID)
    }

    func cancelChannelPasswordRequest() {
        channelPasswordRequest = nil
        channelPasswordError = nil
        pendingChannelSwitch = nil
        isSwitchingChannel = false
    }

    func sendChat(_ text: String, scope: ChatScope, recipientID: Int? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 500 else { return }
        let type: String
        var payload: [String: Any] = ["message": trimmed]
        var targetId: String?
        var conversationId: String?

        switch scope {
        case .channel:
            type = "sendTextMessage"
            targetId = currentChannel?.id
        case .server:
            type = "sendServerMessage"
        case .privateMessage:
            guard let recipientID, members.contains(where: { $0.id == recipientID && $0.isSelf != true }) else {
                operationError = "先选择一位在线成员，再发送私聊。"
                return
            }
            type = "sendPrivateMessage"
            payload["clientId"] = recipientID
            conversationId = String(recipientID)
        }

        let messageID = UUID().uuidString
        chatMessages.append(ChatMessage(
            id: messageID,
            scope: scope,
            targetId: targetId,
            conversationId: conversationId,
            senderId: localClientID,
            senderName: "你",
            text: trimmed,
            timestamp: Date(),
            isSelf: true
        ))
        let requestID = sendCommand(type, payload: payload, optimisticMessageID: messageID)
        if requestID == nil {
            chatMessages.removeAll { $0.id == messageID }
        }
    }

    func sendPoke(to memberID: Int, message: String = "") {
        sendCommand("poke", payload: ["clientId": memberID, "message": String(message.prefix(200))])
    }

    func setAway(_ away: Bool, message: String = "") {
        let normalizedMessage = away ? Self.normalizedAwayMessage(message) : ""
        isAway = away
        awayMessage = normalizedMessage
        members = members.map { member in
            guard member.id == localClientID || member.isSelf == true else { return member }
            var copy = member
            copy.away = away
            copy.awayMessage = normalizedMessage.isEmpty ? nil : normalizedMessage
            return copy
        }
        channels = channels.map { channel in
            var copy = channel
            copy.members = channel.members?.map { member in
                guard member.id == localClientID || member.isSelf == true else { return member }
                var updated = member
                updated.away = away
                updated.awayMessage = normalizedMessage.isEmpty ? nil : normalizedMessage
                return updated
            }
            return copy
        }
        sendCommand("setAway", payload: ["away": away, "message": normalizedMessage])
    }

    func isMemberSharingScreen(_ member: VoiceMember) -> Bool {
        screenShares.contains { stream in
            if let ownerClientId = stream.ownerClientId, ownerClientId == member.id { return true }
            return stream.ownerNickname == member.nickname
        }
    }

    private static func normalizedAwayMessage(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        var utf16Length = 0
        for character in trimmed {
            let characterLength = String(character).utf16.count
            guard utf16Length + characterLength <= 200 else { break }
            result.append(character)
            utf16Length += characterLength
        }
        return result
    }

    private func updateSelfPresence(from candidates: [VoiceMember]) {
        guard let selfMember = candidates.first(where: { $0.id == localClientID || $0.isSelf == true }) else {
            isAway = false
            awayMessage = ""
            return
        }
        isAway = selfMember.away == true
        awayMessage = isAway
            ? Self.normalizedAwayMessage(selfMember.awayMessage ?? "")
            : ""
    }

    func setMicrophoneMuted(_ muted: Bool) {
        guard muted || (!speakerMuted && microphoneControlMode == .toggle) else { return }
        guard !isWhisperPushToTalkBusy else {
            operationError = "请先松开耳语 PTT，等待麦克风状态恢复。"
            return
        }
        guard muted || canEnableMicrophone else {
            operationError = "麦克风尚未就绪或未获系统授权。"
            return
        }
        microphoneMuted = muted
        nativeVoiceSession?.setMuted(muted)
        legacyVoiceSession?.setMicrophoneMuted(muted)
        sendCommand("setMicrophoneMuted", payload: ["muted": muted])
    }

    func setMicrophoneControlMode(_ mode: MicrophoneControlMode) {
        guard !isWhisperPushToTalkBusy else {
            operationError = "请先松开耳语 PTT，等待麦克风状态恢复。"
            return
        }
        guard microphoneControlMode != mode else { return }
        endPushToTalk()
        microphoneControlMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "webspeak.microphoneControlMode")
        if mode == .pushToTalk, !microphoneMuted {
            setMicrophoneMuted(true)
        }
    }

    func setSpeakerMuted(_ muted: Bool) {
        guard speakerMuted != muted else { return }
        speakerMuted = muted
        nativeVoiceSession?.setSpeakerMuted(muted)
        legacyVoiceSession?.setSpeakerMuted(muted)
        guard muted else { return }
        if isPushToTalkActive { endPushToTalk() }
        if isWhisperPushToTalkActive { endWhisperPushToTalk() }
        if !microphoneMuted { setLocalMicrophoneMuted(true) }
        sendCommand("setMicrophoneMuted", payload: ["muted": true], requestID: nil)
    }

    func beginPushToTalk() {
        guard !isPushToTalkActive, !isWhisperPushToTalkBusy,
              microphoneControlMode == .pushToTalk, !speakerMuted,
              phase == .connected, isVoiceMediaConnected, canEnableMicrophone
        else { return }
        isPushToTalkActive = true
        nativeVoiceSession?.setMuted(false)
        legacyVoiceSession?.setMicrophoneMuted(false)
        sendCommand("setMicrophoneMuted", payload: ["muted": false], requestID: nil)
    }

    func endPushToTalk() {
        guard isPushToTalkActive else { return }
        isPushToTalkActive = false
        setLocalMicrophoneMuted(true)
        sendCommand("setMicrophoneMuted", payload: ["muted": true], requestID: nil)
    }

    func beginWhisperPushToTalk() {
        guard !isWhisperPushToTalkBusy, !isPushToTalkActive,
              !whisperTargetIDs.isEmpty, phase == .connected,
              isVoiceMediaConnected, canEnableMicrophone, !speakerMuted
        else { return }
        isWhisperPushToTalkActive = true
        isWhisperPushToTalkBusy = true
        whisperPushToTalkPreviousMute = microphoneMuted
        whisperPushToTalkPreviousWhisperState = whisperActive
        setLocalMicrophoneMuted(true)
        whisperPushToTalkTask = Task { [weak self] in
            await self?.runWhisperPushToTalk()
        }
    }

    func endWhisperPushToTalk() {
        guard isWhisperPushToTalkActive else { return }
        isWhisperPushToTalkActive = false
        setLocalMicrophoneMuted(true)
        whisperPushToTalkReleaseContinuation?.resume()
        whisperPushToTalkReleaseContinuation = nil
    }

    private func runWhisperPushToTalk() async {
        let previousMute = whisperPushToTalkPreviousMute ?? true
        let previousWhisper = whisperPushToTalkPreviousWhisperState ?? false
        await legacyVoiceSession?.muteAndWaitForPendingMicrophoneFrames()
        guard !Task.isCancelled else {
            finishWhisperPushToTalk(keepMuted: true)
            return
        }

        // Stop ordinary speech locally first, then wait for the gateway/TeamSpeak
        // mute acknowledgement before changing the server-side whisper routing.
        if !previousMute,
           !(await sendGatewayCommandAndWait("setMicrophoneMuted", payload: ["muted": true]))
        {
            finishWhisperPushToTalk(keepMuted: true)
            return
        }
        guard !Task.isCancelled else {
            finishWhisperPushToTalk(keepMuted: true)
            return
        }

        guard isWhisperPushToTalkActive, !speakerMuted else {
            await restoreWhisperPushToTalk(microphoneWasMuted: previousMute, whisperWasActive: previousWhisper)
            return
        }

        whisperActive = true
        let whisperEnabled = await sendGatewayCommandAndWait("setWhisperActive", payload: ["active": true])
        guard whisperEnabled, !Task.isCancelled else {
            finishWhisperPushToTalk(keepMuted: true)
            return
        }

        guard isWhisperPushToTalkActive, !speakerMuted else {
            await restoreWhisperPushToTalk(microphoneWasMuted: previousMute, whisperWasActive: previousWhisper)
            return
        }

        setLocalMicrophoneMuted(false)
        let microphoneEnabled = await sendGatewayCommandAndWait("setMicrophoneMuted", payload: ["muted": false])
        guard microphoneEnabled, !Task.isCancelled else {
            finishWhisperPushToTalk(keepMuted: true)
            return
        }

        if isWhisperPushToTalkActive {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                whisperPushToTalkReleaseContinuation = continuation
                if !isWhisperPushToTalkActive {
                    whisperPushToTalkReleaseContinuation = nil
                    continuation.resume()
                }
            }
        }
        guard !Task.isCancelled else {
            finishWhisperPushToTalk(keepMuted: true)
            return
        }
        await restoreWhisperPushToTalk(microphoneWasMuted: previousMute, whisperWasActive: previousWhisper)
    }

    private func restoreWhisperPushToTalk(microphoneWasMuted: Bool, whisperWasActive: Bool) async {
        setLocalMicrophoneMuted(true)
        await legacyVoiceSession?.muteAndWaitForPendingMicrophoneFrames()
        guard !Task.isCancelled else {
            finishWhisperPushToTalk(keepMuted: true)
            return
        }
        let microphoneMutedOnGateway = await sendGatewayCommandAndWait("setMicrophoneMuted", payload: ["muted": true])
        guard microphoneMutedOnGateway, !Task.isCancelled else {
            finishWhisperPushToTalk(keepMuted: true)
            return
        }

        let shouldRestoreWhisper = whisperWasActive && !whisperTargetIDs.isEmpty
        whisperActive = shouldRestoreWhisper
        let whisperRestored = await sendGatewayCommandAndWait("setWhisperActive", payload: ["active": shouldRestoreWhisper])
        guard whisperRestored, !Task.isCancelled else {
            finishWhisperPushToTalk(keepMuted: true)
            return
        }

        if !microphoneWasMuted, !speakerMuted, microphoneControlMode == .toggle {
            setLocalMicrophoneMuted(false)
            let microphoneRestored = await sendGatewayCommandAndWait("setMicrophoneMuted", payload: ["muted": false])
            guard microphoneRestored, !Task.isCancelled else {
                finishWhisperPushToTalk(keepMuted: true)
                return
            }
        }
        finishWhisperPushToTalk(keepMuted: microphoneWasMuted)
    }

    private func finishWhisperPushToTalk(keepMuted: Bool) {
        if keepMuted { setLocalMicrophoneMuted(true) }
        isWhisperPushToTalkActive = false
        isWhisperPushToTalkBusy = false
        whisperPushToTalkPreviousMute = nil
        whisperPushToTalkPreviousWhisperState = nil
        whisperPushToTalkTask = nil
        whisperPushToTalkReleaseContinuation?.resume()
        whisperPushToTalkReleaseContinuation = nil
    }

    private func setLocalMicrophoneMuted(_ muted: Bool) {
        let effectiveMute = muted || speakerMuted
        microphoneMuted = effectiveMute
        nativeVoiceSession?.setMuted(effectiveMute)
        legacyVoiceSession?.setMicrophoneMuted(effectiveMute)
    }

    private func sendGatewayCommandAndWait(_ type: String, payload: [String: Any]) async -> Bool {
        guard webSocket != nil else { return false }
        let requestID = UUID().uuidString
        return await withCheckedContinuation { continuation in
            pendingGatewayCommandWaiters[requestID] = continuation
            gatewayCommandTimeoutTasks[requestID] = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(8))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.resolveGatewayCommand(requestID, succeeded: false)
                self?.operationError = "网关未及时确认耳语 PTT 操作；麦克风已在本机保持静音。"
            }
            guard sendCommand(type, payload: payload, requestID: requestID) != nil else {
                resolveGatewayCommand(requestID, succeeded: false)
                return
            }
        }
    }

    private func resolveGatewayCommand(_ requestID: String, succeeded: Bool) {
        gatewayCommandTimeoutTasks.removeValue(forKey: requestID)?.cancel()
        pendingGatewayCommandWaiters.removeValue(forKey: requestID)?.resume(returning: succeeded)
    }

    func retryVoiceMedia() {
        guard phase == .connected, let webSocket else { return }
        startVoiceMedia(on: webSocket, gatewaySaysWebRTCAvailable: gatewayWebRTCAvailable)
    }

    func setWhisperTarget(_ memberID: Int, enabled: Bool) {
        guard !isWhisperPushToTalkBusy else {
            operationError = "请先松开耳语 PTT，等待私语状态恢复，再修改目标。"
            return
        }
        var targets = whisperTargetIDs
        if enabled {
            targets.insert(memberID)
        } else {
            targets.remove(memberID)
        }
        guard targets.count <= 8 else {
            operationError = "私语目标最多为 8 人。"
            return
        }
        sendCommand("setWhisperTargets", payload: ["targetIds": Array(targets).sorted()])
    }

    func setWhisperActive(_ active: Bool) {
        guard !isWhisperPushToTalkBusy else {
            operationError = "请先松开耳语 PTT，等待私语状态恢复。"
            return
        }
        guard !active || !whisperTargetIDs.isEmpty else {
            operationError = "请先选择私语目标。"
            return
        }
        whisperActive = active
        sendCommand("setWhisperActive", payload: ["active": active])
    }

    func moveMember(_ memberID: Int, to channel: VoiceChannel, password: String = "") {
        sendCommand("moveClient", payload: [
            "clientId": memberID,
            "channelId": channel.id,
            "password": password
        ])
    }

    func memberVolume(for member: VoiceMember) -> Double {
        if let value = memberVolumes[member.id] { return value }
        if let uid = member.uid, let value = savedMemberVolumesByUID[uid] { return value }
        return 1
    }

    func setMemberVolume(_ member: VoiceMember, volume: Double) {
        let value = min(4, max(0, volume))
        memberVolumes[member.id] = value
        if let uid = member.uid, !uid.isEmpty {
            savedMemberVolumesByUID[uid] = value
            UserDefaults.standard.set(savedMemberVolumesByUID, forKey: "webspeak.memberVolumesByUID")
        }
        legacyVoiceSession?.setMemberVolume(member.id, volume: value)
        memberVolumeSendTasks[member.id]?.cancel()
        memberVolumeSendTasks[member.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.sendCommand("setMemberVolume", payload: ["clientId": member.id, "volume": value])
            self?.memberVolumeSendTasks.removeValue(forKey: member.id)
        }
    }

    func requestScreenShareList() {
        sendMessage(["type": "screenShareList"])
    }

    func startScreenShare() {
        logger.info("Screen-share publish requested")
        guard phase == .connected else {
            operationError = "請先連接到語音伺服器。"
            return
        }
        guard screenSharePublisherSession == nil, !isScreenShareStarting else { return }
        guard #available(iOS 27.0, *) else {
            operationError = "系統屏幕共享需要 iOS 27 或更新版本；較舊系統目前不支援發送。"
            return
        }
        isScreenShareStarting = true
        operationError = nil
        let requestID = UUID().uuidString
        pendingScreenShareStartRequestID = requestID
        sendMessage([
            "type": "screenShareStart",
            "requestId": requestID,
            "name": "\(nickname) 的 iPhone 屏幕",
            "audio": false
        ])
    }

    func cancelScreenShareStart() {
        isScreenShareStarting = false
        pendingScreenShareStartRequestID = nil
    }

    func stopScreenSharePublishing() {
        guard let session = screenSharePublisherSession else { return }
        session.stop()
        screenSharePublisherSession = nil
        pendingScreenShareStartRequestID = nil
        screenShares.removeAll { $0.streamId == session.stream.streamId }
        isScreenShareStarting = false
    }

    func joinScreenShare(_ stream: ScreenShareStream) {
        logger.info("Screen-share view requested; source=\(stream.source, privacy: .public)")
        guard phase == .connected else {
            operationError = "請先連接到語音伺服器。"
            return
        }
        if activeScreenShare?.streamId == stream.streamId { return }
        leaveScreenShare(sendLeave: true)
        operationError = nil
        sendMessage(["type": "screenShareJoin", "streamId": stream.streamId])
    }

    func leaveScreenShare() {
        leaveScreenShare(sendLeave: true)
    }

    private func leaveScreenShare(sendLeave: Bool) {
        screenShareViewerSession?.close(sendLeave: sendLeave)
        screenShareViewerSession = nil
        activeScreenShare = nil
    }

    func measureLatency() {
        let sequence = UUID().uuidString
        latencyStartedAt[sequence] = ProcessInfo.processInfo.systemUptime
        sendCommand("latencyProbe", payload: ["sequence": sequence], requestID: nil)
    }

    func clearOperationError() {
        operationError = nil
    }

    func applyRecentConnection(_ connection: RecentConnectionRecord) {
        gatewayAddress = connection.gateway
        nickname = connection.nickname
        serverTarget = connection.target
        channelName = connection.channel
        serverPassword = ""
        inviteToken = ""
        publicConfig = nil
        configError = nil
        connectionError = nil
    }

    func toggleFavorite(_ connection: RecentConnectionRecord) {
        guard let index = recentConnections.firstIndex(where: { $0.id == connection.id }) else { return }
        recentConnections[index].isFavorite.toggle()
        persistRecentConnections()
    }

    func removeRecentConnection(_ connection: RecentConnectionRecord) {
        recentConnections.removeAll { $0.id == connection.id }
        persistRecentConnections()
    }

    func clearLocalData() {
        let knownGateways = Set(recentConnections.map(\.gateway) + [gatewayAddress])
        var identityDeleteFailures = 0
        for value in knownGateways {
            guard let url = try? api.gatewayURL(from: value) else { continue }
            do {
                try identityStore.delete(for: Self.gatewayKey(url))
            } catch {
                identityDeleteFailures += 1
            }
        }
        recentConnections = []
        savedMemberVolumesByUID = [:]
        memberVolumes = [:]
        chatMessages = []
        serverEvents = []
        gatewayAddress = ""
        nickname = ""
        serverTarget = ""
        channelName = ""
        serverPassword = ""
        inviteToken = ""
        selectedRelayID = ""
        rememberIdentity = false
        microphoneMuted = true
        speakerMuted = false
        microphoneControlMode = .toggle
        selectedLanguageCode = "system"
        voiceActivityDetectionEnabled = false
        voiceActivityThreshold = 0.008
        noiseSuppressionEnabled = true
        pokeNotificationsEnabled = false
        publicConfig = nil
        configError = nil
        UserDefaults.standard.removeObject(forKey: "webspeak.memberVolumesByUID")
        UserDefaults.standard.removeObject(forKey: "webspeak.recentConnections")
        UserDefaults.standard.removeObject(forKey: "webspeak.gateway")
        UserDefaults.standard.removeObject(forKey: "webspeak.nickname")
        UserDefaults.standard.removeObject(forKey: "webspeak.rememberIdentity")
        UserDefaults.standard.removeObject(forKey: "webspeak.microphoneMuted")
        UserDefaults.standard.removeObject(forKey: "webspeak.speakerMuted")
        UserDefaults.standard.removeObject(forKey: "webspeak.microphoneControlMode")
        UserDefaults.standard.removeObject(forKey: "webspeak.voxEnabled")
        UserDefaults.standard.removeObject(forKey: "webspeak.voxThreshold")
        UserDefaults.standard.removeObject(forKey: "webspeak.noiseSuppression")
        UserDefaults.standard.removeObject(forKey: "webspeak.pokeNotifications")
        UserDefaults.standard.removeObject(forKey: "webspeak.language")
        operationError = identityDeleteFailures == 0
            ? "已清除此 App 保存的连接列表、身份与音量偏好；不会影响网关或 TeamSpeak 服务器数据。"
            : "连接列表与音量偏好已清除，但有 \(identityDeleteFailures) 项 Keychain identity 删除失败。请稍后重试。"
    }

    private func receiveMessages(from task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case let .string(text):
                    guard let data = text.data(using: .utf8) else { continue }
                    handleIncoming(data)
                case let .data(data):
                    if let legacyVoiceSession {
                        legacyVoiceSession.receiveAudioFrame(data)
                    } else {
                        noteBinaryMediaUnavailable()
                    }
                @unknown default:
                    continue
                }
            } catch {
                handleSocketFailure(error, task: task)
                return
            }
        }
    }

    private func handleIncoming(_ data: Data) {
        guard let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = message["type"] as? String
        else {
            return
        }

        switch type {
        case "connected":
            phase = .connected
            connectionError = nil
            gatewayWebRTCAvailable = message["webrtcAvailable"] as? Bool == true
            logger.info("Gateway voice connected; webRTCAvailable=\(self.gatewayWebRTCAvailable, privacy: .public)")
            localClientID = Self.integer(message["tsClientId"])
            recordRecentConnection()
            nativeVoiceSession?.close()
            nativeVoiceSession = nil
            isVoiceMediaStarting = false
            isVoiceMediaConnected = false
            mediaStatus = "正在准备语音媒体…"
            if let values = message["members"] as? [Any] {
                if let decoded = Self.decode([VoiceMember].self, from: values) {
                    let updatedMembers = decoded.map { member in
                        var copy = member
                        copy.isSelf = copy.id == localClientID
                        return copy
                    }
                    members = updatedMembers
                    updateSelfPresence(from: updatedMembers)
                }
            }
            if let values = message["serverEventLog"] as? [Any] {
                if let decoded = Self.decode([ServerEvent].self, from: values) {
                    serverEvents = Array(decoded.suffix(200))
                }
            }
            if let values = message["whisperTargetIds"] as? [Any] {
                whisperTargetIDs = Set(values.map(Self.integer).filter { $0 > 0 })
            }
            whisperActive = message["whisperActive"] as? Bool == true
            if let values = message["screenShareIceServers"] as? [Any] {
                screenShareIceServers = Self.decode([GatewayIceServer].self, from: values) ?? []
            }
            if rememberIdentity,
               let identity = message["identity"] as? String,
               identity.count <= 8192,
               let activeGatewayURL
            {
                do {
                    try identityStore.save(identity, for: Self.gatewayKey(activeGatewayURL))
                } catch {
                    operationError = error.localizedDescription
                }
            }
            if let webSocket {
                startVoiceMedia(on: webSocket, gatewaySaysWebRTCAvailable: gatewayWebRTCAvailable)
            }
            requestScreenShareList()

        case "channelList":
            guard let values = message["channels"] as? [Any] else { return }
            channels = (Self.decode([VoiceChannel].self, from: values) ?? []).map { channel in
                var copy = channel
                copy.members = channel.members?.map { member in
                    var updated = member
                    updated.channelId = channel.id
                    updated.isSelf = member.id == localClientID
                    return updated
                }
                return copy
            }
            members = channels.flatMap { channel in
                (channel.members ?? []).map { member in
                    var copy = member
                    copy.channelId = channel.id
                    copy.isSelf = member.id == localClientID
                    return copy
                }
            }
            updateSelfPresence(from: members)
            requestScreenShareList()

        case "memberEnter":
            let id = Self.integer(message["id"])
            guard id > 0, !members.contains(where: { $0.id == id }) else { return }
            let member = VoiceMember(
                id: id,
                nickname: message["nickname"] as? String ?? "未知用户",
                uid: message["uid"] as? String,
                avatar: message["avatar"] as? String,
                away: message["away"] as? Bool,
                awayMessage: message["awayMessage"] as? String,
                isSelf: (message["isSelf"] as? Bool) ?? (id == localClientID)
            )
            members.append(member)

        case "memberLeave":
            let id = Self.integer(message["id"])
            if isWhisperPushToTalkActive, whisperTargetIDs.contains(id) {
                endWhisperPushToTalk()
            }
            members.removeAll { $0.id == id }
            speakingClientIDs.remove(id)
            memberVolumes.removeValue(forKey: id)
            legacyVoiceSession?.removeMember(id)
            if privateRecipientID == id { privateRecipientID = nil }

        case "memberAvatar":
            let id = Self.integer(message["id"])
            let uid = message["uid"] as? String
            let avatar = message["avatar"] as? String
            members = members.map { member in
                guard member.id == id, uid == nil || uid == member.uid else { return member }
                var copy = member
                copy.avatar = avatar
                return copy
            }
            channels = channels.map { channel in
                var copy = channel
                copy.members = copy.members?.map { member in
                    guard member.id == id, uid == nil || uid == member.uid else { return member }
                    var updated = member
                    updated.avatar = avatar
                    return updated
                }
                return copy
            }

        case "chatMessage":
            appendRemoteChat(message)

        case "serverEvent":
            if let value = message["event"],
               let event = Self.decode(ServerEvent.self, from: value)
            {
                serverEvents.append(event)
                if serverEvents.count > 200 { serverEvents.removeFirst(serverEvents.count - 200) }
            }

        case "pokeReceived":
            let sender = message["invokerName"] as? String ?? "用户"
            let text = message["message"] as? String ?? ""
            if UIApplication.shared.applicationState == .active {
                operationError = text.isEmpty ? "收到来自\(sender)的提醒。" : "\(sender)：\(text)"
            } else if pokeNotificationsEnabled {
                schedulePokeNotification()
            }

        case "voiceActivity":
            if let values = message["clientIds"] as? [Any] {
                speakingClientIDs = Set(values.map(Self.integer).filter { $0 > 0 })
            }

        case "whisperTargets":
            if let values = message["targetIds"] as? [Any] {
                let updatedTargets = Set(values.map(Self.integer).filter { $0 > 0 })
                if isWhisperPushToTalkActive, updatedTargets != whisperTargetIDs {
                    endWhisperPushToTalk()
                }
                whisperTargetIDs = updatedTargets
            }
            whisperActive = message["active"] as? Bool == true

        case "screenShareList":
            let values = message["streams"] as? [Any] ?? []
            screenShares = Self.decode([ScreenShareStream].self, from: values) ?? []
            logger.debug("Screen-share list received; count=\(self.screenShares.count, privacy: .public)")

        case "screenShareStarted":
            if let streamValue = message["stream"],
               let stream = Self.decode(ScreenShareStream.self, from: streamValue)
            {
                let isOwner = message["owner"] as? Bool == true
                let requestID = message["requestId"] as? String
                logger.info("Screen-share start acknowledged; owner=\(isOwner, privacy: .public)")
                if isOwner,
                   (!isScreenShareStarting || requestID == nil || requestID != pendingScreenShareStartRequestID)
                {
                    screenShares.removeAll { $0.streamId == stream.streamId }
                    sendMessage(["type": "screenShareStop", "streamId": stream.streamId])
                    return
                }
                if !screenShares.contains(where: { $0.id == stream.id }) { screenShares.append(stream) }
                if isOwner, isScreenShareStarting, let webSocket {
                    let session = ScreenSharePublisherSession.make(
                        stream: stream,
                        iceServers: screenShareIceServers,
                        gatewaySocket: webSocket
                    )
                    screenSharePublisherSession = session
                    isScreenShareStarting = false
                    pendingScreenShareStartRequestID = nil
                    session.presentSystemPicker()
                }
            }

        case "screenShareJoined":
            guard let streamValue = message["stream"],
                  let stream = Self.decode(ScreenShareStream.self, from: streamValue),
                  let webSocket
            else {
                operationError = "無法讀取屏幕共享資訊。"
                return
            }
            leaveScreenShare(sendLeave: false)
            activeScreenShare = stream
            logger.info("Screen-share join acknowledged; source=\(stream.source, privacy: .public)")
            let session = ScreenShareViewerSession(stream: stream, iceServers: screenShareIceServers, gatewaySocket: webSocket)
            screenShareViewerSession = session
            Task { [weak self, weak session] in
                guard let self, let session else { return }
                do {
                    try await session.start()
                } catch {
                    guard self.screenShareViewerSession === session else { return }
                    self.operationError = error.localizedDescription
                    self.leaveScreenShare(sendLeave: true)
                }
            }

        case "screenShareSignal":
            let signalKind = (message["signal"] as? [String: Any])?["kind"] as? String ?? "unknown"
            logger.debug("Screen-share signal received; kind=\(signalKind, privacy: .public)")
            if let publisher = screenSharePublisherSession,
               message["streamId"] as? String == publisher.stream.streamId,
               let peerID = message["fromPeerId"] as? String,
               let signal = message["signal"] as? [String: Any]
            {
                publisher.receiveSignal(from: peerID, signal: signal)
                return
            }
            guard message["streamId"] as? String == activeScreenShare?.streamId,
                  message["fromPeerId"] as? String == activeScreenShare?.ownerPeerId,
                  let signal = message["signal"] as? [String: Any]
            else {
                return
            }
            if signal["kind"] as? String == "close" {
                leaveScreenShare(sendLeave: false)
            } else {
                screenShareViewerSession?.receiveSignal(signal)
            }

        case "screenShareLeft":
            if message["streamId"] as? String == activeScreenShare?.streamId {
                leaveScreenShare(sendLeave: false)
            }

        case "screenShareStopped":
            if let id = message["streamId"] as? String {
                screenShares.removeAll { $0.streamId == id }
                if id == activeScreenShare?.streamId { leaveScreenShare(sendLeave: false) }
                if id == screenSharePublisherSession?.stream.streamId {
                    screenSharePublisherSession?.stop(sendGatewayStop: false)
                    screenSharePublisherSession = nil
                    isScreenShareStarting = false
                }
            }

        case "screenShareViewerJoined":
            if message["streamId"] as? String == screenSharePublisherSession?.stream.streamId,
               let peerID = message["viewerPeerId"] as? String
            {
                screenSharePublisherSession?.viewerJoined(peerID: peerID)
            }

        case "screenShareNativeViewerJoined":
            if message["streamId"] as? String == screenSharePublisherSession?.stream.streamId,
               let peerID = message["viewerPeerId"] as? String
            {
                screenSharePublisherSession?.viewerJoined(peerID: peerID)
            }

        case "screenShareViewerLeft":
            if message["streamId"] as? String == screenSharePublisherSession?.stream.streamId,
               let peerID = message["viewerPeerId"] as? String
            {
                screenSharePublisherSession?.viewerLeft(peerID: peerID)
            }

        case "screenShareViewerCount":
            guard let id = message["streamId"] as? String else { return }
            screenShares = screenShares.map { stream in
                guard stream.streamId == id else { return stream }
                var copy = stream
                copy.viewerCount = Self.integer(message["viewerCount"])
                if let values = message["viewers"] as? [Any] {
                    copy.viewers = Self.decode([ScreenShareViewer].self, from: values)
                }
                return copy
            }

        case "screenShareError":
            logger.error("Gateway rejected a screen-share operation")
            operationError = Self.safeDetail(message["message"] as? String) ?? "屏幕共享操作失败。"
            if isScreenShareStarting,
               let requestID = message["requestId"] as? String,
               requestID == pendingScreenShareStartRequestID
            {
                isScreenShareStarting = false
                pendingScreenShareStartRequestID = nil
            } else if activeScreenShare != nil {
                leaveScreenShare(sendLeave: false)
            }

        case "channelSwitched":
            operationError = nil
            if let requestID = message["requestId"] as? String,
               pendingChannelSwitch?.requestID == requestID
            {
                pendingChannelSwitch = nil
                channelPasswordRequest = nil
                channelPasswordError = nil
                isSwitchingChannel = false
            }
            if screenSharePublisherSession != nil {
                screenSharePublisherSession?.stop()
                screenSharePublisherSession = nil
                isScreenShareStarting = false
            }
            leaveScreenShare(sendLeave: true)

        case "latencyPong":
            handleLatencyPong(message)

        case "commandCompleted":
            if let requestID = message["requestId"] as? String {
                resolveGatewayCommand(requestID, succeeded: true)
                pendingRequests.removeValue(forKey: requestID)
                if pendingChannelSwitch?.requestID == requestID {
                    pendingChannelSwitch = nil
                    isSwitchingChannel = false
                }
            }

        case "error":
            let errorObject = message["error"] as? [String: Any]
            let detail = Self.safeDetail(errorObject?["message"] as? String) ?? "操作失败。"
            let code = (errorObject?["code"] as? String)?.uppercased()
            if let requestID = message["requestId"] as? String {
                resolveGatewayCommand(requestID, succeeded: false)
            }
            if phase == .connecting {
                phase = .failed
                connectionError = detail
                return
            }
            if let requestID = message["requestId"] as? String,
               let pendingChannelSwitch,
               pendingChannelSwitch.requestID == requestID
            {
                self.pendingChannelSwitch = nil
                isSwitchingChannel = false
                if code == "CHANNEL_PASSWORD_REQUIRED" {
                    channelPasswordRequest = pendingChannelSwitch.channel
                    channelPasswordError = pendingChannelSwitch.submittedPassword
                        ? "密码不正确，请再试一次。"
                        : "此频道需要密码。"
                    logger.info("Channel switch requires a password; prompt shown")
                    return
                }
                channelPasswordRequest = nil
                channelPasswordError = nil
            }
            if let requestID = message["requestId"] as? String {
                if let optimisticID = pendingRequests.removeValue(forKey: requestID) {
                    chatMessages.removeAll { $0.id == optimisticID }
                }
            }
            logger.error("Gateway operation failed; code=\(code ?? "unknown", privacy: .public)")
            operationError = detail

        case "disconnected":
            phase = message["recoverable"] as? Bool == false ? .failed : .reconnecting
            if phase == .failed { connectionError = "TeamSpeak 连接已断开。" }
            stopVoiceMedia()

        case "reconnecting":
            phase = .reconnecting
            stopVoiceMedia()

        case "reconnected":
            phase = .connected
            connectionError = nil
            if let webSocket {
                startVoiceMedia(on: webSocket, gatewaySaysWebRTCAvailable: gatewayWebRTCAvailable)
            }
            requestScreenShareList()

        case "reconnectFailed", "connectionFailed":
            phase = .failed
            stopVoiceMedia()
            let code = message["code"] as? String ?? "CONNECTION_FAILED"
            let detail = Self.safeDetail(message["detail"] as? String)
            connectionError = Self.connectionMessage(code: code, detail: detail)

        case "webrtcAnswer":
            guard let session = nativeVoiceSession else { return }
            let payload = message["payload"] as? [String: Any]
            Task { [weak self, weak session] in
                guard let self, let session else { return }
                do {
                    try await session.applyAnswer(payload?["sdp"])
                    guard self.nativeVoiceSession === session else { return }
                    self.mediaStatus = "WebRTC 信令已响应，正在等待实时媒体连接。"
                    session.setMuted(self.microphoneMuted)
                    self.sendCommand("setMicrophoneMuted", payload: ["muted": self.microphoneMuted], requestID: nil)
                    self.applySavedMemberVolumes()
                } catch {
                    guard self.nativeVoiceSession === session else { return }
                    self.nativeVoiceSession = nil
                    session.close()
                    self.isVoiceMediaConnected = false
                    self.isVoiceMediaStarting = false
                    self.mediaStatus = error.localizedDescription
                }
            }

        case "webrtcError", "audioError":
            logger.error("Gateway reported a WebRTC/audio error; type=\(type, privacy: .public) code=\((message["code"] as? String) ?? "unknown", privacy: .public)")
            let failedSession = nativeVoiceSession
            nativeVoiceSession = nil
            failedSession?.close()
            isVoiceMediaConnected = false
            isVoiceMediaStarting = false
            canEnableMicrophone = false
            mediaStatus = "WebRTC 语音协商失败；请重试并检查网关媒体设置。"

        default:
            break
        }
    }

    private func appendRemoteChat(_ message: [String: Any]) {
        let senderID = Self.integer(message["invokerId"])
        guard senderID != localClientID else { return }
        let rawScope = message["scope"] as? String ?? "system"
        let scope: ChatScope
        switch rawScope {
        case "channel": scope = .channel
        case "server": scope = .server
        case "private": scope = .privateMessage
        default: return
        }
        let timestamp = (message["timestamp"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1_000
        let targetId: String?
        if let rawTarget = message["targetId"] as? String, rawTarget != "0" {
            targetId = rawTarget
        } else if let rawTarget = message["targetId"] as? NSNumber, rawTarget.intValue != 0 {
            targetId = rawTarget.stringValue
        } else {
            targetId = nil
        }
        chatMessages.append(ChatMessage(
            id: UUID().uuidString,
            scope: scope,
            targetId: targetId,
            conversationId: scope == .privateMessage ? String(senderID) : nil,
            senderId: senderID > 0 ? senderID : nil,
            senderName: Self.safeDetail(message["invokerName"] as? String) ?? "未知用户",
            text: Self.safeDetail(message["message"] as? String) ?? "",
            timestamp: Date(timeIntervalSince1970: timestamp / 1_000),
            isSelf: false
        ))
        if chatMessages.count > 1_000 { chatMessages.removeFirst(chatMessages.count - 1_000) }
    }

    private func handleLatencyPong(_ message: [String: Any]) {
        guard let sequence = message["sequence"] as? String,
              let start = latencyStartedAt.removeValue(forKey: sequence)
        else {
            return
        }
        browserRoundTripMs = max(0, Int((ProcessInfo.processInfo.systemUptime - start) * 1_000))
        if let value = message["teamSpeakLatencyMs"] as? NSNumber, value.intValue >= 0 {
            teamSpeakLatencyMs = value.intValue
        } else {
            teamSpeakLatencyMs = nil
        }
    }

    private func schedulePokeNotification() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard pokeNotificationsEnabled,
                  settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            else { return }
            let content = UNMutableNotificationContent()
            content.title = "WebSpeak"
            content.body = String(localized: "你收到一条提醒。打开应用查看会话。", locale: appLocale)
            content.sound = nil
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    private func startVoiceMedia(on socket: URLSessionWebSocketTask, gatewaySaysWebRTCAvailable: Bool) {
        if (speakerMuted || microphoneControlMode == .pushToTalk), !microphoneMuted {
            microphoneMuted = true
        }
        guard gatewaySaysWebRTCAvailable else {
            stopVoiceMedia()
            if !microphoneMuted {
                microphoneMuted = true
            }
            logger.info("Starting legacy WebSocket Opus audio because gateway WebRTC audio is disabled")
            let session = WebSocketVoiceAudioSession(
                gatewaySocket: socket,
                voiceActivityDetectionEnabled: voiceActivityDetectionEnabled,
                voiceActivityThreshold: voiceActivityThreshold,
                noiseSuppressionEnabled: noiseSuppressionEnabled,
                speakerMuted: speakerMuted
            )
            session.onStatusChange = { [weak self, weak session] status in
                guard let self, let session, self.legacyVoiceSession === session else { return }
                self.mediaStatus = status
            }
            session.onMicrophoneLevel = { [weak self, weak session] level in
                guard let self, let session, self.legacyVoiceSession === session else { return }
                self.microphoneInputLevel = level
            }
            legacyVoiceSession = session
            canEnableMicrophone = false
            isVoiceMediaStarting = true
            isVoiceMediaConnected = false
            if !microphoneMuted {
                microphoneMuted = true
            }
            mediaStatus = "正在启动兼容语音并请求麦克风权限…"
            Task { [weak self, weak session] in
                guard let self, let session else { return }
                do {
                    let microphoneAvailable = try await session.start(muted: self.microphoneMuted)
                    guard self.legacyVoiceSession === session else {
                        session.close()
                        return
                    }
                    self.canEnableMicrophone = microphoneAvailable
                    if !microphoneAvailable {
                        self.microphoneMuted = true
                        session.setMicrophoneMuted(true)
                    }
                    self.isVoiceMediaStarting = false
                    self.isVoiceMediaConnected = true
                    self.mediaStatus = microphoneAvailable
                        ? "WebSocket 兼容语音已连接；麦克风\(self.microphoneMuted ? "静音" : "已启用")。"
                        : "兼容语音已连接，可听取频道语音；麦克风权限未开启。"
                    self.sendCommand("setMicrophoneMuted", payload: ["muted": self.microphoneMuted], requestID: nil)
                    self.applySavedMemberVolumes()
                    self.logger.info("Legacy WebSocket audio ready; microphoneAvailable=\(microphoneAvailable, privacy: .public)")
                } catch {
                    guard self.legacyVoiceSession === session else { return }
                    session.close()
                    self.legacyVoiceSession = nil
                    self.canEnableMicrophone = false
                    self.isVoiceMediaStarting = false
                    self.isVoiceMediaConnected = false
                    self.mediaStatus = error.localizedDescription
                    let value = error as NSError
                    self.logger.error("Legacy WebSocket audio startup failed; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
                }
            }
            return
        }

        stopVoiceMedia()
        logger.info("Starting native WebRTC audio")
        let session = WebRTCAudioSession(gatewaySocket: socket)
        session.setSpeakerMuted(speakerMuted)
        session.onStatusChange = { [weak self, weak session] status in
            guard let self, let session, self.nativeVoiceSession === session else { return }
            self.mediaStatus = status
            self.isVoiceMediaConnected = session.isConnected
            if session.isConnected {
                self.isVoiceMediaStarting = false
                self.mediaStatus = "实时 WebRTC 双向语音已连接"
            }
        }
        session.onConnectionFailure = { [weak self, weak session] detail in
            guard let self, let session, self.nativeVoiceSession === session else { return }
            self.nativeVoiceSession = nil
            session.close()
            self.isVoiceMediaStarting = false
            self.isVoiceMediaConnected = false
            self.canEnableMicrophone = false
            self.mediaStatus = detail
        }
        nativeVoiceSession = session
        isVoiceMediaStarting = true
        isVoiceMediaConnected = false
        canEnableMicrophone = false
        mediaStatus = "正在请求麦克风权限并协商 WebRTC…"
        Task { [weak self, weak session] in
            guard let self, let session else { return }
            do {
                try await session.start(muted: self.microphoneMuted)
                guard self.nativeVoiceSession === session else {
                    session.close()
                    return
                }
                self.canEnableMicrophone = true
            } catch {
                guard self.nativeVoiceSession === session else { return }
                session.close()
                self.nativeVoiceSession = nil
                self.isVoiceMediaStarting = false
                self.isVoiceMediaConnected = false
                self.canEnableMicrophone = false
                self.mediaStatus = error.localizedDescription
            }
        }
    }

    private func stopVoiceMedia() {
        if isPushToTalkActive { endPushToTalk() }
        if whisperPushToTalkTask != nil || isWhisperPushToTalkActive {
            setLocalMicrophoneMuted(true)
            whisperPushToTalkReleaseContinuation?.resume()
            whisperPushToTalkReleaseContinuation = nil
            for requestID in Array(pendingGatewayCommandWaiters.keys) {
                resolveGatewayCommand(requestID, succeeded: false)
            }
            whisperPushToTalkTask?.cancel()
            whisperPushToTalkTask = nil
            isWhisperPushToTalkActive = false
            isWhisperPushToTalkBusy = false
            whisperPushToTalkPreviousMute = nil
            whisperPushToTalkPreviousWhisperState = nil
        }
        nativeVoiceSession?.close()
        nativeVoiceSession = nil
        legacyVoiceSession?.close()
        legacyVoiceSession = nil
        isVoiceMediaStarting = false
        isVoiceMediaConnected = false
        canEnableMicrophone = false
        isPushToTalkActive = false
        isWhisperPushToTalkActive = false
        whisperPushToTalkPreviousMute = nil
        whisperPushToTalkPreviousWhisperState = nil
        microphoneInputLevel = 0
    }

    private func applySavedMemberVolumes() {
        for member in members where member.isSelf != true {
            guard let uid = member.uid,
                  let volume = savedMemberVolumesByUID[uid],
                  abs(volume - 1) > 0.001
            else {
                continue
            }
            memberVolumes[member.id] = volume
            legacyVoiceSession?.setMemberVolume(member.id, volume: volume)
            sendCommand("setMemberVolume", payload: ["clientId": member.id, "volume": volume], requestID: nil)
        }
    }

    private func recordRecentConnection() {
        guard let activeGatewayURL, let publicConfig else { return }
        let target = publicConfig.accessMode == .open ? serverTarget : publicConfig.target
        let gatewayKey = Self.gatewayKey(activeGatewayURL)
        let wasFavorite = recentConnections.first { connection in
            guard let savedGateway = try? api.gatewayURL(from: connection.gateway) else { return false }
            return Self.gatewayKey(savedGateway) == gatewayKey
                && connection.target.caseInsensitiveCompare(target) == .orderedSame
        }?.isFavorite ?? false
        let record = RecentConnectionRecord(
            gateway: activeGatewayURL.absoluteString,
            target: target,
            nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines),
            channel: channelName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastConnectedAt: Date(),
            isFavorite: wasFavorite
        )
        recentConnections.removeAll { $0.id == record.id }
        recentConnections.append(record)
        recentConnections.sort { $0.lastConnectedAt > $1.lastConnectedAt }
        if recentConnections.count > 40 {
            let favorites = recentConnections.filter(\.isFavorite)
            let newest = recentConnections.filter { !$0.isFavorite }.prefix(max(0, 40 - favorites.count))
            recentConnections = favorites + newest
            recentConnections.sort { $0.lastConnectedAt > $1.lastConnectedAt }
        }
        persistRecentConnections()
    }

    private func persistRecentConnections() {
        guard let data = try? JSONEncoder().encode(recentConnections) else { return }
        UserDefaults.standard.set(data, forKey: "webspeak.recentConnections")
    }

    private static func loadRecentConnections() -> [RecentConnectionRecord] {
        guard let data = UserDefaults.standard.data(forKey: "webspeak.recentConnections"),
              let values = try? JSONDecoder().decode([RecentConnectionRecord].self, from: data)
        else {
            return []
        }
        return Array(values.sorted { $0.lastConnectedAt > $1.lastConnectedAt }.prefix(40))
    }

    @discardableResult
    private func sendCommand(
        _ type: String,
        payload: [String: Any],
        requestID: String? = UUID().uuidString,
        optimisticMessageID: String? = nil
    ) -> String? {
        guard webSocket != nil else {
            operationError = "当前没有可用的网关连接。"
            return nil
        }
        var message: [String: Any] = ["type": type, "payload": payload]
        if let requestID { message["requestId"] = requestID }
        if let requestID { pendingRequests[requestID] = optimisticMessageID }
        sendMessage(message)
        return requestID
    }

    private func sendMessage(_ message: [String: Any]) {
        guard let socket = webSocket else {
            operationError = "当前没有可用的网关连接。"
            return
        }
        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8)
        else {
            operationError = "无法编码网关请求。"
            return
        }
        queuedGatewayMessages.append((socket, text))
        pumpGatewaySendQueue()
    }

    private func pumpGatewaySendQueue() {
        guard gatewaySendTask == nil else { return }
        gatewaySendTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, !self.queuedGatewayMessages.isEmpty {
                let next = self.queuedGatewayMessages.removeFirst()
                guard self.webSocket === next.socket else { continue }
                do {
                    try await next.socket.send(.string(next.text))
                } catch {
                    self.handleSocketFailure(error, task: next.socket)
                    break
                }
            }
            self.gatewaySendTask = nil
            if !self.queuedGatewayMessages.isEmpty { self.pumpGatewaySendQueue() }
        }
    }

    private func noteBinaryMediaUnavailable() {
        guard phase == .connected, !isVoiceMediaConnected else { return }
        mediaStatus = "网关发送了当前会话未使用的二进制数据；实时语音依赖 WebRTC 协商。"
    }

    private func handleSocketFailure(_ error: Error, task: URLSessionWebSocketTask) {
        guard webSocket === task else { return }
        webSocket = nil
        queuedGatewayMessages.removeAll { $0.socket === task }
        gatewaySendTask?.cancel()
        gatewaySendTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        connectTask?.cancel()
        connectTask = nil
        stopVoiceMedia()
        leaveScreenShare(sendLeave: false)
        screenSharePublisherSession?.stop(sendGatewayStop: false)
        screenSharePublisherSession = nil
        screenShares = []
        isScreenShareStarting = false
        pendingScreenShareStartRequestID = nil
        screenShareIceServers = []
        activeGatewayURL = nil
        for sendTask in memberVolumeSendTasks.values { sendTask.cancel() }
        memberVolumeSendTasks.removeAll()
        pendingRequests.removeAll()
        latencyStartedAt.removeAll()
        speakingClientIDs = []
        channels = []
        members = []
        chatMessages = []
        serverEvents = []
        whisperTargetIDs = []
        whisperActive = false
        localClientID = 0
        privateRecipientID = nil
        gatewayWebRTCAvailable = false
        if phase != .failed {
            phase = .failed
            connectionError = "网关连接中断：\(Self.safeDetail(error.localizedDescription) ?? "请检查网络后重新连接")"
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from value: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func integer(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private static func safeDetail(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(240))
    }

    private static func connectionMessage(code: String, detail: String?) -> String {
        let message: String
        switch code.uppercased() {
        case "SERVER_PASSWORD_REQUIRED": message = "此 TeamSpeak 服务器需要密码。"
        case "INVALID_SERVER_PASSWORD": message = "TeamSpeak 服务器密码错误。"
        case "CHANNEL_PASSWORD_REQUIRED": message = "此频道需要密码。"
        case "NICKNAME_IN_USE": message = "昵称已被使用，请更换昵称。"
        case "HOST_NOT_FOUND": message = "找不到 TeamSpeak 服务器主机。"
        case "UNREACHABLE", "CONNECTION_REFUSED": message = "无法连接 TeamSpeak 服务器，请检查地址和网络。"
        case "IDENTITY_INVALID": message = "已保存的 TeamSpeak 身份无效，请关闭记住身份后重试。"
        case "CLIENT_VERSION_OUTDATED": message = "TeamSpeak 网关客户端版本过旧。"
        case "SERVER_FULL": message = "TeamSpeak 服务器当前已满。"
        case "BANNED", "KICKED": message = "此身份当前无法进入 TeamSpeak 服务器。"
        case "RATE_LIMITED": message = "连接请求过于频繁，请稍后重试。"
        case "ACCELERATION_UNAVAILABLE": message = "所选网络中继当前不可用。"
        default: message = "连接 TeamSpeak 失败（\(String(code.prefix(64)))）。"
        }
        return [message, detail].compactMap { $0 }.joined(separator: " ")
    }

    private static func gatewayKey(_ gateway: URL) -> String {
        var components = URLComponents(url: gateway, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        return components?.string ?? gateway.host ?? gateway.absoluteString
    }
}

private extension Optional where Wrapped == [GatewayRelay] {
    var orEmpty: [GatewayRelay] { self ?? [] }
}
