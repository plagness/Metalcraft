> [🇬🇧 English](README.md) | 🇷🇺 **Русский**

<div align="center">

# ⛏ Metalcraft

**Воксельный движок с нуля на Swift + Metal для Apple Silicon**

*Эксперимент: выжать максимум из TBDR-архитектуры GPU Apple — ноль зависимостей, чистая производительность*

<br>

![Скриншот](Screenshots/2026-03-10.png)

<br>

[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![Metal](https://img.shields.io/badge/Metal-API-8A8A8A?style=for-the-badge&logo=apple&logoColor=white)](https://developer.apple.com/metal/)
[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=for-the-badge&logo=macos&logoColor=white)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-M1+-FF3B30?style=for-the-badge&logo=apple&logoColor=white)](https://support.apple.com/en-us/116943)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue?style=for-the-badge)](LICENSE)
[![LOC](https://img.shields.io/badge/Строк_кода-~4600-8B5CF6?style=for-the-badge)]()
[![Dependencies](https://img.shields.io/badge/Зависимости-0-22C55E?style=for-the-badge)]()

</div>

---

## 🔍 О проекте

Это **воксельный движок, написанный с нуля** как эксперимент — насколько далеко можно зайти на одном чипе Apple Silicon, используя только нативные фреймворки.

**Вопрос:** Можно ли построить воксельный рендерер масштаба Minecraft с deferred PBR-освещением, генерацией террейна на GPU и 100K загруженных чанков — используя только Swift и Metal?

**Ответ:** Да. Вот как.

**Ключевые факты:**
- 🏗️ ~4 600 строк кода (14 Swift-файлов + 7 Metal-шейдеров + 1 bridging-заголовок)
- 📦 Ноль внешних зависимостей — только фреймворки Apple
- ⚡ Single-pass deferred рендеринг через tile memory TBDR
- 🌍 Дальность прорисовки 64 чанка с 4-уровневым LOD
- 🎮 Генерация террейна на GPU в реальном времени с 6 биомами

---

## 🏛️ Архитектура

```
┌─────────────────────────────────────────────────────────────────┐
│                     Рендер-пайплайн                             │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────────┐  │
│  │  G-Buffer     │──▶│  Deferred    │──▶│  Вода + Частицы    │  │
│  │  заполнение   │   │  PBR-свет    │   │  (Forward Pass)    │  │
│  │  (Tile SRAM)  │   │  (Tile SRAM) │   │                    │  │
│  └──────────────┘   └──────────────┘   └────────────────────┘  │
│         ▲                                         │             │
│         │                                         ▼             │
│  ┌──────────────┐                      ┌────────────────────┐  │
│  │  Chunk        │                      │  Bloom + Tone Map  │  │
│  │  Manager      │                      │  + Композит        │  │
│  │  + ICB        │                      │  → Drawable        │  │
│  └──────────────┘                      └────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     Compute-пайплайн                            │
│                                                                 │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────────┐  │
│  │  GPU генерация│   │  Симуляция   │   │  Bloom             │  │
│  │  террейна     │   │  частиц      │   │  Extract/Blur/Up   │  │
│  │  (Perlin)     │   │  (8192)      │   │  (Kawase)          │  │
│  └──────────────┘   └──────────────┘   └────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## ⚙️ Ключевые технологии

### 🔲 Single-Pass Deferred Rendering (TBDR)

Главная инновация. На Apple Silicon GPU работает как **Tile-Based Deferred Renderer** — обрабатывает экран маленькими тайлами в быстрой on-chip SRAM.

Движок использует это, храня весь G-Buffer в **tile memory** и никогда не записывая его в DRAM:

| Слой G-Buffer | Формат | Содержимое | Хранение |
|---|---|---|---|
| Attachment 0 | RGBA8 | Albedo (RGB) + Metallic (A) | Только Tile SRAM |
| Attachment 1 | RGBA8 | Normal (RGB) + Roughness (A) | Только Tile SRAM |
| Attachment 2 | RGBA16F | Emission (RGB) + Depth (A) | Только Tile SRAM |
| Attachment 3 | RGBA16F | HDR-результат освещения | DRAM (выход) |

Проход освещения читает G-Buffer через **programmable blending** (`[[color(n)]]`) Metal — напрямую из tile SRAM, без обращений к DRAM.

> **Результат:** экономия ~58 МБ/кадр пропускной способности памяти при 1080p по сравнению с традиционным IMR deferred rendering.

### 🎨 PBR-освещение

Cook-Torrance BRDF:
- **D** — GGX (распределение нормалей)
- **G** — Smith (функция геометрии)
- **F** — Schlick (приближение Френеля)

Источники света:
- ☀️ Направленное солнце (тёплое, высокая интенсивность)
- 💡 16 анимированных точечных источников (HSV-радуга, орбитальные)
- 🌐 Полусферический ambient (градиент небо-земля)
- 🌫️ Атмосферный туман (дистанция + высота)

### 📦 Система чанков

- **Размер чанка:** 16×16×16 вокселей (4 096 блоков)
- **Дальность прорисовки:** 64 чанка (1 024 блока)
- **Макс. загружено:** 100 000 чанков
- **Макс. отрисовка/кадр:** 4 500 чанков
- **Загрузка:** 32 чанка/кадр
- **Мешинг:** 24 чанка/кадр
- **Кольцевая загрузка** — естественный порядок по расстоянию от центра

### 🧊 Система LOD

Пропуск вокселей на основе дистанции для дальних чанков:

| Расстояние | Шаг LOD | Эффективное разрешение |
|---|---|---|
| 0–160 блоков | 1 | Полное 16×16×16 |
| 160–384 блока | 2 | 8×8×8 |
| 384–768 блоков | 4 | 4×4×4 |
| 768–1600 блоков | 8 | 2×2×2 |

### 🔗 Greedy Meshing

Объединяет соседние грани одного типа блоков в крупные четырёхугольники. Кардинально снижает количество вершин.

**Упакованный формат вершины** — всего 16 байт:
```
PackedVoxelVertex (16 байт)
├── position    Float16×3     6 байт
├── normalIdx   UInt8         1 байт  (0–5 для ±X/±Y/±Z)
├── padding     UInt8         1 байт
├── uv          Float16×2     4 байта
└── color       RGBA8         4 байта
```

### 📐 Mega-Buffer + Indirect Command Buffer

Все меши чанков живут в **одном общем буфере**:
- **Вершинный буфер:** 128 МБ (один `MTLBuffer`)
- **Индексный буфер:** 64 МБ (один `MTLBuffer`)
- **Один** вызов `setVertexBuffer` на кадр вместо 4 500

**Indirect Command Buffer (ICB):** 4 500 отдельных `drawIndexedPrimitives` закодированы в один `executeCommandsInBuffer`. Перекодируется только при изменении списка видимых чанков.

### 🌍 GPU Compute генерация террейна

Террейн генерируется целиком на GPU через compute-шейдеры:
- **Perlin noise** (PCG-хэш, детерминированный)
- **6 биомов** с плавным смешиванием: Океан, Равнины, Лес, Пустыня, Горы, Тундра
- **Пещеры** (3D noise с порогом)
- **Расстановка деревьев** с учётом биома
- **Производительность:** в 10–50× быстрее CPU-аналога
- **Память:** `storageModeShared` — zero-copy на unified memory Apple Silicon

### ✨ GPU система частиц

- **8 192 частицы** — симуляция на compute-шейдере
- Физика: гравитация, ветер, время жизни
- Рендер как camera-facing billboards
- Additive + alpha blending

### 🌸 Пост-обработка

- **Bloom:** Kawase blur (5-tap вниз, 9-tap вверх) по 4 mip-уровням
- **Тональная компрессия:** ACES filmic
- **Виньетка** + композит на drawable

---

## 📊 Метрики производительности

| Метрика | Значение |
|---|---|
| Дальность прорисовки | 64 чанка (1 024 блока) |
| Макс. загруженных чанков | 100 000 |
| Макс. отрисовка/кадр | 4 500 |
| Загрузка чанков | 32/кадр |
| Генерация мешей | 24/кадр |
| GPU terrain-задач в полёте | 64 |
| Размер вершины | 16 байт (упакованный) |
| Вершинный mega-buffer | 128 МБ |
| Индексный mega-buffer | 64 МБ |
| Экономия пропускной способности G-Buffer | ~58 МБ/кадр (1080p) |
| GPU-частиц | 8 192 |
| Кадров в полёте | 3 (тройная буферизация) |
| Типов блоков | 27 (с PBR-свойствами) |
| Биомов | 6 (плавное смешивание) |
| Динамических точечных источников | 16 (анимированные, PBR) |
| Bloom-проходов | 4 mip-уровня (Kawase) |

---

## 🧠 Как работает TBDR (и зачем этот движок)

Традиционные GPU (NVIDIA, AMD) используют **Immediate Mode Rendering (IMR)** — обрабатывают треугольники один за другим и записывают результат напрямую в DRAM.

Apple Silicon использует **Tile-Based Deferred Rendering (TBDR)**:

1. GPU делит экран на маленькие тайлы (~32×32 пикселя)
2. Каждый тайл рендерится целиком в **быстрой on-chip SRAM** (tile memory)
3. Только финальный результат пикселя записывается в DRAM

**Почему это важно для deferred rendering:**

На IMR GPU deferred rendering требует:
- **Запись** G-Buffer в DRAM (стоимость пропускной способности)
- **Чтение** G-Buffer обратно для освещения (ещё пропускная способность)
- При 1080p с 3 render targets: ~58 МБ/кадр только на трафик G-Buffer

На Apple Silicon TBDR:
- G-Buffer записывается в **tile memory** (быстрая SRAM)
- Освещение читает G-Buffer из **той же tile memory**
- `storeAction = .dontCare` — G-Buffer **никогда не записывается в DRAM**
- Атрибут Metal `[[color(n)]]` позволяет читать данные в том же render pass

**Результат:** Вся стоимость пропускной способности G-Buffer устранена. Этот движок создан специально для демонстрации этого преимущества.

---

## 🤖 Neural Engine

> **Статус:** Архитектура подготовлена, интеграция в процессе

Проект включает выделенный модуль `NeuralEngine/`, спроектированный для интеграции с Apple Neural Engine (ANE) через CoreML.

**Планируемые возможности:**
- 🔬 **ML-апскейлинг** — рендер в низком разрешении, апскейл через ANE (аналог DLSS/FSR, но на нейронном железе Apple)
- 🎨 **Деноизинг** — шумоподавление в реальном времени для ray-traced проходов
- 🧭 **Предсказание LOD** — ML-выбор LOD на основе траектории камеры
- 🌍 **Улучшение террейна** — нейросетевая генерация мелких деталей ландшафта

**Зачем ANE для воксельного движка?**
Neural Engine в Apple Silicon (до 38 TOPS на M4) работает **независимо от GPU**. ML-инференс для апскейлинга/деноизинга может выполняться **параллельно** с GPU-рендерингом — по сути, бесплатные вычисления для улучшения качества картинки.

Директория `NeuralEngine/Models/` подготовлена для CoreML-моделей (`.mlmodelc`).

---

## 🧰 Фреймворки

| Фреймворк | Назначение |
|---|---|
| `Metal` | GPU-рендеринг и compute-шейдеры |
| `MetalKit` | Управление view, жизненный цикл drawable |
| `simd` | Векторная/матричная математика на CPU |
| `CoreGraphics` | Растеризация текста для отладочного оверлея |
| `CoreText` | Разметка шрифтов для отладочного HUD |
| `Cocoa` | Жизненный цикл приложения, управление окном |
| `QuartzCore` | Точный таймер (`CACurrentMediaTime`) |
| `Foundation` | Базовые типы, dispatch-очереди |

> **Ноль внешних зависимостей.** Без SPM. Без CocoaPods. Без Carthage. Только фреймворки Apple.

---

## 📁 Структура проекта

```
Metalcraft/
├── project.yml                          # Определение проекта XcodeGen
├── Screenshots/                         # Скриншоты билда
├── VoxelEngine/
│   ├── App/                             # Точка входа, окно, контроллер
│   │   ├── main.swift
│   │   ├── AppDelegate.swift
│   │   ├── GameViewController.swift
│   │   └── MetalView.swift
│   ├── Core/                            # Отсчёт времени, delta time
│   ├── Input/                           # Клавиатура + мышь FPS-управление
│   ├── Math/                            # Генерация шума, frustum culling
│   ├── Renderer/                        # Metal-рендерер, камера, mega-buffer
│   │   ├── Renderer.swift               # Основной пайплайн (~600 строк)
│   │   ├── CameraSystem.swift           # FPS-камера, матрицы проекции
│   │   └── MeshAllocator.swift          # Суб-аллокатор mega-buffer
│   ├── Compute/                         # GPU-генерация террейна
│   ├── Voxel/                           # Система чанков, типы блоков, мешинг
│   │   ├── ChunkManager.swift           # Стриминг, LOD, загрузка (~500 строк)
│   │   ├── GreedyMesher.swift           # Оптимизация объединением граней
│   │   ├── BlockRegistry.swift          # 27 типов блоков с PBR-свойствами
│   │   └── WaterMesher.swift            # Прозрачная вода
│   ├── Debug/                           # FPS-оверлей (CoreText → текстура)
│   ├── Shaders/                         # Metal Shading Language
│   │   ├── Common/ShaderTypes.h         # Bridging-типы Swift-Metal
│   │   ├── Deferred/                    # Заполнение G-Buffer + PBR-освещение
│   │   ├── Transparency/               # Forward-проход воды
│   │   ├── Particles/                   # GPU compute + billboard-рендер
│   │   ├── PostProcess/                 # Bloom (Kawase), tone mapping
│   │   ├── Voxel/                       # GPU compute-шейдер террейна
│   │   └── Utility/                     # Полноэкранный треугольник
│   ├── NeuralEngine/                    # [В разработке] CoreML / ANE
│   └── ECS/                             # [В разработке] Entity-Component-System
└── VoxelEngine.xcodeproj/               # Xcode-проект (готов к сборке)
```

---

## 📋 Требования

| Требование | Минимум |
|---|---|
| **Операционная система** | macOS 14.0 (Sonoma) |
| **Железо** | Apple Silicon (M1 / M2 / M3 / M4) |
| **GPU Family** | Metal GPU Family Apple 7+ |
| **Xcode** | 15.0+ |
| **Swift** | 5.9 |

> ⚠️ **Intel Mac не поддерживается.** Движок требует unified memory и TBDR tile memory, доступные только на Apple Silicon.

---

## 🚀 Сборка и запуск

### Вариант A — Напрямую (рекомендуется)

```bash
git clone https://github.com/plagness/Metalcraft.git
cd Metalcraft
open VoxelEngine.xcodeproj
# Нажмите Cmd+R для сборки и запуска
```

### Вариант B — Перегенерация через XcodeGen

```bash
brew install xcodegen
git clone https://github.com/plagness/Metalcraft.git
cd Metalcraft
xcodegen generate
open VoxelEngine.xcodeproj
```

### 🎮 Управление

| Клавиша | Действие |
|---|---|
| `W` `A` `S` `D` | Движение |
| `Мышь` | Осмотр |
| `Пробел` | Вверх |
| `Shift` | Вниз |
| `Tab` | Спринт (5× скорость) |
| `Скролл` | Настройка скорости |
| `Esc` | Захват/отпуск курсора |

---

## 🗺️ Дорожная карта

- [ ] 🤖 Интеграция Neural Engine / CoreML (ANE-апскейлинг, деноизинг)
- [ ] 🏗️ Entity-Component-System архитектура
- [ ] 🔊 Пространственный звук
- [ ] 🌑 Каскадные теневые карты
- [ ] 🖼️ Текстурный атлас
- [ ] 🔦 Ray tracing (Metal ray tracing API)
- [ ] 💾 Сохранение/загрузка мира
- [ ] 🌊 Объёмный туман и облака

---

## 📄 Лицензия

```
Copyright 2026 plagness

Licensed under the Apache License, Version 2.0
```

Полный текст — в файле [LICENSE](LICENSE).
