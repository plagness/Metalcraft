import XCTest
@testable import SimulationKit

final class FactorySimulationTests: XCTestCase {
    func testCopperCableIsCraftableInDemoFactory() {
        let snapshot = FactoryBootstrap.demoFactory()
        let copperCable = snapshot.availableRecipes.first { $0.recipe.name == "Copper Cable" }

        XCTAssertNotNil(copperCable)
        XCTAssertEqual(copperCable?.isCraftable, true)
    }

    func testPowerGridKeepsPositiveHeadroom() {
        let snapshot = FactoryBootstrap.demoFactory()

        XCTAssertGreaterThan(snapshot.powerGrid.generationKW, snapshot.powerGrid.loadKW)
        XCTAssertGreaterThan(snapshot.powerGrid.headroomKW, 0)
        XCTAssertEqual(snapshot.powerGrid.networks, 2)
    }
}
