import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("today", systemImage: "flame.fill", value: Router.Tab.today) {
                HomeView()
            }
            Tab("battle", systemImage: "trophy.fill", value: Router.Tab.battle) {
                BattleView()
            }
            Tab("stats", systemImage: "chart.bar.xaxis", value: Router.Tab.stats) {
                StatsView()
            }
        }
        .sheet(item: $router.sheet) { sheet in
            sheetContent(sheet)
                .presentationBackground(Theme.bg)
        }
        .fullScreenCover(item: $router.wrapped) { request in
            WrappedView(request: request)
        }
        .fullScreenCover(isPresented: $router.showOnboarding) {
            OnboardingView()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Router.Sheet) -> some View {
        switch sheet {
        case .arm(let auto, let returnTo):
            ArmView(auto: auto, returnTo: returnTo)
                .presentationDetents([.large])
        case .settings:
            SettingsView()
        case .setupGuide:
            NavigationStack { AutomationGuideView(showsDoneButton: true) }
        case .joinBattle:
            JoinBattleView()
        case .invite(let code):
            InviteAcceptView(code: code)
                .presentationDetents([.medium])
        }
    }
}
