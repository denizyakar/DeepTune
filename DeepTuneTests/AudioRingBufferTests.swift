import XCTest
@testable import DeepTune

final class AudioRingBufferTests: XCTestCase {
    func testReturnsAppendedSamplesInOrder() {
        var buffer = AudioRingBuffer(capacity: 8)
        buffer.append([1, 2, 3])

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.lastSamples(3), [1, 2, 3])
    }

    func testReturnsFewerSamplesThanRequestedWhenNotYetFilled() {
        var buffer = AudioRingBuffer(capacity: 8)
        buffer.append([1, 2])

        XCTAssertEqual(buffer.lastSamples(5), [1, 2])
    }

    func testKeepsOnlyMostRecentSamplesOnceWrapped() {
        var buffer = AudioRingBuffer(capacity: 4)
        buffer.append([1, 2, 3, 4, 5, 6])

        XCTAssertEqual(buffer.count, 4)
        XCTAssertEqual(buffer.lastSamples(4), [3, 4, 5, 6])
    }

    func testWrapsCorrectlyAcrossSeparateAppends() {
        var buffer = AudioRingBuffer(capacity: 4)
        buffer.append([1, 2, 3])
        buffer.append([4, 5])

        XCTAssertEqual(buffer.lastSamples(4), [2, 3, 4, 5])
        XCTAssertEqual(buffer.lastSamples(2), [4, 5])
    }

    func testHandlesChunkLargerThanCapacity() {
        var buffer = AudioRingBuffer(capacity: 3)
        buffer.append([1, 2, 3, 4, 5, 6, 7])

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.lastSamples(3), [5, 6, 7])
    }

    func testRemoveAllEmptiesBuffer() {
        var buffer = AudioRingBuffer(capacity: 4)
        buffer.append([1, 2, 3])
        buffer.removeAll()

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.lastSamples(3), [])
    }
}
