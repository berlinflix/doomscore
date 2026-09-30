import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action Button control (iOS 18+).
struct ArmControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.doomscore.arm") {
            ControlWidgetButton(action: ArmCounterIntent()) {
                Label("Count Reels", systemImage: "flame.fill")
            }
        }
        .displayName("Count Reels")
        .description("Jump straight to arming the Doomscore counter.")
    }
}
