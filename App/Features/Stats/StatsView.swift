import Charts
import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var period: StatsPeriod = .week
    @State private var anchor = Date()

    private var summary: PeriodSummary {
        StatsEngine.summary(for: period, containing: anchor, ledger: model.ledger, goal: model.goal, installDate: model.installDate)
    }

    var body: some View {
        let summary = self.summary
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("progress 📈")
                        .font(Theme.display(28))
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                Picker("Period", selection: $period) {
                    ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { _, _ in anchor = Date() }

                navigator(summary)
                chartCard(summary)
                tiles(summary)
                if !summary.perApp.isEmpty { appsCard(summary) }
                wrappedCards
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
    }

    // MARK: Sections

    private func navigator(_ summary: PeriodSummary) -> some View {
        let canGoForward = summary.interval.end <= Date() ? true : false
        return HStack {
            Button { shift(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .black))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.surfaceHigh))
            }
            Spacer()
            Text(Fmt.periodTitle(period, interval: summary.interval))
                .font(Theme.body(17, weight: .black))
                .foregroundStyle(Theme.text)
            Spacer()
            Button { shift(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .black))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.surfaceHigh))
            }
            .disabled(!canGoForward)
            .opacity(canGoForward ? 1 : 0.3)
        }
        .foregroundStyle(Theme.text)
    }

    private func shift(_ direction: Int) {
        if let next = Calendar.current.date(byAdding: period.calendarComponent, value: direction, to: anchor), next <= Date().addingTimeInterval(1) {
            withAnimation(.snappy) { anchor = next }
        }
    }

    private func chartCard(_ summary: PeriodSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(summary.total)")
                        .font(Theme.display(40))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText(value: Double(summary.total)))
                    Text("reels")
                        .font(Theme.body(16, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    if let change = summary.changeVsPrevious, period != .day {
                        Text("\(Fmt.percent(change)) vs last \(period.title.lowercased())")
                            .font(Theme.body(12, weight: .heavy))
                            .foregroundStyle(change > 0 ? Theme.red : Theme.lime)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill((change > 0 ? Theme.red : Theme.lime).opacity(0.12)))
                    }
                }
                chart(summary)
                    .frame(height: 180)
            }
        }
    }

    @ViewBuilder
    private func chart(_ summary: PeriodSummary) -> some View {
        switch period {
        case .day:
            Chart {
                ForEach(0..<24, id: \.self) { hour in
                    BarMark(x: .value("Hour", hour), y: .value("Reels", summary.hourly[hour]))
                        .foregroundStyle(Theme.brand)
                        .cornerRadius(4)
                }
            }
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel { if let h = value.as(Int.self) { Text(Fmt.hour(h)) } }
                }
            }
            .chartStyled()
        case .week, .month:
            Chart {
                ForEach(summary.series) { entry in
                    BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Reels", entry.count))
                        .foregroundStyle(entry.count > model.goal ? AnyShapeStyle(Theme.hot) : AnyShapeStyle(Theme.brand))
                        .cornerRadius(5)
                }
                RuleMark(y: .value("Cap", model.goal))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(Theme.textFaint)
                    .annotation(position: .top, alignment: .leading) {
                        Text("cap").font(Theme.body(10, weight: .bold)).foregroundStyle(Theme.textFaint)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 7)) { value in
                    AxisValueLabel(format: period == .week ? .dateTime.weekday(.narrow) : .dateTime.day())
                }
            }
            .chartStyled()
        case .year:
            Chart {
                ForEach(summary.monthly) { entry in
                    BarMark(x: .value("Month", entry.date, unit: .month), y: .value("Reels", entry.count))
                        .foregroundStyle(Theme.brand)
                        .cornerRadius(5)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow))
                }
            }
            .chartStyled()
        }
    }

    private func tiles(_ summary: PeriodSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(emoji: "📊", value: String(format: "%.0f", summary.averagePerDay), label: "avg per day")
            StatTile(
                emoji: "🏆",
                value: summary.bestDay.map { Fmt.compact($0.count) } ?? "—",
                label: summary.bestDay.map { "highest · \(Fmt.dayTitle($0.day))" } ?? "highest day",
                tint: Theme.orange
            )
            StatTile(emoji: "⏱️", value: Fmt.duration(summary.watchSeconds), label: "time scrolling")
            StatTile(emoji: "🧊", value: "\(summary.longestChillStreak)d", label: "longest chill streak", tint: Theme.cyan)
            StatTile(emoji: "🥷", value: "\(summary.adsSkipped)", label: "ads dodged", tint: Theme.lime)
            StatTile(emoji: "📏", value: String(format: "%.0f m", summary.thumbMeters), label: "of content scrolled", tint: Theme.pink)
        }
    }

    private func appsCard(_ summary: PeriodSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "top apps")
                ForEach(summary.perApp) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.app.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(entry.app.tint))
                        Text(entry.app.displayName)
                            .font(Theme.body(16, weight: .bold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Fmt.compact(entry.count))
                                .font(Theme.body(17, weight: .black))
                                .foregroundStyle(Theme.text)
                            if entry.seconds > 0 {
                                Text(Fmt.duration(entry.seconds))
                                    .font(Theme.body(12, weight: .semibold))
                                    .foregroundStyle(Theme.textFaint)
                            }
                        }
                    }
                }
            }
        }
    }

    private var wrappedCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "recaps 📼")
            HStack(spacing: 10) {
                wrappedButton("week", emoji: "🗓️", period: .week, colors: [Theme.lime, Theme.cyan])
                wrappedButton("month", emoji: "🌙", period: .month, colors: [Theme.pink, Theme.violet])
                wrappedButton(String(Calendar.current.component(.year, from: Date())), emoji: "🏁", period: .year, colors: [Theme.orange, Theme.pink])
            }
        }
    }

    private func wrappedButton(_ title: String, emoji: String, period: StatsPeriod, colors: [Color]) -> some View {
        Button {
            router.wrapped = Router.WrappedRequest(period: period, anchor: Date())
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(emoji).font(.system(size: 26))
                Text(title).font(Theme.body(16, weight: .black))
                Text("recap").font(Theme.body(12, weight: .bold)).opacity(0.7)
            }
            .foregroundStyle(.black)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(PressableStyle())
    }
}

private extension View {
    func chartStyled() -> some View {
        chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel().foregroundStyle(Theme.textFaint)
            }
        }
    }
}
