import Foundation

struct Note: Identifiable, Hashable {
    let name: String
    let frequency: Double
    let octave: Int

    /// Unique within a tuning; `ModelIdentityTests` guards that.
    var id: String { fullName }

    var fullName: String {
        return "\(name)\(octave)"
    }
}
