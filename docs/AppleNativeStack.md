# Apple-Native Stack for Metalcraft

Дата фиксации: 9 марта 2026 года.

Важно: на эту дату WWDC26 ещё не прошла. Самый новый публичный цикл Apple SDK сейчас относится к WWDC25: Xcode 26, macOS 26, iOS 26 и связанные API. Поэтому ниже стек идёт от самого нового публично доступного цикла к более старым.

## 2025 cycle (актуальный публичный максимум на 2026-03-09)

- `Metal 4`: основной вектор для высокопроизводительного rendering/compute на Apple Silicon. Для проекта это база под future chunk meshing, GPU-driven culling и frame generation/upscaling pipeline. Источник: WWDC25 `Discover Metal 4`.
- `SwiftUI` latest scene/window APIs: быстрый native shell, debug overlays, inspector panels и tooling без AppKit boilerplate. Источник: WWDC25 `What’s new in SwiftUI`.
- `Core ML` latest API family, включая tensor-oriented workflow: слой ML orchestration для terrain heuristics, factory advisor, ore prospecting, path heatmaps. Источник: WWDC25 Platforms State of the Union и `What’s new in machine learning`.
- `Managed Background Assets`: докачка тяжёлых наборов данных, world seeds, model packs и texture bundles без собственного patcher-а. Источник: WWDC25 `What’s new in games`.
- `Game Porting Toolkit 3`: не для финального рантайма, а для reference-профилирования, сравнения input/render loops и изучения game workloads на Mac. Источник: WWDC25 `What’s new in games`.

## 2024 cycle

- `RealityKit` low-level mesh/texture control: полезен для editor/tooling, object previews и возможного spatial companion, но не обязателен для core voxel renderer. Источник: WWDC24 Platforms State of the Union.
- `Object Capture`: можно использовать для оффлайн-пайплайна редких industrial props и декоративных объектов. Источник: WWDC24 Platforms State of the Union.
- `Metal debugging + Apple GPU profiling` в Xcode: обязательный dev-loop для chunk meshing и memory pressure на unified memory.

## 2023 cycle

- `Game Porting Toolkit`: полезен как исследовательский слой для анализа PC factory/survival workflows и input/render assumptions на Mac. Источник: WWDC23.
- `SwiftUI + Observation` era: хороший базовый стек для editor/debug UI и in-game telemetry shell.

## 2022 cycle

- `Metal 3`: fast resource loading, pipeline evolution, upscaling foundation. Это минимальный практический baseline для рендера voxel/factory мира. Источник: WWDC22 `What’s new in Metal`.
- `MetalFX`: upscale/AA путь для dense factory scenes. Источник: Apple Developer documentation for MetalFX.
- `Create ML Components`: оффлайн-подготовка моделей/пайплайнов для gameplay assistance и world analysis.

## 2021 cycle

- `RealityKit 2`: зрелая high-level 3D integration, полезна для tools/preview, но core world renderer лучше держать на MetalKit ради контроля над chunk buffers. Источник: WWDC21 Platforms State of the Union.
- `PHASE`: spatial audio для фабрик, машин, генераторов, рельс и подземных производственных линий. Источник: PHASE overview on Apple Developer.
- `GameplayKit`: всё ещё полезен для state machines, noise, agents и rule systems, если потребуется без изобретения велосипеда.
- `Swift Concurrency`: обязательная основа для background simulation, async streaming и ML job scheduling.

## 2020 cycle

- `Apple Silicon + unified memory`: архитектурная база проекта. Chunk data, render buffers и ML workloads нужно проектировать под единый memory pool, а не под дискретный CPU/GPU split.
- `Core ML on Apple Silicon`: главный публичный путь для использования Neural Engine без ручного низкоуровневого кода.
- `Accelerate / BNNS / MPSGraph`: вспомогательные compute-блоки для численных задач, когда полноценная Core ML модель избыточна.

## Практический выбор для первого production-среза

1. `SwiftUI` для shell, HUD, debug/telemetry panels.
2. `MetalKit` для core voxel viewport.
3. `Core ML` для ANE-bound задач.
4. `GameController` для native input.
5. `PHASE` для industrial spatial audio.
6. `MetricKit` + Xcode/Instruments для post-run performance analysis.

## Важное ограничение

Прямой и публично документированный live API для точного отображения загрузки Neural Engine по ядрам приложению не предоставлен. На практике безопасный путь такой:

- в рантайме показывать оценочную телеметрию по Core ML tasks;
- в дев-цикле подтверждать картину через Xcode performance reports и Instruments.

## Источники

- [WWDC25 Platforms State of the Union](https://developer.apple.com/videos/play/wwdc2025/102/)
- [WWDC25 What’s new in SwiftUI](https://developer.apple.com/videos/play/wwdc2025/256/)
- [WWDC25 Discover Metal 4](https://developer.apple.com/videos/play/wwdc2025/302/)
- [WWDC25 What’s new in machine learning](https://developer.apple.com/videos/play/wwdc2025/310/)
- [WWDC25 What’s new in games](https://developer.apple.com/videos/play/wwdc2025/291/)
- [MetalFX documentation](https://developer.apple.com/documentation/metalfx)
- [Machine learning overview](https://developer.apple.com/machine-learning/)
- [PHASE overview](https://developer.apple.com/documentation/phase)
- [GameplayKit](https://developer.apple.com/documentation/gameplaykit)
