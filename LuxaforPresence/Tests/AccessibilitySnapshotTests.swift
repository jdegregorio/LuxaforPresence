import XCTest
@testable import LuxaforPresence

final class AccessibilitySnapshotTests: XCTestCase {
    func testCollectNodes_enforcesOneBudgetAcrossAllApplications() {
        var requestedLimits: [Int] = []
        let node = AXNodeSnapshot(
            role: nil,
            roleDescription: nil,
            label: nil,
            placeholder: nil,
            domIdentifier: nil,
            identifier: nil,
            pid: nil
        )

        let nodes = AccessibilitySnapshotProvider.collectNodes(
            for: [2, 3, 4],
            maxNodes: 3
        ) { requestedCount, remainingBudget in
            requestedLimits.append(remainingBudget)
            return Array(repeating: node, count: requestedCount)
        }

        XCTAssertEqual(nodes.count, 3)
        XCTAssertEqual(requestedLimits, [3, 1])
    }
}
