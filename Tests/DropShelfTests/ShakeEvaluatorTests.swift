import XCTest
@testable import DropShelf

final class ShakeEvaluatorTests: XCTestCase {
    func testHorizontalShakeDetected() {
        let config = ShakeAnalysisInput(
            requiredDirectionChanges: 3,
            minimumSegmentDistance: 18,
            timeWindow: 0.48
        )

        // Rapid left-right-left-right movement
        let samples: [CursorSample] = [
            CursorSample(point: CGPoint(x: 100, y: 200), timestamp: 0.00),
            CursorSample(point: CGPoint(x: 135, y: 202), timestamp: 0.06),
            CursorSample(point: CGPoint(x: 95,  y: 199), timestamp: 0.14),
            CursorSample(point: CGPoint(x: 140, y: 201), timestamp: 0.22),
            CursorSample(point: CGPoint(x: 90,  y: 200), timestamp: 0.30)
        ]

        XCTAssertTrue(ShakeEvaluator.isShakeDetected(samples: samples, config: config))
    }

    func testStraightLineDragDoesNotTriggerShake() {
        let config = ShakeAnalysisInput(
            requiredDirectionChanges: 3,
            minimumSegmentDistance: 18,
            timeWindow: 0.48
        )

        // Smooth diagonal drag across screen
        let samples: [CursorSample] = [
            CursorSample(point: CGPoint(x: 100, y: 100), timestamp: 0.00),
            CursorSample(point: CGPoint(x: 150, y: 130), timestamp: 0.08),
            CursorSample(point: CGPoint(x: 210, y: 170), timestamp: 0.16),
            CursorSample(point: CGPoint(x: 280, y: 220), timestamp: 0.24),
            CursorSample(point: CGPoint(x: 360, y: 280), timestamp: 0.32)
        ]

        XCTAssertFalse(ShakeEvaluator.isShakeDetected(samples: samples, config: config))
    }

    func testMicroJitterDoesNotTriggerShake() {
        let config = ShakeAnalysisInput(
            requiredDirectionChanges: 3,
            minimumSegmentDistance: 18,
            timeWindow: 0.48
        )

        // Tiny hand tremor (< 18pt)
        let samples: [CursorSample] = [
            CursorSample(point: CGPoint(x: 200, y: 200), timestamp: 0.00),
            CursorSample(point: CGPoint(x: 206, y: 200), timestamp: 0.05),
            CursorSample(point: CGPoint(x: 198, y: 201), timestamp: 0.10),
            CursorSample(point: CGPoint(x: 205, y: 199), timestamp: 0.15),
            CursorSample(point: CGPoint(x: 199, y: 200), timestamp: 0.20)
        ]

        XCTAssertFalse(ShakeEvaluator.isShakeDetected(samples: samples, config: config))
    }
}
