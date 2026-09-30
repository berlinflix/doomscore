import SwiftUI
import WidgetKit

@main
struct DoomscoreWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CounterWidget()
        BattleWidget()
        DoomLiveActivity()
        ArmControl()
    }
}
