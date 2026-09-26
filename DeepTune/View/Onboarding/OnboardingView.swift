import SwiftUI

/// A short first-launch tour. Each page shows a live demo of the real
/// component it describes, and the last one asks for the microphone.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page: OnboardingPage = .instruments
    @State private var permissionManager: PermissionManager
    /// Fixed at launch: the microphone page only appears if there is still
    /// something to ask, and must not vanish once the user answers.
    private let pages: [OnboardingPage]

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
        let permissionManager = PermissionManager()
        _permissionManager = State(initialValue: permissionManager)
        pages = OnboardingPage.allCases.filter {
            $0 != .microphone || permissionManager.canRequestMicrophoneAccess
        }
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundTop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip", action: skip)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .opacity(isLastPage ? 0 : 1)
                        .disabled(isLastPage)
                }
                .padding(.horizontal, 24)
                .frame(height: 44)

                TabView(selection: $page) {
                    ForEach(pages) { item in
                        OnboardingPageView(page: item, isActive: item == page)
                            .tag(item)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 18) {
                    PageIndicator(pages: pages, current: page)

                    if page == .microphone {
                        Button("Allow Microphone", action: requestMicrophone)
                            .buttonStyle(.primary)
                    } else {
                        Button(isLastPage ? "Get Started" : "Continue", action: advance)
                            .buttonStyle(.primary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, page == .microphone ? 0 : 12)

                // Always laid out so the primary button doesn't jump between pages.
                Button("Not Now", action: onFinish)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(height: 36)
                    .opacity(page == .microphone ? 1 : 0)
                    .disabled(page != .microphone)
                    .padding(.bottom, 4)
            }
        }
    }

    private var isLastPage: Bool { page == pages.last }

    private func advance() {
        guard let index = pages.firstIndex(of: page), index + 1 < pages.count else {
            onFinish()
            return
        }
        withAnimation {
            page = pages[index + 1]
        }
    }

    /// Skipping the tour still stops at the microphone question, which the
    /// user can decline there.
    private func skip() {
        guard pages.contains(.microphone) else {
            onFinish()
            return
        }
        withAnimation {
            page = .microphone
        }
    }

    // Either answer finishes onboarding; if access is refused, the tuner's
    // own card explains how to turn it on.
    private func requestMicrophone() {
        permissionManager.requestMicrophonePermission { _ in
            onFinish()
        }
    }
}

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case instruments
    case tunings
    case modes
    case chordFinder
    case microphone

    var id: Int { rawValue }
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
        case .microphone:
            MicrophoneDemo(isActive: isActive)
        }
    }

    private var title: LocalizedStringKey {
        switch page {
        case .instruments: "Guitar, bass or ukulele"
        case .tunings: "Beyond standard tuning"
        case .modes: "Two ways to tune"
        case .chordFinder: "Name that chord"
        case .microphone: "Let DeepTune listen"
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
        case .microphone:
            "The microphone is how DeepTune hears your instrument. Audio is processed on your device and never saved."
        }
    }
}

private struct PageIndicator: View {
    let pages: [OnboardingPage]
    let current: OnboardingPage

    var body: some View {
        HStack(spacing: 8) {
            ForEach(pages) { page in
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
