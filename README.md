# Metalcraft

Нативная Apple Silicon voxel-industrial sandbox игра под macOS. Ближайший ориентир не "dashboard с рендером", а playable смесь Minecraft, Factorio, Create, Mekanism и IC2: разрушаемый мир, индустриальные цепочки, физические машины, логистика, энергия и автоматизация.

## Что внутри сейчас

- `MetalcraftApp`: точка входа приложения.
- `WorldKit`: воксельный мир, блоки, chunk/world snapshot, демо-генерация мира.
- `SimulationKit`: инвентарь, рецепты, базовая энергетика и фабричные узлы.
- `NeuralEngineKit`: Core ML workload orchestration и оценочная телеметрия ANE-нагрузки.
- `RenderKit`: минимальный MetalKit renderer для voxel-сцены.
- `MetalcraftUI`: SwiftUI shell, панель телеметрии, crafting/power dashboard.

## Куда проект идёт

- `industrial-first`: фабрики, энергия, переработка и логистика важнее survival-механик.
- `physical factories`: машины, ремни, валы, кабели и moving structures должны жить прямо в мире.
- `voxel-native tooling`: нужен внутренний инструмент для быстрого рисования/сборки новых voxel-построек и машинных корпусов.
- `apple-native acceleration`: Metal/MetalFX/PHASE/Core ML/ANE усиливают игру, но не подменяют игровой цикл.

Подробное видение зафиксировано в [GameVision](docs/GameVision.md).

## Почему не монолит

Рендер, симуляция, AI/ML и UI разделены на отдельные framework targets. Это позволяет:

- масштабировать chunk meshing и симуляцию независимо;
- подключать Core ML/ANE без смешивания с игровым рендером;
- тестировать рецепты и электрические сети отдельно от UI и Metal;
- позже вынести мир, серверную симуляцию или visionOS companion в отдельные продукты.

## Сборка

```bash
xcodegen generate
xcodebuild -project Metalcraft.xcodeproj -scheme MetalcraftApp -configuration Debug build
```

## Документация

- [AppleNativeStack](docs/AppleNativeStack.md)
- [Architecture](docs/Architecture.md)
- [GameVision](docs/GameVision.md)
