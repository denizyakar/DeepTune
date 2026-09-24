import Foundation

struct Tuning: Identifiable, Hashable {
    let name: String
    /// Notes ordered from lowest pitch (thickest string) to highest pitch (thinnest string)
    let notes: [Note]

    /// Unique within an instrument, which is what persistence relies on.
    var id: String { name }
}

struct TuningGroup: Identifiable, Hashable {
    let title: String
    let subtitle: String?
    let tunings: [Tuning]

    var id: String { title }
}
