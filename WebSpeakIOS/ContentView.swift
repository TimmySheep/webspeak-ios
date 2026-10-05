import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebSpeakAppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.phase == .connected || model.phase == .reconnecting {
                VoiceWorkspaceView(model: model)
            } else {
                NavigationStack {
                    ConnectionScreenView(model: model)
                }
            }
        }
        .tint(.webSpeakBlue)
        .environment(\.locale, model.appLocale)
        .onOpenURL { model.handleIncomingInviteURL($0) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                model.endPushToTalk()
                model.endWhisperPushToTalk()
            }
        }
    }
}

#Preview {
    ContentView()
}
