# Game Vision

Дата фиксации: 9 марта 2026 года.

## Ключевой поворот

Metalcraft не должен оставаться "нативным приложением с красивой 3D-сценой". Цель проекта теперь формулируется так:

- voxel-industrial sandbox;
- industrial-first progression;
- world-first automation;
- Apple-native implementation.

Это означает, что главный интерфейс проекта должен быть игрой, а не панелью аналитики. Любая телеметрия Apple Silicon, Core ML или Neural Engine остаётся debug/tooling-функцией и не заменяет gameplay loop.

## Основные референсы

### Minecraft

Берём:

- изменяемый блоковый мир;
- свободное строительство;
- добычу и placement прямо в пространстве;
- физическое присутствие игрока в мире.

Не ставим в центр:

- голод/ночь/выживание как главную петлю.

### Factorio

Берём:

- throughput mindset;
- bottlenecks;
- power network как производственную задачу;
- масштабирование через автоматизацию.

### Create

Берём:

- механическую кинематику в мире;
- shafts, gears, belts, deployers, contraptions;
- понятную визуально фабрику;
- нагрузку сети как видимую механику.

### Mekanism

Берём:

- глубокую переработку руд и материалов;
- tiered machines;
- item/fluid/gas/power networks;
- side configuration и routing.

### IC2

Берём:

- инженерную энергосистему;
- tiers/voltage/losses/storage/transformers;
- риск неправильной разводки;
- ранний industrial progression через generator -> processing -> electric automation.

## Целевой игровой цикл

1. Игрок добывает стартовые ресурсы вручную.
2. Собирает первую механическую инфраструктуру.
3. Запускает раннюю переработку и простые линии.
4. Переходит на электрические сети и буферизацию энергии.
5. Автоматизирует транспорт и multi-step processing.
6. Масштабирует завод через moving structures, модульные блоки и сложные production chains.

## Что должно ощущаться в игре

- Машины не "существуют в UI", они стоят в мире.
- Предметы и ресурсы текут через реальные линии.
- Энергия ограничивает развитие и заставляет проектировать сеть.
- Ошибки проектирования видны глазами: перегрузка, пробки, нехватка питания, плохая компоновка.
- Постройки и фабричные модули можно быстро создавать из вокселей собственным инструментом.

## Физика и движение

Проект должен поддерживать:

- физику dropped items и движущихся элементов;
- динамические структуры/contraptions;
- переносимые и вращающиеся агрегаты;
- разрушение/сборку структур без ручного переписывания mesh под каждую новую конструкцию.

Это требует отдельного simulation-слоя для:

- rigid assemblies;
- joints/rotation;
- collision volumes;
- block-to-structure promotion, когда набор блоков становится движущимся объектом.

## Внутренний voxel authoring tool

Нужен лёгкий встроенный инструмент, который позволяет:

- быстро набрасывать 3D voxel-формы;
- собирать корпуса машин, декоративные блоки и prefab-модули;
- преобразовывать визуальную идею в voxel blueprint;
- сохранять шаблоны как игровые prefabs.

Минимальный первый вариант:

- orthographic editor;
- paint/erase/fill/eyedropper;
- palette материалов;
- symmetry/mirror;
- экспорт в JSON/asset bundle blueprint.

## Следующие продуктовые модули

- `PlayerKit`: controller, input, interaction, tools, hotbar.
- `AutomationKit`: machines, kinetic network, electric network, logistics.
- `PhysicsKit`: moving structures, rigid assemblies, collision and motion.
- `VoxelAuthoringKit`: in-engine voxel editing and prefab export.
- `HUDKit`: игровой HUD, inventory, crafting, machine inspector, overlays.

## Ближайший вертикальный срез

Первый действительно правильный vertical slice должен содержать:

- игровой controllable character;
- placement/breaking блоков;
- hotbar и inventory;
- механический источник энергии;
- belts/shafts/gears;
- одну-две processing machines;
- простой in-world machine inspector;
- базовую moving contraption или вращающуюся сборку.
