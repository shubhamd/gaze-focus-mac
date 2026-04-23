import XCTest
@testable import GazeFocus

final class CursorEngineTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        #if DEBUG
        CursorEngine.threadCheckHook = nil
        #endif
        CursorEngine.warpHandler = { point in
            CGWarpMouseCursorPosition(point)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    // AC-EDGE-04
    func testSortedDisplaysAreLeftToRight() {
        let inputs = [
            DisplayFrame(id: 0, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080)),
            DisplayFrame(id: 1, frame: CGRect(x: 0,    y: 0, width: 1920, height: 1080)),
            DisplayFrame(id: 2, frame: CGRect(x: 3840, y: 0, width: 1920, height: 1080))
        ]
        let sorted = CursorEngine.sorted(inputs)
        XCTAssertEqual(sorted.map { $0.id }, [1, 0, 2])
        XCTAssertEqual(sorted.map { $0.frame.minX }, [0, 1920, 3840])
    }

    func testSortedDisplaysWithNegativeOrigin() {
        // Screen positioned to the left of the primary (negative X).
        let inputs = [
            DisplayFrame(id: 0, frame: CGRect(x: 0,     y: 0, width: 1920, height: 1080)),
            DisplayFrame(id: 1, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        ]
        let sorted = CursorEngine.sorted(inputs)
        XCTAssertEqual(sorted.map { $0.id }, [1, 0])
    }

    // AC-CURSOR-01
    func testWarpObservesNonMainThread() {
        #if DEBUG
        let observed = Atomic<[Bool]>([])
        CursorEngine.threadCheckHook = { isMain in observed.append(isMain) }

        let didWarp = Atomic<Int>(0)
        CursorEngine.warpHandler = { _ in didWarp.increment() }

        let bgExpectation = expectation(description: "background call")
        DispatchQueue.global(qos: .userInitiated).async {
            CursorEngine.warpCursor(to: DisplayFrame(id: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100)))
            bgExpectation.fulfill()
        }
        wait(for: [bgExpectation], timeout: 2.0)

        let mainExpectation = expectation(description: "main call")
        DispatchQueue.main.async {
            CursorEngine.warpCursor(to: DisplayFrame(id: 0, frame: CGRect(x: 0, y: 0, width: 100, height: 100)))
            mainExpectation.fulfill()
        }
        wait(for: [mainExpectation], timeout: 2.0)

        XCTAssertEqual(observed.value, [false, true],
                       "thread check hook should observe bg first, then main")
        XCTAssertEqual(didWarp.value, 1,
                       "warpHandler should only fire on the main-thread call")
        #else
        throw XCTSkip("Thread-check hook is DEBUG-only")
        #endif
    }

    func testWarpCoordinateFlip() {
        // Display at origin (0, 0), width=1000, height=600.
        // AppKit midX = 500, midY = 300.
        // CG target = (500, mainHeight - 300).
        let mainHeight = CGFloat(CGDisplayPixelsHigh(CGMainDisplayID()))
        let captured = Atomic<CGPoint?>(nil)
        CursorEngine.warpHandler = { point in captured.set(point) }

        let exp = expectation(description: "warp")
        DispatchQueue.main.async {
            CursorEngine.warpCursor(to: DisplayFrame(
                id: 0,
                frame: CGRect(x: 0, y: 0, width: 1000, height: 600)
            ))
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)

        let pt = try? XCTUnwrap(captured.value)
        XCTAssertEqual(pt?.x, 500)
        XCTAssertEqual(pt?.y, mainHeight - 300)
    }
}

// MARK: - Thread-safe test helper

private final class Atomic<T> {
    private var _value: T
    private let lock = NSLock()

    init(_ initial: T) { _value = initial }

    var value: T {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func set(_ newValue: T) {
        lock.lock(); defer { lock.unlock() }
        _value = newValue
    }
}

private extension Atomic where T == Int {
    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
}

private extension Atomic where T == [Bool] {
    func append(_ b: Bool) {
        lock.lock(); defer { lock.unlock() }
        _value.append(b)
    }
}
