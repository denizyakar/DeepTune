//
//  ContentView.swift
//  DeepTune
//
//  Created by Ali Deniz Yakar on 16.03.2026.
//

import SwiftUI

struct ContentView: View {
    private static let onboardingKey = "DeepTune.hasCompletedOnboarding"

    // Read once rather than through @AppStorage, which re-renders this view on
    // UserDefaults writes. TunerView builds its session on every init and the
    // session saves the selection while it is built, so each render rebuilt the
    // tuner and triggered another render: the app hung on a blank screen.
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)

    var body: some View {
        // The tuner is only built once onboarding is done, so it can't start the
        // audio engine or ask for the microphone underneath the tour.
        if hasCompletedOnboarding {
            TunerView()
                .transition(.opacity)
        } else {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: Self.onboardingKey)
                withAnimation(.easeInOut(duration: 0.35)) {
                    hasCompletedOnboarding = true
                }
            }
            .transition(.opacity)
        }
    }
}

#Preview {
    ContentView()
}
