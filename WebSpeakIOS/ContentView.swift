import SwiftUI

struct ContentView: View {
    @StateObject private var model = WebSpeakAppModel()

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
    }
}

#Preview {
    ContentView()
}
