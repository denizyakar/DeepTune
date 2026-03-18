import Foundation

struct Tuning: Identifiable, Hashable {
    let id = UUID()
    let name: String
    /// Notes ordered from lowest pitch (thickest string) to highest pitch (thinnest string)
    let notes: [Note]
}

struct TuningGroup: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let tunings: [Tuning]
}
