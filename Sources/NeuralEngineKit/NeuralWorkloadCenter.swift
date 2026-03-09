import CoreML
import Foundation
import Observation

public enum NeuralTaskKind: String, CaseIterable, Sendable, Identifiable {
    case terrainSynthesis
    case oreScoring
    case logisticsForecast
    case smelterAdvisor

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .terrainSynthesis: "Terrain Synthesis"
        case .oreScoring: "Ore Scoring"
        case .logisticsForecast: "Logistics Forecast"
        case .smelterAdvisor: "Smelter Advisor"
        }
    }

    public var explanation: String {
        switch self {
        case .terrainSynthesis: "Chunk heuristics and biome transitions."
        case .oreScoring: "Ore density prediction before exposing a vein."
        case .logisticsForecast: "Conveyor saturation and route pressure estimates."
        case .smelterAdvisor: "Input balancing between furnaces and storage."
        }
    }
}

public struct NeuralTaskSnapshot: Identifiable, Sendable {
    public let id: UUID
    public let kind: NeuralTaskKind
    public let requestedComputeUnits: MLComputeUnits
    public let dutyCycle: Double
    public let latencyMS: Double
    public let modelName: String
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        kind: NeuralTaskKind,
        requestedComputeUnits: MLComputeUnits,
        dutyCycle: Double,
        latencyMS: Double,
        modelName: String,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.requestedComputeUnits = requestedComputeUnits
        self.dutyCycle = dutyCycle
        self.latencyMS = latencyMS
        self.modelName = modelName
        self.updatedAt = updatedAt
    }
}

@MainActor
@Observable
public final class NeuralWorkloadCenter {
    public private(set) var estimatedUtilization: Double
    public private(set) var tasks: [NeuralTaskSnapshot]
    public let preferredComputeUnits: MLComputeUnits
    public let note: String

    @ObservationIgnored
    private var timer: Timer?

    @ObservationIgnored
    private var tick: Int

    public init(preferredComputeUnits: MLComputeUnits = .all) {
        self.preferredComputeUnits = preferredComputeUnits
        self.estimatedUtilization = 0.0
        self.tasks = []
        self.tick = 0
        self.note = "Public Apple APIs do not expose exact live Neural Engine utilization per core. This panel estimates ANE pressure from active Core ML workloads and duty cycle."
        seedWorkloads()
    }

    public func startDemoLoop() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advanceDemoWorkloads()
            }
        }

        timer?.tolerance = 0.15
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public var computeUnitsLabel: String {
        Self.label(for: preferredComputeUnits)
    }

    private func seedWorkloads() {
        let date = Date()
        tasks = [
            NeuralTaskSnapshot(
                kind: .terrainSynthesis,
                requestedComputeUnits: preferredComputeUnits,
                dutyCycle: 0.62,
                latencyMS: 11.4,
                modelName: "terrain-heuristics-v2",
                updatedAt: date
            ),
            NeuralTaskSnapshot(
                kind: .oreScoring,
                requestedComputeUnits: preferredComputeUnits,
                dutyCycle: 0.44,
                latencyMS: 8.9,
                modelName: "ore-scorer-v1",
                updatedAt: date
            ),
            NeuralTaskSnapshot(
                kind: .logisticsForecast,
                requestedComputeUnits: preferredComputeUnits,
                dutyCycle: 0.27,
                latencyMS: 6.3,
                modelName: "belt-forecast-v1",
                updatedAt: date
            ),
            NeuralTaskSnapshot(
                kind: .smelterAdvisor,
                requestedComputeUnits: preferredComputeUnits,
                dutyCycle: 0.31,
                latencyMS: 5.7,
                modelName: "smelter-balancer-v1",
                updatedAt: date
            ),
        ]
        recalculateEstimatedUtilization()
    }

    private func advanceDemoWorkloads() {
        tick += 1
        let now = Date()

        tasks = tasks.enumerated().map { index, task in
            let phase = Double(tick) * 0.42 + Double(index)
            let wave = 0.5 + 0.5 * sin(phase)
            let duty = max(0.08, min(0.96, 0.18 + wave * (0.38 + Double(index) * 0.08)))
            let latency = max(2.8, 4.2 + duty * 13.5 + Double(index) * 1.4)

            return NeuralTaskSnapshot(
                id: task.id,
                kind: task.kind,
                requestedComputeUnits: task.requestedComputeUnits,
                dutyCycle: duty,
                latencyMS: latency,
                modelName: task.modelName,
                updatedAt: now
            )
        }

        recalculateEstimatedUtilization()
    }

    private func recalculateEstimatedUtilization() {
        guard tasks.isEmpty == false else {
            estimatedUtilization = 0
            return
        }

        let weightedLoad = tasks.reduce(0.0) { partial, task in
            let multiplier = task.requestedComputeUnits == .cpuAndNeuralEngine ? 1.15 : 1.0
            return partial + min(task.dutyCycle * multiplier, 1.0)
        }

        estimatedUtilization = min(weightedLoad / Double(tasks.count), 1.0)
    }

    private static func label(for computeUnits: MLComputeUnits) -> String {
        switch computeUnits {
        case .cpuOnly:
            "CPU only"
        case .cpuAndGPU:
            "CPU + GPU"
        case .cpuAndNeuralEngine:
            "CPU + Neural Engine"
        case .all:
            "All compute units"
        @unknown default:
            "Unknown"
        }
    }
}
