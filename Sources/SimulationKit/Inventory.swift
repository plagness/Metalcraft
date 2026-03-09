import Foundation

public enum ItemKind: String, CaseIterable, Codable, Sendable {
    case wood
    case stone
    case coal
    case copperOre
    case ironOre
    case copperIngot
    case ironIngot
    case cable
    case circuitBoard
    case machineFrame
    case batteryCell

    public var displayName: String {
        switch self {
        case .wood: "Wood"
        case .stone: "Stone"
        case .coal: "Coal"
        case .copperOre: "Copper Ore"
        case .ironOre: "Iron Ore"
        case .copperIngot: "Copper Ingot"
        case .ironIngot: "Iron Ingot"
        case .cable: "Cable"
        case .circuitBoard: "Circuit Board"
        case .machineFrame: "Machine Frame"
        case .batteryCell: "Battery Cell"
        }
    }
}

public struct ItemStack: Hashable, Codable, Sendable, Identifiable {
    public let kind: ItemKind
    public let amount: Int

    public var id: String {
        kind.rawValue
    }

    public init(kind: ItemKind, amount: Int) {
        self.kind = kind
        self.amount = amount
    }
}

public struct Inventory: Sendable {
    public private(set) var storage: [ItemKind: Int]

    public init(storage: [ItemKind: Int]) {
        self.storage = storage
    }

    public func amount(of kind: ItemKind) -> Int {
        storage[kind, default: 0]
    }

    public var stacks: [ItemStack] {
        storage
            .map { ItemStack(kind: $0.key, amount: $0.value) }
            .sorted { lhs, rhs in
                if lhs.amount != rhs.amount {
                    return lhs.amount > rhs.amount
                }

                return lhs.kind.rawValue < rhs.kind.rawValue
            }
    }
}

public enum CraftStation: String, Codable, Sendable {
    case hand
    case furnace
    case machineBench

    public var displayName: String {
        switch self {
        case .hand: "Inventory"
        case .furnace: "Furnace"
        case .machineBench: "Machine Bench"
        }
    }
}

public struct Recipe: Hashable, Codable, Sendable, Identifiable {
    public let name: String
    public let station: CraftStation
    public let inputs: [ItemStack]
    public let outputs: [ItemStack]

    public var id: String {
        name
    }

    public init(name: String, station: CraftStation, inputs: [ItemStack], outputs: [ItemStack]) {
        self.name = name
        self.station = station
        self.inputs = inputs
        self.outputs = outputs
    }
}

public struct CraftAvailability: Hashable, Sendable, Identifiable {
    public let recipe: Recipe
    public let missingInputs: [ItemStack]

    public var id: String {
        recipe.id
    }

    public var isCraftable: Bool {
        missingInputs.isEmpty
    }
}

public enum RecipeBook {
    public static let defaultRecipes: [Recipe] = [
        Recipe(
            name: "Copper Smelting",
            station: .furnace,
            inputs: [
                ItemStack(kind: .copperOre, amount: 2),
                ItemStack(kind: .coal, amount: 1),
            ],
            outputs: [
                ItemStack(kind: .copperIngot, amount: 2),
            ]
        ),
        Recipe(
            name: "Iron Smelting",
            station: .furnace,
            inputs: [
                ItemStack(kind: .ironOre, amount: 2),
                ItemStack(kind: .coal, amount: 1),
            ],
            outputs: [
                ItemStack(kind: .ironIngot, amount: 2),
            ]
        ),
        Recipe(
            name: "Copper Cable",
            station: .hand,
            inputs: [
                ItemStack(kind: .copperIngot, amount: 2),
            ],
            outputs: [
                ItemStack(kind: .cable, amount: 4),
            ]
        ),
        Recipe(
            name: "Battery Cell",
            station: .machineBench,
            inputs: [
                ItemStack(kind: .copperIngot, amount: 2),
                ItemStack(kind: .ironIngot, amount: 1),
                ItemStack(kind: .coal, amount: 1),
            ],
            outputs: [
                ItemStack(kind: .batteryCell, amount: 1),
            ]
        ),
        Recipe(
            name: "Machine Frame",
            station: .machineBench,
            inputs: [
                ItemStack(kind: .ironIngot, amount: 4),
                ItemStack(kind: .cable, amount: 2),
            ],
            outputs: [
                ItemStack(kind: .machineFrame, amount: 1),
            ]
        ),
        Recipe(
            name: "Circuit Board",
            station: .machineBench,
            inputs: [
                ItemStack(kind: .copperIngot, amount: 2),
                ItemStack(kind: .cable, amount: 2),
                ItemStack(kind: .stone, amount: 1),
            ],
            outputs: [
                ItemStack(kind: .circuitBoard, amount: 1),
            ]
        ),
    ]

    public static func availability(in inventory: Inventory) -> [CraftAvailability] {
        defaultRecipes.map { recipe in
            let missing = recipe.inputs.compactMap { requirement -> ItemStack? in
                let delta = requirement.amount - inventory.amount(of: requirement.kind)
                return delta > 0 ? ItemStack(kind: requirement.kind, amount: delta) : nil
            }

            return CraftAvailability(recipe: recipe, missingInputs: missing)
        }
    }
}
