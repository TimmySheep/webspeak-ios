import AppIntents

@MainActor
final class LiveActivityIntentBridge {
    static let shared = LiveActivityIntentBridge()

    private var microphoneToggleHandler: ((String) -> Void)?
    private var speakerToggleHandler: ((String) -> Void)?

    func registerMicrophoneToggleHandler(_ handler: @escaping (String) -> Void) {
        microphoneToggleHandler = handler
    }

    func toggleMicrophone(sessionID: String) {
        microphoneToggleHandler?(sessionID)
    }

    func registerSpeakerToggleHandler(_ handler: @escaping (String) -> Void) {
        speakerToggleHandler = handler
    }

    func toggleSpeaker(sessionID: String) {
        speakerToggleHandler?(sessionID)
    }
}

struct ToggleLiveActivityMicrophoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "切换麦克风"
    static var openAppWhenRun = false

    @Parameter(title: "语音会话标识")
    var sessionID: String

    init() {
        sessionID = ""
    }

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            LiveActivityIntentBridge.shared.toggleMicrophone(sessionID: sessionID)
        }
        return .result()
    }
}

struct ToggleLiveActivitySpeakerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "切换扬声器"
    static var openAppWhenRun = false

    @Parameter(title: "语音会话标识")
    var sessionID: String

    init() {
        sessionID = ""
    }

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            LiveActivityIntentBridge.shared.toggleSpeaker(sessionID: sessionID)
        }
        return .result()
    }
}
