import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

/// Sign in (Apple or no-account quick start), then pick a handle.
struct JoinBattleView: View {
    @Environment(BattleStore.self) private var battle
    @Environment(\.dismiss) private var dismiss
    @State private var rawNonce = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if battle.phase == .needsProfile || battle.phase == .ready {
                        ProfileEditorCard(onSaved: { dismiss() })
                    } else {
                        signInSection
                    }
                }
                .padding(20)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("close") { dismiss() }
                }
            }
        }
    }

    private var signInSection: some View {
        VStack(spacing: 18) {
            GoobView(mood: .lowkey, size: 120)
            Text("join the battle")
                .font(Theme.display(30))
                .foregroundStyle(Theme.text)
            Text("we only store a handle, an emoji and your daily reel totals. no email needed.")
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)

            SignInWithAppleButton(.continue) { request in
                rawNonce = Nonce.random()
                request.requestedScopes = []
                request.nonce = Nonce.sha256(rawNonce)
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 54)
            .clipShape(Capsule())
            .disabled(busy)

            Button {
                Task { await run { try await battle.startAnonymously() } }
            } label: {
                Text(busy ? "hold on…" : "quick start (no account)")
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(busy)

            Text("quick start keeps you on this phone only. sign in with Apple to keep your battles if you switch phones.")
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)

            if let error {
                Text(error).font(Theme.body(14)).foregroundStyle(Theme.red).multilineTextAlignment(.center)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                error = "Apple sign-in didn't return a token."
                return
            }
            let nonce = rawNonce
            Task { await run { try await battle.signInWithApple(idToken: idToken, rawNonce: nonce) } }
        case .failure(let failure):
            if (failure as? ASAuthorizationError)?.code != .canceled {
                error = failure.localizedDescription
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Handle + name + emoji + colour.
struct ProfileEditorCard: View {
    var onSaved: (() -> Void)?

    @Environment(BattleStore.self) private var battle
    @State private var handle = ""
    @State private var displayName = ""
    @State private var emoji = Theme.profileEmojis[0]
    @State private var color = Theme.profileColors[0]
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Avatar(emoji: emoji, colorHex: color, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName.isEmpty ? "your name" : displayName)
                            .font(Theme.body(20, weight: .black))
                            .foregroundStyle(Theme.text)
                        Text("@\(HandleRules.normalize(handle).isEmpty ? "handle" : HandleRules.normalize(handle))")
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundStyle(Theme.textDim)
                    }
                }

                field("display name", text: $displayName, prompt: "e.g. Aspect")
                field("handle", text: $handle, prompt: "lowercase, 3–20 chars")

                Text("pick your vibe")
                    .font(Theme.body(13, weight: .heavy))
                    .foregroundStyle(Theme.textDim)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(Theme.profileEmojis, id: \.self) { option in
                        Text(option)
                            .font(.system(size: 24))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(option == emoji ? Theme.surfaceHigh : .clear))
                            .overlay(Circle().stroke(option == emoji ? Theme.lime : .clear, lineWidth: 2))
                            .onTapGesture { emoji = option }
                    }
                }
                HStack(spacing: 10) {
                    ForEach(Theme.profileColors, id: \.self) { option in
                        Circle()
                            .fill(Color(hexString: option))
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Color.white, lineWidth: option == color ? 3 : 0))
                            .onTapGesture { color = option }
                    }
                }

                if let error {
                    Text(error).font(Theme.body(14)).foregroundStyle(Theme.red)
                }

                Button {
                    Task { await save() }
                } label: {
                    Text(busy ? "saving…" : "lock it in")
                }
                .buttonStyle(ChunkyButtonStyle())
                .disabled(busy)
            }
        }
        .onAppear {
            if let profile = battle.profile {
                handle = profile.handle
                displayName = profile.displayName
                emoji = profile.emoji
                color = profile.color
            } else if handle.isEmpty {
                handle = HandleRules.suggestion()
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.body(13, weight: .heavy))
                .foregroundStyle(Theme.textDim)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(Theme.body(17, weight: .bold))
                .foregroundStyle(Theme.text)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surfaceHigh))
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            try await battle.saveProfile(handle: handle, displayName: displayName, emoji: emoji, color: color)
            error = nil
            onSaved?()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Opened from an invite link.
struct InviteAcceptView: View {
    let code: String

    @Environment(BattleStore.self) private var battle
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var state: ViewState = .idle

    private enum ViewState: Equatable { case idle, working, done(String), failed(String) }

    var body: some View {
        VStack(spacing: 18) {
            Text("⚔️").font(.system(size: 54))
            Text(title)
                .font(Theme.display(26))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            if case .failed(let message) = state {
                Text(message).font(Theme.body(15)).foregroundStyle(Theme.red).multilineTextAlignment(.center)
            }
            if battle.phase == .ready {
                Button(state == .working ? "joining…" : "accept the challenge") {
                    Task { await accept() }
                }
                .buttonStyle(ChunkyButtonStyle())
                .disabled(state == .working || isDone)
            } else {
                Button("set up my profile first") {
                    battle.pendingInviteCode = code
                    router.sheet = .joinBattle
                }
                .buttonStyle(ChunkyButtonStyle())
            }
            Button("close") { dismiss() }.buttonStyle(GhostButtonStyle())
        }
        .padding(24)
        .screenBackground()
    }

    private var isDone: Bool { if case .done = state { true } else { false } }

    private var title: String {
        switch state {
        case .done(let name): "you and \(name) are now battling 🔥"
        default: "someone challenged you to a scroll battle"
        }
    }

    private func accept() async {
        state = .working
        do {
            let friend = try await battle.accept(code: code)
            state = .done(friend.displayName)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

enum Nonce {
    static func random(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "Unable to generate nonce")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
