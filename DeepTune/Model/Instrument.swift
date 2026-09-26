import Foundation

enum InstrumentType: String, CaseIterable, Hashable {
    case guitar6 = "6-String Guitar"
    case guitar7 = "7-String Guitar"
    case guitar8 = "8-String Guitar"
    case bass = "4-String Bass"
    case ukulele = "4-String Ukulele"

    var displayName: String {
        switch self {
        case .guitar6: String(localized: "6-String Guitar")
        case .guitar7: String(localized: "7-String Guitar")
        case .guitar8: String(localized: "8-String Guitar")
        case .bass: String(localized: "4-String Bass")
        case .ukulele: String(localized: "4-String Ukulele")
        }
    }
}

struct Instrument: Identifiable, Hashable {
    let type: InstrumentType
    let defaultTuning: Tuning
    let availableTunings: [Tuning]

    var id: InstrumentType { type }
    
    var name: String {
        type.displayName
    }
}
