import ActivityKit
import Combine
import Foundation
import os
import SwiftUI

@MainActor
final class VoiceSessionLiveActivityController {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.echosixhiya.webspeak.ios",
        category: "LiveActivity"
    )
    private var operationTask: Task<Void, Never>?
    private var lastRequestedSessionID: String?
    private var lastRequestedState: WebSpeakVoiceLiveActivityAttributes.ContentState?

    func update(sessionID: String, state: WebSpeakVoiceLiveActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard lastRequestedSessionID != sessionID || lastRequestedState != state else { return }
        lastRequestedSessionID = sessionID
        lastRequestedState = state

        let previousTask = operationTask
        operationTask = Task { @MainActor [weak self] in
            await previousTask?.value
            await self?.applyUpdate(sessionID: sessionID, state: state)
        }
    }

    func end(sessionID: String) {
        if lastRequestedSessionID == sessionID {
            lastRequestedSessionID = nil
            lastRequestedState = nil
        }

        let previousTask = operationTask
        operationTask = Task { @MainActor [weak self] in
            await previousTask?.value
            await self?.endActivity(sessionID: sessionID)
        }
    }

    private func applyUpdate(sessionID: String, state: WebSpeakVoiceLiveActivityAttributes.ContentState) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        let activities = Activity<WebSpeakVoiceLiveActivityAttributes>.activities

        if let activity = activities.first(where: { $0.attributes.sessionID == sessionID }) {
            await activity.update(content)
            return
        }

        for staleActivity in activities {
            await staleActivity.end(nil, dismissalPolicy: .immediate)
        }

        do {
            _ = try Activity.request(
                attributes: WebSpeakVoiceLiveActivityAttributes(sessionID: sessionID),
                content: content,
                pushType: nil
            )
        } catch {
            let value = error as NSError
            logger.error("Could not start voice Live Activity; domain=\(value.domain, privacy: .public) code=\(value.code, privacy: .public)")
            if lastRequestedSessionID == sessionID {
                lastRequestedSessionID = nil
                lastRequestedState = nil
            }
        }
    }

    private func endActivity(sessionID: String) async {
        let activities = Activity<WebSpeakVoiceLiveActivityAttributes>.activities
            .filter { $0.attributes.sessionID == sessionID }
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

@MainActor
final class DemoLiveActivityController: ObservableObject {
    enum Status: Equatable {
        case idle
        case starting
        case active
        case unavailable
        case failed

        var message: LocalizedStringKey {
            switch self {
            case .idle:
                return "灵动岛示例尚未启动。"
            case .starting:
                return "正在启动示例 Live Activity…"
            case .active:
                return "示例 Live Activity 已启动。"
            case .unavailable:
                return "Live Activities 当前已关闭，请检查系统设置后重试。"
            case .failed:
                return "系统暂时无法启动示例 Live Activity，请稍后重试。"
            }
        }

        var canRetry: Bool {
            self == .idle || self == .unavailable || self == .failed
        }
    }

    @Published private(set) var status: Status = .idle

    private var activity: Activity<WebSpeakVoiceLiveActivityAttributes>?
    private var startTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var microphoneMuted = false
    private var speakerMuted = false
    private var pushToTalkActive = false

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = .unavailable
            return
        }
        guard activity == nil, startTask == nil else { return }

        status = .starting
        let sessionID = WebSpeakVoiceLiveActivityAttributes.demoSessionIDPrefix + UUID().uuidString

        startTask = Task { @MainActor in
            defer { startTask = nil }

            for previousDemo in Activity<WebSpeakVoiceLiveActivityAttributes>.activities
                where previousDemo.attributes.isDemo
            {
                await previousDemo.end(nil, dismissalPolicy: .immediate)
            }

            guard !Task.isCancelled else {
                status = .idle
                return
            }

            do {
                activity = try Activity.request(
                    attributes: WebSpeakVoiceLiveActivityAttributes(sessionID: sessionID),
                    content: ActivityContent(state: contentState, staleDate: nil),
                    pushType: nil
                )
                status = .active
            } catch {
                activity = nil
                status = .failed
            }
        }
    }

    func update(microphoneMuted: Bool, speakerMuted: Bool, pushToTalkActive: Bool) {
        self.microphoneMuted = microphoneMuted
        self.speakerMuted = speakerMuted
        self.pushToTalkActive = pushToTalkActive
        publishUpdate()
    }

    func end() async {
        startTask?.cancel()
        await startTask?.value

        guard let activity else {
            status = .idle
            return
        }

        self.activity = nil
        let previousUpdate = updateTask
        updateTask = Task { @MainActor in
            await previousUpdate?.value
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        await updateTask?.value
        updateTask = nil
        status = .idle
    }

    private var contentState: WebSpeakVoiceLiveActivityAttributes.ContentState {
        WebSpeakVoiceLiveActivityAttributes.ContentState(
            channelName: "夜航语音",
            memberCount: 3,
            localeIdentifier: Locale.current.identifier,
            connectionStatus: .connected,
            microphoneMuted: microphoneMuted,
            microphoneMode: pushToTalkActive ? .pushToTalk : .toggle,
            pushToTalkActive: pushToTalkActive,
            microphoneToggleEnabled: false,
            speakerMuted: speakerMuted,
            screenShareStatus: .none
        )
    }

    private func publishUpdate() {
        guard let activity else { return }
        let previousUpdate = updateTask
        updateTask = Task { @MainActor in
            await previousUpdate?.value
            guard self.activity?.attributes.sessionID == activity.attributes.sessionID else { return }
            await activity.update(ActivityContent(state: contentState, staleDate: nil))
        }
    }
}
