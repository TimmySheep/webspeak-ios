import Foundation

enum GatewayAccessMode: String, Decodable {
    case fixed
    case open
}

struct GatewayRelay: Decodable, Identifiable {
    let id: String
    let name: String
}

struct GatewayPublicConfig: Decodable {
    let initialized: Bool
    let accessMode: GatewayAccessMode
    let target: String
    let siteName: String
    let version: String
    let accelerationRelays: [GatewayRelay]?
}

struct GatewayTicketResponse: Decodable {
    let ok: Bool
    let ticket: String?
    let code: String?
}

struct GatewayJoinRequest: Encodable {
    let nickname: String
    let channel: String
    let invite: String
    let identity: String?
    let rememberIdentity: Bool
    let target: String?
    let serverPassword: String?
    let accelerationRelayId: String?
}

struct VoiceMember: Decodable, Identifiable, Hashable {
    let id: Int
    var nickname: String
    var uid: String?
    var avatar: String?
    var away: Bool?
    var awayMessage: String?
    var inputMuted: Bool?
    var outputMuted: Bool?
    var channelCommander: Bool?
    var isSelf: Bool?
    var channelId: String?

    enum CodingKeys: String, CodingKey {
        case id, nickname, uid, avatar, away, awayMessage, inputMuted, outputMuted, channelCommander, isSelf
    }
}

struct VoiceChannel: Decodable, Identifiable, Hashable {
    let id: String
    let parentID: String
    let order: String?
    let name: String
    let description: String?
    var members: [VoiceMember]?
}

struct ServerEvent: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let message: String
    let timestamp: Double
}

enum ChatScope: String, CaseIterable, Identifiable {
    case channel
    case server
    case privateMessage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .channel: "频道"
        case .server: "服务器"
        case .privateMessage: "私聊"
        }
    }
}

struct ChatMessage: Identifiable, Hashable {
    let id: String
    let scope: ChatScope
    let targetId: String?
    let conversationId: String?
    let senderId: Int?
    let senderName: String
    let text: String
    let timestamp: Date
    let isSelf: Bool
}

enum MicrophoneControlMode: String, CaseIterable, Identifiable {
    case toggle
    case pushToTalk

    var id: String { rawValue }
}

struct ScreenShareStream: Decodable, Identifiable, Hashable {
    let streamId: String
    let source: String
    let ownerPeerId: String
    let ownerClientId: Int?
    let ownerNickname: String
    let name: String
    let audio: Bool
    let createdAt: Double
    var viewerCount: Int
    var viewers: [ScreenShareViewer]?

    var id: String { streamId }
}

struct ScreenShareViewer: Decodable, Identifiable, Hashable {
    let peerId: String
    let nickname: String
    let avatar: String?

    var id: String { peerId }
}

struct GatewayIceServer: Decodable, Hashable {
    let urls: [String]
    let username: String?
    let credential: String?

    enum CodingKeys: String, CodingKey {
        case urls, username, credential
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(String.self, forKey: .urls) {
            urls = [value]
        } else {
            urls = try container.decode([String].self, forKey: .urls)
        }
        username = try container.decodeIfPresent(String.self, forKey: .username)
        credential = try container.decodeIfPresent(String.self, forKey: .credential)
    }
}

struct RecentConnectionRecord: Codable, Hashable, Identifiable {
    var gateway: String
    var target: String
    var nickname: String
    var channel: String
    var lastConnectedAt: Date
    var isFavorite: Bool

    var id: String { "\(gateway.lowercased())|\(target.lowercased())" }
}

enum VoiceConnectionPhase: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed

    var title: String {
        switch self {
        case .disconnected: "未连接"
        case .connecting: "正在连接"
        case .connected: "已连接"
        case .reconnecting: "正在重连"
        case .failed: "连接失败"
        }
    }
}

enum GatewayClientError: LocalizedError {
    case invalidGateway
    case insecureGateway
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidGateway:
            "网关地址无效。请输入完整域名或 HTTPS 地址。"
        case .insecureGateway:
            "网关必须使用 HTTPS，应用不会降级到未加密连接。"
        case .invalidResponse:
            "网关返回了无法识别的响应。"
        case let .server(message):
            message
        }
    }
}
