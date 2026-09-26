import Foundation

/// How each instrument is drawn. Shared by the tuner and onboarding so both
/// always show the same artwork.
extension InstrumentType {
    var iconName: String {
        switch self {
        case .guitar6, .guitar7, .guitar8:
            return "guitars.fill"
        case .bass:
            return "music.note.list"
        case .ukulele:
            return "music.quarternote.3"
        }
    }

    var headstockImageName: String {
        switch self {
        case .guitar6:
            return "Guitar6Headstock"
        case .guitar7, .guitar8:
            return "Guitar7Headstock"
        case .bass:
            return "Bass4Headstock"
        case .ukulele:
            return "Ukulele4Headstock"
        }
    }
}
