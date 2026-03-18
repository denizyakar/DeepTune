import SwiftUI

struct TuningPickerView: View {
    @ObservedObject var viewModel: TunerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(InstrumentCatalog.allInstruments) { instrument in
                    instrumentSections(for: instrument)
                }
            }
            .navigationTitle("Select Tuning")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
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
            viewModel.currentInstrument = instrument
            viewModel.currentTuning = tuning
            viewModel.setTargetNote(nil)
            dismiss()
        } label: {
            HStack {
                Text(tuning.name)
                    .foregroundColor(.primary)
                Spacer()
                if viewModel.currentInstrument == instrument && viewModel.currentTuning == tuning {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                }
            }
        }
    }

    private func groupHeader(instrument: Instrument, group: TuningGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(instrument.name) • \(group.title)")
            if let subtitle = group.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .textCase(nil)
    }
}
