import AVKit
import SwiftUI

struct AudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.tintColor = UIColor(Color.webSpeakBlue)
        picker.activeTintColor = UIColor(Color.webSpeakBlue)
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {}
}
