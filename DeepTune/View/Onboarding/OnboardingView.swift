import SwiftUI

/// A short first-launch tour. Each page shows a live demo of the real
/// component it describes.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page: OnboardingPage = .instruments

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip", action: onFinish)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .opacity(page.isLast ? 0 : 1)
                        .disabled(page.isLast)
                }
                .padding(.horizontal, 24)
                .frame(height: 44)

                TabView(selection: $page) {
                    ForEach(OnboardingPage.allCases) { item in
                        OnboardingPageView(page: item, isActive: item == page)
                            .tag(item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 18) {
                    PageIndicator(current: page)

                    Button(page.isLast ? "Get Started" : "Continue", action: advance)
                        .buttonStyle(.primary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
    }

    private func advance() {
        guard let next = page.next else {
            onFinish()
            return
        }
        withAnimation {
            page = next
        }
    }
}

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case instruments
    case tunings
    case modes
    case chordFinder

    var id: Int { rawValue }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }

    var isLast: Bool { next == nil }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                demo
                    .padding(.top, 8)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(message)
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var demo: some View {
        switch page {
        case .instruments:
            InstrumentsDemo(isActive: isActive)
        case .tunings:
            TuningsDemo(isActive: isActive)
        case .modes:
            TuningModesDemo(isActive: isActive)
        case .chordFinder:
            ChordFinderDemo(isActive: isActive)
        }
    }

    private var title: LocalizedStringKey {
        switch page {
        case .instruments: "Guitar, bass or ukulele"
        case .tunings: "Beyond standard tuning"
        case .modes: "Two ways to tune"
        case .chordFinder: "Name that chord"
        }
    }

    private var message: LocalizedStringKey {
        switch page {
        case .instruments:
            "Pick your instrument at the top of the screen and the tuner follows its strings."
        case .tunings:
            "\(InstrumentCatalog.selectableTuningCount) drop, open and alternate tunings, grouped so the one you need is easy to find."
        case .modes:
            "Auto guides you string by string. Manual shows whatever note you play."
        case .chordFinder:
            "Play a chord once and Chord Finder names it, along with close alternatives."
        }
    }
}

private struct PageIndicator: View {
    let current: OnboardingPage

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingPage.allCases) { page in
                Capsule()
                    .fill(page == current ? AppTheme.accent : AppTheme.stroke)
                    .frame(width: page == current ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: current)
        .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingView(onFinish: {})
}

#Preview("Dark") {
    OnboardingView(onFinish: {})
        .preferredColorScheme(.dark)
}
