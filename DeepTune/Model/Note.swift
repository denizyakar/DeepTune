import Foundation

struct Note: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let frequency: Double
    let octave: Int
    
    var fullName: String {
        return "\(name)\(octave)"
    }
}
