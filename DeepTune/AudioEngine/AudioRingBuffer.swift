import Foundation

/// Fixed-capacity circular buffer holding the most recent audio samples.
///
/// Appending costs the size of the incoming chunk, never the size of the backlog:
/// the buffer is written to from a real-time audio callback, so a plain array with
/// `removeFirst` would shift the whole retained window on every callback.
struct AudioRingBuffer {
    private var storage: [Float]
    private var writeIndex = 0
    private(set) var count = 0

    let capacity: Int

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = [Float](repeating: 0.0, count: self.capacity)
    }

    var isEmpty: Bool { count == 0 }

    mutating func append<C: Collection>(_ samples: C) where C.Element == Float {
        for sample in samples {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
        }
        count = Swift.min(capacity, count + samples.count)
    }

    /// The most recent `requestedCount` samples in chronological order, or fewer
    /// when the buffer has not filled up yet.
    func lastSamples(_ requestedCount: Int) -> [Float] {
        let available = Swift.min(requestedCount, count)
        guard available > 0 else { return [] }

        var result = [Float]()
        result.reserveCapacity(available)

        // writeIndex points one past the newest sample.
        var readIndex = ((writeIndex - available) % capacity + capacity) % capacity
        for _ in 0..<available {
            result.append(storage[readIndex])
            readIndex = (readIndex + 1) % capacity
        }
        return result
    }

    mutating func removeAll() {
        writeIndex = 0
        count = 0
    }
}
