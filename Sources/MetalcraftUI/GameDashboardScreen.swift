import NeuralEngineKit
import RenderKit
import SimulationKit
import SwiftUI
import WorldKit

public struct GameDashboardScreen: View {
    private let world: WorldSnapshot
    private let factory: FactorySnapshot
    private let renderer: VoxelRenderer
    private let silicon: AppleSiliconProfile
    private let stackEntries: [AppleStackEntry]

    @State private var neuralCenter: NeuralWorkloadCenter

    public init() {
        let world = WorldBootstrap.demoWorld()
        self.world = world
        self.factory = FactoryBootstrap.demoFactory()
        self.renderer = VoxelRenderer(world: world)
        self.silicon = AppleSiliconProfile.current(preferredChipName: "M1 Pro")
        self.stackEntries = AppleStackEntry.roadmap
        _neuralCenter = State(initialValue: NeuralWorkloadCenter(preferredComputeUnits: .cpuAndNeuralEngine))
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.08),
                    Color(red: 0.05, green: 0.11, blue: 0.16),
                    Color(red: 0.09, green: 0.15, blue: 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(spacing: 18) {
                leftRail
                    .frame(width: 320)

                centerStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                rightRail
                    .frame(width: 340)
            }
            .padding(18)
        }
        .task {
            neuralCenter.startDemoLoop()
        }
        .onDisappear {
            neuralCenter.stop()
        }
    }

    private var leftRail: some View {
        ScrollView {
            VStack(spacing: 16) {
                PanelCard(title: "Apple-Native Build", subtitle: silicon.summaryLine) {
                    Text("Latest public Apple cycle is WWDC25/Xcode 26 as of March 9, 2026. The runtime stack is ordered from newest public SDKs back to the Apple Silicon baseline from 2020.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Divider()
                        .overlay(.white.opacity(0.08))

                    ForEach(stackEntries) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.cycle)
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(Color(red: 0.96, green: 0.78, blue: 0.27))
                            Text(entry.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(entry.rationale)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }

                PanelCard(title: "Inventory", subtitle: "Simple survival crafting: ingredients in inventory unlock recipes") {
                    ForEach(factory.inventory.stacks.prefix(8)) { stack in
                        HStack {
                            Text(stack.kind.displayName)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Spacer()
                            Text("\(stack.amount)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.58, green: 0.86, blue: 0.96))
                        }
                    }
                }

                PanelCard(title: "World Breakdown", subtitle: "\(world.blocks.count) total blocks • seed \(world.seed)") {
                    ForEach(world.materialBreakdown.prefix(6), id: \.material) { row in
                        HStack {
                            Circle()
                                .fill(color(for: row.material.color))
                                .frame(width: 10, height: 10)
                            Text(row.material.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Spacer()
                            Text("\(row.count)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var centerStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.10, blue: 0.14),
                            Color(red: 0.02, green: 0.04, blue: 0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )

            VoxelViewport(renderer: renderer)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(1)

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Metalcraft")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                        Text("Voxel survival + factory prototype on Apple Silicon")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Capsule()
                        .fill(Color.black.opacity(0.42))
                        .overlay(
                            Text("MetalKit instancing • \(renderer.renderDiagnostics)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 0.77, green: 0.93, blue: 1.0))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        )
                        .fixedSize()
                }

                Spacer()

                HStack {
                    legendCard
                    Spacer()
                }
            }
            .padding(26)
        }
    }

    private var rightRail: some View {
        ScrollView {
            VStack(spacing: 16) {
                PanelCard(title: "Power Grid", subtitle: "\(factory.powerGrid.networks) isolated networks") {
                    HStack {
                        MetricBadge(title: "Generation", value: "\(Int(factory.powerGrid.generationKW)) kW", accent: Color(red: 0.40, green: 0.95, blue: 0.54))
                        MetricBadge(title: "Load", value: "\(Int(factory.powerGrid.loadKW)) kW", accent: Color(red: 1.0, green: 0.55, blue: 0.37))
                    }

                    Gauge(value: factory.powerGrid.utilization, in: 0...1) {
                        Text("Grid Utilization")
                    } currentValueLabel: {
                        Text("\(Int(factory.powerGrid.utilization * 100))%")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(
                        Gradient(colors: [
                            Color(red: 0.46, green: 0.88, blue: 0.52),
                            Color(red: 1.0, green: 0.74, blue: 0.29),
                        ])
                    )

                    HStack {
                        Text("Headroom")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(factory.powerGrid.headroomKW)) kW")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }

                    HStack {
                        Text("Battery Buffer")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(factory.powerGrid.storageBufferKWh)) kWh")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                }

                PanelCard(title: "Crafting", subtitle: "Available recipes are inferred directly from inventory state") {
                    ForEach(factory.availableRecipes.prefix(6)) { availability in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(availability.recipe.name)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Spacer()
                                Text(availability.recipe.station.displayName)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }

                            if availability.isCraftable {
                                Text("Ready to craft")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color(red: 0.47, green: 0.93, blue: 0.62))
                            } else {
                                Text(missingText(for: availability))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.47))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }

                PanelCard(title: "Neural Workloads", subtitle: neuralCenter.computeUnitsLabel) {
                    Gauge(value: neuralCenter.estimatedUtilization, in: 0...1) {
                        Text("Estimated ANE Pressure")
                    } currentValueLabel: {
                        Text("\(Int(neuralCenter.estimatedUtilization * 100))%")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(
                        Gradient(colors: [
                            Color(red: 0.45, green: 0.79, blue: 1.0),
                            Color(red: 0.96, green: 0.79, blue: 0.32),
                        ])
                    )

                    ForEach(neuralCenter.tasks) { task in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(task.kind.displayName)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                Spacer()
                                Text("\(Int(task.dutyCycle * 100))%")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.78, green: 0.94, blue: 1.0))
                            }

                            ProgressView(value: task.dutyCycle)
                                .tint(Color(red: 0.42, green: 0.82, blue: 1.0))

                            HStack {
                                Text(task.modelName)
                                Spacer()
                                Text(String(format: "%.1f ms", task.latencyMS))
                            }
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                            Text(task.kind.explanation)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Text(neuralCenter.note)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var legendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prototype Slice")
                .font(.system(size: 14, weight: .black, design: .rounded))
            Text("Core loop split into separate world, simulation, render and neural modules. The renderer stays intentionally small; Apple frameworks do the heavy lifting everywhere else.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                MiniLegend(color: Color(red: 0.33, green: 0.63, blue: 0.30), label: "Terrain")
                MiniLegend(color: Color(red: 0.92, green: 0.83, blue: 0.23), label: "Power")
                MiniLegend(color: Color(red: 0.96, green: 0.54, blue: 0.26), label: "Smelting")
            }
        }
        .padding(16)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func missingText(for availability: CraftAvailability) -> String {
        let missing = availability.missingInputs
            .map { "\($0.kind.displayName) x\($0.amount)" }
            .joined(separator: ", ")
        return "Missing: \(missing)"
    }

    private func color(for vector: SIMD4<Float>) -> Color {
        Color(
            red: Double(vector.x),
            green: Double(vector.y),
            blue: Double(vector.z),
            opacity: Double(vector.w)
        )
    }
}

private struct PanelCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.08),
                    Color.white.opacity(0.03),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct MetricBadge: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MiniLegend: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 14, height: 14)
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }
}
