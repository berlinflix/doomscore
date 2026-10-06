import DeviceActivity
import Foundation

/// Screen Time monitor extension ("auto mode"). iOS wakes it when a tracked
/// app reaches another minute of use today — it never sees the screen, only
/// "Instagram has been open N minutes". Its lifecycle ends as soon as a
/// callback returns, so all work here is synchronous and short.
final class ActivityMonitorExtension: DeviceActivityMonitor {
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        ScreenTimeRuntime.thresholdReached(event.rawValue, at: Date())
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity.rawValue == ScreenTimeLadder.watchdogActivity {
            ScreenTimeRuntime.watchdogFired(at: Date())
        }
    }
}
