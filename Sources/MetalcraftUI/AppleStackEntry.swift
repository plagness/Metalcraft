import Foundation

public struct AppleStackEntry: Identifiable, Hashable, Sendable {
    public let cycle: String
    public let title: String
    public let rationale: String

    public var id: String {
        cycle + title
    }

    public init(cycle: String, title: String, rationale: String) {
        self.cycle = cycle
        self.title = title
        self.rationale = rationale
    }

    public static let roadmap: [AppleStackEntry] = [
        AppleStackEntry(
            cycle: "2025",
            title: "Metal 4 + latest SwiftUI",
            rationale: "Primary render path, tools shell, debug overlays, and future GPU-driven world streaming."
        ),
        AppleStackEntry(
            cycle: "2024",
            title: "RealityKit tooling + Object Capture",
            rationale: "Optional pipeline for editor previews, scanned props, and companion spatial experiences."
        ),
        AppleStackEntry(
            cycle: "2023",
            title: "Observation + game tooling",
            rationale: "Fast native telemetry UI and reactive simulation dashboards without monolithic AppKit glue."
        ),
        AppleStackEntry(
            cycle: "2022",
            title: "Metal 3 + MetalFX",
            rationale: "Streaming foundation and upscale path for heavy factory scenes."
        ),
        AppleStackEntry(
            cycle: "2021",
            title: "PHASE + Swift Concurrency",
            rationale: "Industrial spatial audio and async simulation/streaming jobs."
        ),
        AppleStackEntry(
            cycle: "2020",
            title: "Apple Silicon + Core ML",
            rationale: "Unified memory and Neural Engine-first ML orchestration on M1 Pro."
        ),
    ]
}
