import SwiftUI

struct TuningPickerView: View {
    @ObservedObject var viewModel: TunerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(InstrumentCatalog.allInstruments) { instrument in
                    instrumentSections(for: instrument)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationTitle("Select Tuning")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
        .tint(AppTheme.accent)
    }

    @ViewBuilder
    private func instrumentSections(for instrument: Instrument) -> some View {
        let groups = InstrumentCatalog.tuningGroups(for: instrument)
        ForEach(groups) { group in
            Section(header: groupHeader(instrument: instrument, group: group)) {
                ForEach(group.tunings) { tuning in
                    tuningRow(instrument: instrument, tuning: tuning)
                }
            }
        }
    }

    private func tuningRow(instrument: Instrument, tuning: Tuning) -> some View {
        Button {
            viewModel.setInstrumentAndTuning(instrument: instrument, tuning: tuning)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tuning.name)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("\(tuning.notes.count)-string")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
                if viewModel.currentInstrument == instrument && viewModel.currentTuning == tuning {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.accent)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }

    private func groupHeader(instrument: Instrument, group: TuningGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(instrument.name) • \(group.title)")
                .foregroundColor(AppTheme.textPrimary)
            if let subtitle = group.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .textCase(nil)
    }
}
