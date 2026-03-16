import Foundation

struct InstrumentCatalog {
    static let standardGuitar6Notes = [
        Note(name: "E", frequency: 82.41, octave: 2), // 6th string
        Note(name: "A", frequency: 110.00, octave: 2), // 5th string
        Note(name: "D", frequency: 146.83, octave: 3), // 4th string
        Note(name: "G", frequency: 196.00, octave: 3), // 3rd string
        Note(name: "B", frequency: 246.94, octave: 3), // 2nd string
        Note(name: "E", frequency: 329.63, octave: 4)  // 1st string
    ]
    
    static let standardGuitar6Tuning = Tuning(name: "Standard", notes: standardGuitar6Notes)
    
    static let guitar6 = Instrument(
        type: .guitar6,
        defaultTuning: standardGuitar6Tuning,
        availableTunings: [standardGuitar6Tuning]
    )
    
    static let allInstruments: [Instrument] = [guitar6]
}
