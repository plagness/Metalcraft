import Foundation
import WorldKit

public struct MachineNode: Hashable, Sendable, Identifiable {
    public enum Role: String, Sendable {
        case generation
        case smelting
        case storage
        case logistics

        public var displayName: String {
            switch self {
            case .generation: "Generation"
            case .smelting: "Smelting"
            case .storage: "Storage"
            case .logistics: "Logistics"
            }
        }
    }

    public let name: String
    public let role: Role
    public let position: GridPoint
    public let powerDeltaKW: Double

    public var id: String {
        name
    }

    public init(name: String, role: Role, position: GridPoint, powerDeltaKW: Double) {
        self.name = name
        self.role = role
        self.position = position
        self.powerDeltaKW = powerDeltaKW
    }
}

public struct PowerGridOverview: Sendable {
    public let generationKW: Double
    public let loadKW: Double
    public let storageBufferKWh: Double
    public let networks: Int

    public init(generationKW: Double, loadKW: Double, storageBufferKWh: Double, networks: Int) {
        self.generationKW = generationKW
        self.loadKW = loadKW
        self.storageBufferKWh = storageBufferKWh
        self.networks = networks
    }

    public var headroomKW: Double {
        generationKW - loadKW
    }

    public var utilization: Double {
        guard generationKW > 0 else { return 0 }
        return min(loadKW / generationKW, 1.0)
    }
}

public struct FactorySnapshot: Sendable {
    public let inventory: Inventory
    public let machines: [MachineNode]
    public let powerGrid: PowerGridOverview
    public let availableRecipes: [CraftAvailability]

    public init(
        inventory: Inventory,
        machines: [MachineNode],
        powerGrid: PowerGridOverview,
        availableRecipes: [CraftAvailability]
    ) {
        self.inventory = inventory
        self.machines = machines
        self.powerGrid = powerGrid
        self.availableRecipes = availableRecipes
    }
}

public enum FactoryBootstrap {
    public static func demoFactory() -> FactorySnapshot {
        let inventory = Inventory(storage: [
            .wood: 12,
            .stone: 18,
            .coal: 16,
            .copperOre: 10,
            .ironOre: 8,
            .copperIngot: 6,
            .ironIngot: 4,
            .cable: 4,
        ])

        let machines = [
            MachineNode(name: "Steam Dynamo", role: .generation, position: GridPoint(x: 10, y: 6, z: 8), powerDeltaKW: 180),
            MachineNode(name: "Capacitor Bank", role: .storage, position: GridPoint(x: 12, y: 6, z: 8), powerDeltaKW: -12),
            MachineNode(name: "Arc Furnace A", role: .smelting, position: GridPoint(x: 14, y: 6, z: 8), powerDeltaKW: -54),
            MachineNode(name: "Arc Furnace B", role: .smelting, position: GridPoint(x: 15, y: 6, z: 8), powerDeltaKW: -54),
            MachineNode(name: "Belt Spine", role: .logistics, position: GridPoint(x: 18, y: 6, z: 9), powerDeltaKW: -22),
        ]

        let generation = machines.filter { $0.powerDeltaKW > 0 }.reduce(0) { $0 + $1.powerDeltaKW }
        let load = abs(machines.filter { $0.powerDeltaKW < 0 }.reduce(0) { $0 + $1.powerDeltaKW })
        let powerGrid = PowerGridOverview(generationKW: generation, loadKW: load, storageBufferKWh: 640, networks: 2)

        return FactorySnapshot(
            inventory: inventory,
            machines: machines,
            powerGrid: powerGrid,
            availableRecipes: RecipeBook.availability(in: inventory)
        )
    }
}
