import ActivityKit

struct WebSpeakVoiceLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum ConnectionStatus: String, Codable, Hashable {
            case connected
            case reconnecting
            case connecting
            case unavailable
        }

        enum MicrophoneMode: String, Codable, Hashable {
            case toggle
            case pushToTalk
        }

        enum ScreenShareStatus: String, Codable, Hashable {
            case none
            case preparing
            case sharing
            case watching
        }

        var channelName: String
        var memberCount: Int?
        var localeIdentifier: String
        var connectionStatus: ConnectionStatus
        var microphoneMuted: Bool
        var microphoneMode: MicrophoneMode
        var pushToTalkActive: Bool
        var microphoneToggleEnabled: Bool
        var speakerMuted: Bool
        var screenShareStatus: ScreenShareStatus
    }

    var sessionID: String
}
