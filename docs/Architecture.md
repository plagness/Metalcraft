# Architecture

## Цели

- Максимально нативный стек Apple под Apple Silicon.
- Минимальный слой собственного Metal-кода: только viewport, mesh upload, shader pipeline.
- Модульность вместо монолита.
- Подготовка к survival/factory gameplay: провода, энергия, металлообработка, recipes.

## Модули

### `WorldKit`

- Описывает блоки, материалы, координатную сетку и snapshot мира.
- Не знает ничего о SwiftUI, Core ML или Metal.
- Должен стать источником истины для chunk streaming, сохранений и генерации мира.

### `SimulationKit`

- Хранит inventory, recipe book, machine nodes и power grid summary.
- Зависит только от `WorldKit`.
- В дальнейшем сюда уйдут production chains, pipe/wire simulation, heat/fluids и automation logic.

### `NeuralEngineKit`

- Изолирует Core ML и политику compute units.
- Даёт оценочную телеметрию AI-задач: чем заняты ML пайплайны, какая у них latency, какая доля условной NE-нагрузки.
- Не трогает рендер и UI-детали.

### `RenderKit`

- Единственное место, где живёт Metal shader/pipeline код.
- Принимает готовый snapshot мира и переводит его в instance buffer.
- В будущем сюда можно добавить greedy meshing, chunk culling, indirect command buffers и MetalFX.

### `MetalcraftUI`

- Сшивает SwiftUI shell, viewport, telemetry overlays и игровые панели.
- Не знает, как устроены низкоуровневые buffers/shaders.

## Data Flow

1. `WorldKit` создаёт `WorldSnapshot`.
2. `SimulationKit` считает доступные рецепты и состояние power grid.
3. `NeuralEngineKit` ведёт ML workload timeline.
4. `RenderKit` визуализирует snapshot мира.
5. `MetalcraftUI` собирает всё в один macOS dashboard.

## Ограничение по Neural Engine

На текущем публичном Apple API нет надёжного публичного runtime-счётчика, который позволял бы приложению показывать точный live `% utilization` Neural Engine по ядрам. Поэтому в интерфейсе используется оценочная телеметрия:

- активные Core ML workloads;
- требуемые `MLComputeUnits`;
- latency и duty cycle за короткое окно;
- текстовое объяснение, какая задача сейчас занимает ML pipeline.

Для дев-сессий и профилирования стоит использовать Xcode performance reports и Instruments.
