import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action Button control (iOS 18+).
struct ArmControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.doomscore.arm") {
            ControlWidgetButton(action: ArmCounterIntent()) {
                Label("How Cooked Am I", systemImage: "flame.fill")
            }
        }
        .displayName("How Cooked Am I")
        .description("Open Doomscore on today's reel count.")
    }
}
