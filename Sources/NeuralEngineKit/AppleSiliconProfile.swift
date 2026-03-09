import CoreML
import Foundation

public struct AppleSiliconProfile: Sendable {
    public let chipName: String
    public let unifiedMemoryGB: Int
    public let logicalCPUCores: Int
    public let activeCPUCores: Int
    public let defaultComputeUnits: MLComputeUnits

    public init(
        chipName: String,
        unifiedMemoryGB: Int,
        logicalCPUCores: Int,
        activeCPUCores: Int,
        defaultComputeUnits: MLComputeUnits
    ) {
        self.chipName = chipName
        self.unifiedMemoryGB = unifiedMemoryGB
        self.logicalCPUCores = logicalCPUCores
        self.activeCPUCores = activeCPUCores
        self.defaultComputeUnits = defaultComputeUnits
    }

    public static func current(preferredChipName: String = "Apple Silicon") -> AppleSiliconProfile {
        let processInfo = ProcessInfo.processInfo
        let bytesPerGB = Double(1_073_741_824)
        let memoryGB = Int((Double(processInfo.physicalMemory) / bytesPerGB).rounded())

        return AppleSiliconProfile(
            chipName: preferredChipName,
            unifiedMemoryGB: max(memoryGB, 1),
            logicalCPUCores: processInfo.processorCount,
            activeCPUCores: processInfo.activeProcessorCount,
            defaultComputeUnits: .all
        )
    }

    public var summaryLine: String {
        "\(chipName) • \(unifiedMemoryGB) GB unified memory • \(activeCPUCores)/\(logicalCPUCores) CPU cores active"
    }
}
