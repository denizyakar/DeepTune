import Foundation

enum InstrumentType: String, CaseIterable, Equatable {
    case guitar6 = "6-String Guitar"
    case guitar7 = "7-String Guitar"
    case guitar8 = "8-String Guitar"
    case bass = "4-String Bass"
    case ukulele = "4-String Ukulele"
}

struct Instrument: Identifiable, Hashable {
    let id = UUID()
    let type: InstrumentType
    let defaultTuning: Tuning
    let availableTunings: [Tuning]
    
    var name: String {
        return type.rawValue
    }
}
