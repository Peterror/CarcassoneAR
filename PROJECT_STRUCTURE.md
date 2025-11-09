# CarcassoneAR Project Structure

## Overview

This document describes the organization of the CarcassoneAR iOS application codebase.

## Directory Structure

```
CarcassoneAR/
├── CarcassoneAR/
│   ├── Models/                      # Data models and structures
│   │   ├── PlaneData.swift          # AR plane geometry data
│   │   └── TransformationModels.swift # Perspective transformation models
│   │
│   ├── Views/                       # SwiftUI views
│   │   ├── ContentView.swift        # Main app view
│   │   ├── AR/                      # AR-related views
│   │   │   ├── ARViewContainer.swift      # AR camera and plane detection
│   │   │   └── CornerMarkersOverlay.swift # Corner visualization overlay
│   │   └── TwoDimensional/          # 2D views
│   │       └── View2D.swift         # Captured image view
│   │
│   ├── Utilities/                   # Helper utilities and algorithms
│   │   └── PerspectiveTransform.swift # Transformation calculations
│   │
│   ├── AppDelegate.swift            # Application delegate
│   │
│   └── Info.plist                   # App configuration
│
├── CLAUDE.md                        # Development guidelines for Claude
├── PLAN.md                          # Development roadmap
├── TECHNICAL_DESIGN.md              # Technical architecture documentation
├── STEP_9_TESTING.md                # Testing guide for Step 9
└── PROJECT_STRUCTURE.md             # This file

```

## Module Descriptions

### Models/

Data structures representing the application's domain models.

- **PlaneData.swift**
  - `PlaneData` - Stores detected AR plane information (dimensions, position, transform)

- **TransformationModels.swift**
  - `PerspectiveTransform` - Transformation data for perspective correction
  - `TransformQuality` - Quality metrics and validation
  - `CapturedFrame` - Complete captured image with metadata

### Views/

SwiftUI views organized by functionality.

#### Main Views
- **ContentView.swift**
  - Main application view
  - State management for AR/2D view modes
  - UI layout and button controls

#### AR/
AR-specific view components.

- **ARViewContainer.swift**
  - UIViewRepresentable wrapper for RealityKit ARView
  - Plane detection delegate
  - Camera capture coordinator
  - Plane visualization management

- **CornerMarkersOverlay.swift**
  - SwiftUI Canvas overlay
  - Displays projected corner markers on AR camera view
  - Shows yellow quadrilateral outline

#### TwoDimensional/
2D view components.

- **View2D.swift**
  - Displays captured camera image
  - Shows corner markers overlay
  - Quality indicators
  - Return to AR button

### Utilities/

Helper classes and algorithms.

- **PerspectiveTransform.swift**
  - `PerspectiveTransformCalculator` - Calculates 3D to 2D projections
  - `ImageTransformProcessor` - Applies Core Image perspective correction
  - Corner calculation and validation
  - Quality assessment

## Key Features by Module

### Plane Detection (ARViewContainer)
- Locks onto first detected horizontal plane
- Fixed 20cm × 20cm capture region
- Real-time corner projection updates
- Green plane visualization with cyan center cursor

### Image Capture (ARViewContainer.Coordinator)
- Captures camera frame in portrait orientation
- Calculates perspective transformation
- Rotates coordinates to match image orientation
- Stores complete frame metadata

### Perspective Transformation (PerspectiveTransform)
- Calculates plane corners in 3D world space
- Projects to 2D camera pixel coordinates
- Validates transformation quality
- Applies Core Image perspective correction

### Corner Visualization (CornerMarkersOverlay + View2D)
- Shows real-time corner positions in AR view
- Displays corner markers on captured image
- Yellow outline shows transformation region
- Red circles mark exact corner positions

## Data Flow

```
1. AR Plane Detection
   ARSession → PlaneDetectionDelegate → PlaneData

2. Corner Calculation
   PlaneData → PerspectiveTransformCalculator → corners3D → corners2D

3. Camera Capture
   ARFrame → captureCameraFrameWithTransform() → CapturedFrame

4. Perspective Transformation
   CapturedFrame → ImageTransformProcessor → Transformed Image

5. Display
   ContentView ← ARViewContainer/View2D ← State Updates
```

## Configuration

### Fixed Parameters
- **Capture region**: 20cm × 20cm (0.2m × 0.2m)
- **Minimum plane size**: 40cm × 40cm (for detection)
- **Output image**: 1024px max width
- **Camera orientation**: Portrait (.right rotation)

### Quality Thresholds
- **Good angle**: > 20° from horizontal
- **Minimum resolution**: > 50 pixels/meter
- **All corners visible**: Within camera frame

## Build Configuration

See `CLAUDE.md` for build commands and development setup.

## Testing

See `STEP_9_TESTING.md` for detailed testing procedures.

## Architecture Patterns

- **MVVM-inspired**: Separation of views, models, and logic
- **SwiftUI**: Declarative UI framework
- **RealityKit**: AR rendering and plane detection
- **ARKit**: Camera tracking and plane anchors
- **Core Image**: Image processing and transformation

## Future Enhancements

See `PLAN.md` Steps 10-15 for planned features:
- Live transformation mode
- Orientation lock
- Zoom/pan controls
- Enhanced image quality
- Annotation tools
- Export functionality
