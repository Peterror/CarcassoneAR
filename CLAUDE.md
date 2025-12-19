# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

CarcassoneAR is an iOS AR application that enhances the Carcassonne board game experience. It captures the physical game board, recognizes tiles, tracks game state, and provides assistance (remaining tiles, valid placements, probability calculations).

**Current State:** Phases 1-2 complete. The app captures a max square region from detected horizontal planes and transforms it to a top-down orthogonal view. Images can be exported to Photos for ML training data collection.

**Technology Stack:** ARKit, RealityKit, Core Image, CoreML, SwiftUI, iOS 26+

## Development Phases

1. **Basic structure and AR views** - COMPLETE
2. **Top-down perspective transformation** - COMPLETE
3. **Tile detection using YOLO** - Planned
4. **Tile classification using MobileNetV2** - Planned
5. **Game state and placement validation** - Planned
6. **User-facing helper features** - Planned
7. **Polish and optional scoring** - Future

## Project Structure

```
./CarcassoneAR/CarcassoneAR/    # Source code (nested structure)
├── AppDelegate.swift           # UIKit entry point
├── Models/
│   ├── PlaneData.swift         # Plane geometry
│   └── TransformationModels.swift  # PerspectiveTransform, CapturedFrame
├── Utilities/
│   ├── PerspectiveTransform.swift  # 3D→2D projection, Core Image transform
│   ├── ImageExporter.swift     # Photos Library export
│   └── AppLogger.swift         # os.Logger categories
└── Views/
    ├── ContentView.swift       # Main view controller, mode switching
    ├── AR/ARViewContainer.swift    # ARView wrapper, plane detection
    └── TwoDimensional/View2D.swift # Transformed image display
```

**Build Commands:** Claude should NEVER run builds. User executes all builds.

## Key Architecture Decisions

### ML Pipeline (Planned)

**Tile Detection:** YOLO (not edge detection) for robust detection regardless of board rotation.

**Tile Classification:** Edge-based approach using MobileNetV2 multi-head output:
- 4 edge classifications (field/road/city/river) - one per direction
- 3 binary features: hasShield, hasMonastery, hasSeparatedCities

This approach provides 4× training data multiplication (each tile = 4 edge samples) and better generalization than classifying 84 tile types directly.

### Edge Types

```swift
enum EdgeType: String {
    case field = "F"    // Green grass, connects to fields
    case road = "R"     // White/beige path, must connect to roads
    case city = "C"     // Brown/orange walls, must connect to cities
    case river = "W"    // Blue water, only matches river, placed first
}
```

### Separated Cities

Tiles with multiple city edges can be:
- **Connected:** Cities form single contiguous region (scored together)
- **Separated:** Cities are independent (scored separately)

This distinction is critical for correct game logic and requires ML detection.

### Coordinate Systems

| System | Origin | Y-Direction | Units |
|--------|--------|-------------|-------|
| ARKit World | Session start | Up | Meters |
| Camera Image (Landscape) | Top-left | Down | Pixels |
| Core Image | Bottom-left | Up | Pixels |
| Tile Grid | First tile | +Y = North | Tile positions |

**Key Conversions:**
- ARKit 3D → Image: `ARCamera.projectPoint()`
- UIKit ↔ Core Image: `y' = imageHeight - y`

### Game State Model

```swift
struct BoardState {
    var tiles: [GridPosition: PlacedTile]  // Grid of placed tiles
    var bounds: GridBounds                  // Current board extent
}

struct GridPosition: Hashable {
    let row: Int  // +Y = North
    let col: Int  // +X = East
}
```

## Core Features

### Implemented
- Horizontal plane detection with single-plane locking
- Dynamic capture region (max square fitting in frame)
- Perspective transformation to orthogonal top-down view
- Quality validation (camera angle >20°, all corners visible, resolution)
- Image export to Photos Library with quality metrics in filename

### Planned (Core Priority)
- **Remaining tiles:** Track unplayed tile types and counts
- **Placement hints:** Show valid positions for a tile
- **Probability calculator:** % chance of finding tiles matching edge requirements

### Planned (Future)
- Scoring assistance (potential + current additional points)
- Pawn (meeple) detection and localization
- Save/resume game sessions
- Expansion support beyond base + river

## Performance Targets

| Operation | Target | Acceptable |
|-----------|--------|------------|
| YOLO detection (full board) | <500ms | <1s |
| Full pipeline (80 tiles) | <1s | <2s |
| Memory usage | <250MB | - |

## Development Notes

- **Device Required:** Physical iOS device (Simulator doesn't support ARKit)
- **Logging:** `os.Logger` with subsystem `Peterror.CarcassoneAR`
- **Metal:** Singleton CIContext for GPU-accelerated image processing
- **Xcode:** File system synchronized groups - new files auto-included in build

## Reference Documents

- **TECHNICAL_DESIGN.md:** Complete technical specification with detailed algorithms, data models, and implementation roadmap
- **TILE_CLASSIFICATION.md:** ML model requirements and architecture choices
