import SwiftUI

struct InstrumentPickerView: View {
    @ObservedObject var viewModel: TunerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(selectableInstruments) { instrument in
                    instrumentRow(instrument)
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
            .navigationTitle("Select Instrument")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
        .tint(AppTheme.accent)
    }

    private var selectableInstruments: [Instrument] {
        InstrumentCatalog.allInstruments.filter { $0.type != .guitar7 }
    }

    private func instrumentRow(_ instrument: Instrument) -> some View {
        Button {
            viewModel.setInstrument(instrument)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instrument.name)
                        .foregroundColor(AppTheme.textPrimary)
                    Text("\(instrument.availableTunings.count) tuning options")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }
                Spacer()
                if viewModel.currentInstrument == instrument {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.accent)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(AppTheme.surfacePrimary)
    }
}
