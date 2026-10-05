import ActivityKit
import Foundation
import os

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
