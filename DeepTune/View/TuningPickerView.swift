import SwiftUI

struct TuningPickerView: View {
    @ObservedObject var viewModel: TunerViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(InstrumentCatalog.allInstruments) { instrument in
                    Section(header: Text(instrument.name)) {
                        ForEach(instrument.availableTunings) { tuning in
                            Button(action: {
                                viewModel.currentInstrument = instrument
                                viewModel.currentTuning = tuning
                                viewModel.setTargetNote(nil) // Reset manual mode
                                dismiss()
                            }) {
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
                    }
                }
            }
            .navigationTitle("Select Tuning")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}
