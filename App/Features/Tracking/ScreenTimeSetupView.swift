import FamilyControls
import SwiftUI

/// Connects auto mode: Screen Time access (one Face ID), then the app picks.
/// Used in onboarding, on Home while tracking is off, and in Settings.
struct ScreenTimeConnectCard: View {
    var showsTikTok = true
    var onConnected: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var pickerSlot: ScreenTimeSlot?
    @State private var showPicker = false
    @State private var draft = FamilyActivitySelection()
    @State private var working = false

    private var service: ScreenTimeService { model.screenTime }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: service.isTracking ? "checkmark.seal.fill" : "hourglass.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(service.isTracking ? Theme.lime : Theme.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Theme.body(17, weight: .heavy))
                            .foregroundStyle(Theme.text)
                        Text(subtitle)
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                    }
                }

                if service.isAuthorized {
                    slotRow(.instagram)
                    if showsTikTok { slotRow(.tiktok) }
                } else {
                    Button {
                        Task { await connect() }
                    } label: {
                        Label(working ? "connecting…" : "connect Screen Time", systemImage: "faceid")
                    }
                    .buttonStyle(ChunkyButtonStyle())
                    .disabled(working)
                    if service.status == .denied {
                        Text("Screen Time access is off. Tap connect to try again (or check Settings → Screen Time).")
                            .font(Theme.body(12, weight: .semibold))
                            .foregroundStyle(Theme.orange)
                    }
                }

                if let error = service.lastError {
                    Text(error)
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.orange)
                }
            }
        }
        .familyActivityPicker(
            headerText: pickerSlot.map { "pick \($0.app.displayName) \($0 == .instagram ? "📸" : "🎵")" },
            footerText: "Only pick \(pickerSlot?.app.displayName ?? "the app"). Doomscore only learns how long it's open — never what's on screen.",
            isPresented: $showPicker,
            selection: $draft
        )
        .onChange(of: showPicker) { _, isOpen in
            guard !isOpen, let slot = pickerSlot else { return }
            pickerSlot = nil
            service.setSelection(draft, for: slot)
            if service.hasApp(for: slot), !service.enabled { service.enable() }
            if service.isTracking { onConnected?() }
        }
    }

    private var title: String {
        if service.isTracking { return "auto-tracking is on ✅" }
        if service.isAuthorized { return "now pick Instagram" }
        return "track automatically"
    }

    private var subtitle: String {
        if service.isTracking { return "runs all day via Screen Time. no recording, no taps." }
        if service.isAuthorized { return "so Screen Time knows which app to watch the clock for" }
        return "iOS Screen Time tells us how long Instagram is open — never what's on it"
    }

    @ViewBuilder
    private func slotRow(_ slot: ScreenTimeSlot) -> some View {
        let tokens = service.selections[slot]?.applicationTokens ?? []
        HStack(spacing: 12) {
            if let token = tokens.first {
                Label(token)
                    .labelStyle(.iconOnly)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                Image(systemName: slot.app.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(slot.app.tint))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(slot.app.displayName)
                    .font(Theme.body(15, weight: .heavy))
                    .foregroundStyle(Theme.text)
                Text(tokens.isEmpty ? (slot == .instagram ? "not picked yet" : "optional") : "tracking · \(String(format: "%.1f", model.pace(for: slot))) reels/min")
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(tokens.isEmpty ? Theme.textFaint : Theme.lime)
            }
            Spacer()
            Button(tokens.isEmpty ? "pick" : "change") { present(slot) }
                .font(Theme.body(14, weight: .heavy))
                .buttonStyle(.bordered)
                .tint(tokens.isEmpty && slot == .instagram ? Theme.lime : Theme.textDim)
        }
    }

    private func present(_ slot: ScreenTimeSlot) {
        draft = service.selections[slot] ?? FamilyActivitySelection()
        pickerSlot = slot
        showPicker = true
    }

    private func connect() async {
        working = true
        defer { working = false }
        if await service.requestAuthorization(), !service.hasApp(for: .instagram) {
            present(.instagram)
        }
    }
}

/// "be honest: what do you do on Instagram?" — sets the starting pace.
struct ScrollStylePicker: View {
    @Environment(AppModel.self) private var model
    @State private var selected = SharedSettings.shared.scrollStyle

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ScrollStyle.allCases) { style in
                Button {
                    selected = style
                    model.setScrollStyle(style)
                } label: {
                    HStack(spacing: 12) {
                        Text(style.emoji).font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.title)
                                .font(Theme.body(16, weight: .heavy))
                                .foregroundStyle(Theme.text)
                            Text("≈ \(String(format: "%.1f", style.instagramPace)) reels per minute on IG")
                                .font(Theme.body(12, weight: .semibold))
                                .foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        Image(systemName: selected == style ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(selected == style ? Theme.lime : Theme.textFaint)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(selected == style ? Theme.lime.opacity(0.12) : Theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(selected == style ? Theme.lime.opacity(0.6) : Theme.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(PressableStyle())
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}
