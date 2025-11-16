# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CarcassoneAR is an iOS augmented reality application that scans horizontal table surfaces and transforms oblique camera views into orthogonal top-down views using perspective transformation. The app captures a fixed 20cm × 20cm region from detected planes and applies computer vision techniques to create accurate 2D mapped representations. The project uses RealityKit, ARKit, and Core Image with SwiftUI for iOS 26+ AR development.

**Current Status**: Phase 1 complete (Steps 1-8), Step 9 (Perspective Transformation) implemented and functional.

**Project Structure**: Source code is located in `./CarcassoneAR/CarcassoneAR/` (nested directory structure).

@PLAN.md

## Build Commands

**IMPORTANT:** Claude Code should **NEVER** run build commands. Only the user can execute builds.

### Building the project
```bash
xcodebuild -project "CarcassoneAR/CarcassoneAR.xcodeproj" -scheme CarcassoneAR -configuration Debug build
```

### Building for release
```bash
xcodebuild -project "CarcassoneAR/CarcassoneAR.xcodeproj" -scheme CarcassoneAR -configuration Release build
```

### Cleaning build artifacts
```bash
xcodebuild -project "CarcassoneAR/CarcassoneAR.xcodeproj" -scheme CarcassoneAR clean
```

**Note:** These commands are documented for reference only. The user will run all build operations.

## Architecture

### Application Structure

The app uses a UIKit-based AppDelegate (AppDelegate.swift) as the main entry point, which hosts a SwiftUI ContentView via UIHostingController. The application follows a hierarchical SwiftUI architecture with state management for view switching and AR data coordination.

### Core Components (10 Swift files)

#### Main Views
- **ContentView.swift**: Master view controller managing ViewMode state (.ar or .view2D), UI overlays (status, buttons), AR/2D switching, and frame capture coordination
- **View2D.swift**: Displays captured and transformed images with corner markers, quality metrics, and camera angle information
- **ARViewContainer.swift**: UIViewRepresentable wrapper integrating RealityKit ARView with horizontal plane detection and capture functionality

#### Data Models
- **PlaneData.swift**: Stores detected plane geometry (dimensions, position, transform matrix)
- **TransformationModels.swift**: Defines PerspectiveTransform, TransformQuality, and CapturedFrame structures

#### Utilities
- **PerspectiveTransform.swift**: Contains PerspectiveTransformCalculator (3D→2D projection, quality validation) and ImageTransformProcessor (Core Image perspective correction)
- **AppLogger.swift**: Centralized logging configuration using os.Logger with category-specific loggers for structured, filterable debugging
- **SIMDExtensions.swift**: SIMD utility extensions (simd_float4.xyz convenience property)
- **CornerMarkersOverlay.swift**: SwiftUI Canvas overlay component (structure ready for future enhancement)

#### Application Entry
- **AppDelegate.swift**: UIKit application lifecycle management

### ARKit/RealityKit Implementation

The AR experience uses ARKit's ARView (not RealityKit's RealityView) for greater control over camera capture:

- **ARWorldTrackingConfiguration**: Detects horizontal planes with minimum 0.4m × 0.4m bounds
- **Plane Locking**: Locks onto first detected plane, stores as `lockedPlaneID`
- **Fixed Capture Region**: Visualizes and captures 20cm × 20cm window on detected plane
- **Plane Visualization**: Green semi-transparent mesh (60% opacity) with cyan center cursor
- **Spatial Tracking**: ARCamera provides projection matrix for 3D→2D coordinate transformation
- **Entity-Component System**: Uses ModelComponent with MeshResource for plane geometry visualization

### Perspective Transformation Pipeline

The application implements a complete computer vision pipeline for perspective correction:

1. **3D Corner Calculation** (PerspectiveTransformCalculator.calculatePlaneCorners):
   - Converts plane center + dimensions to 4 corner points in world space
   - Applies plane's transform matrix to get global coordinates

2. **2D Projection** (PerspectiveTransformCalculator.projectCornersToImage):
   - Uses ARCamera.projectPoint() to map 3D corners to pixel coordinates
   - Handles coordinate system conversion (ARKit world → camera image)

3. **Quality Validation** (PerspectiveTransformCalculator.evaluateTransformQuality):
   - Camera angle > 20° from horizontal (good quality threshold)
   - All corners visible within image bounds
   - Estimated resolution > 50 pixels/meter

4. **Perspective Correction** (ImageTransformProcessor.applyPerspectiveCorrection):
   - Uses Core Image CIPerspectiveCorrection filter
   - Metal-accelerated GPU processing via singleton CIContext
   - Maintains aspect ratio with max 1024px output width

### Data Flow Architecture

```
ARSession → PlaneDetectionDelegate → PlaneData
                                       ↓
                    PerspectiveTransformCalculator
                          ↓
                    Corners3D → Corners2D → Quality Metrics
                                              ↓
                    CVPixelBuffer → CIImage → CIPerspectiveCorrection
                                              ↓
                            CapturedFrame → View2D Display
```

### State Management

- **@State ViewMode**: Controls AR/2D view switching (.ar, .view2D)
- **@State PlaneData**: Stores detected plane geometry for access across views
- **@State CapturedFrame**: Holds captured image, transformation data, and quality metrics
- **Coordinator Pattern**: ARViewContainer.Coordinator manages AR session lifecycle, plane entities, and camera frame capture
- **Binding Propagation**: Parent-child @Binding connections for data flow between ContentView and child views

### Project Configuration

- **iOS Deployment Target**: iOS 26.0
- **Swift Version**: 5.0
- **Required Device Capabilities**: ARKit
- **Camera Permission**: Required for AR functionality
- **Team ID**: NXL4J6LPXF
- **Bundle Identifier**: Peterror.CarcassoneAR

## Key Features

### Phase 1: AR Plane Detection (Steps 1-8) - COMPLETE
- Live AR camera feed with horizontal plane detection
- Automatic plane locking on first detected surface (locks to `lockedPlaneID`)
- Reset button to clear detection and restart scanning
- 2D button to switch to captured view (disabled until plane detected)
- Real-time scanning status indicator (green dot + text)
- 20cm × 20cm fixed capture region visualization (green mesh + cyan cursor)

### Phase 2: Perspective Transformation (Step 9) - COMPLETE
- **3D→2D Corner Projection**: Maps plane corners from world space to camera image pixels
- **Quality Validation**: Evaluates camera angle (>20°), corner visibility, and resolution (>50 ppm)
- **Perspective Correction**: Applies Core Image CIPerspectiveCorrection filter to transform oblique views to orthogonal
- **Coordinate System Handling**: Converts between ARKit world space, camera space, and UIKit/Core Image coordinate systems
- **Visual Feedback**: Displays corner markers, quality metrics, and camera angle in 2D view

## Development Notes

### Working with Xcode Project Files

This project uses Xcode's file system synchronized groups (PBXFileSystemSynchronizedRootGroup).

**Source Code Location**: `./CarcassoneAR/CarcassoneAR/` (note the nested directory structure)

New Swift files added to `CarcassoneAR/CarcassoneAR/` are automatically included in the build without manual project file updates.

**Directory Structure**:
```
./
├── CarcassoneAR/                    # Xcode project container
│   ├── CarcassoneAR.xcodeproj/     # Xcode project file
│   └── CarcassoneAR/               # Source code directory ← CODE IS HERE
│       ├── AppDelegate.swift
│       ├── Models/
│       ├── Utilities/
│       └── Views/
├── CLAUDE.md
└── PLAN.md
```

### ARKit Development Patterns

**Plane Detection and Locking:**
1. Configure ARWorldTrackingConfiguration with `.horizontal` plane detection
2. Implement ARSessionDelegate's `didAdd` and `didUpdate` methods
3. Lock to first detected plane by storing `planeAnchor.identifier`
4. Create AnchorEntity at locked plane's position using `AnchorEntity(anchor: planeAnchor)`
5. Update visualization only for the locked plane

**Camera Frame Capture:**
1. Access `arView.session.currentFrame?.capturedImage` (CVPixelBuffer)
2. Extract `arView.session.currentFrame?.camera` for projection matrix
3. Convert CVPixelBuffer to CIImage
4. Apply orientation correction (portrait uses `.right` rotation)
5. Process with Core Image filters before display

**3D to 2D Projection:**
1. Calculate plane corners in world space using plane transform and dimensions
2. Use `ARCamera.projectPoint()` to map 3D points to normalized image coordinates (0-1)
3. Scale normalized coordinates to pixel coordinates using image resolution
4. Handle coordinate system differences (ARKit Y-up vs UIKit Y-down)

### Coordinate Systems Reference

**ARKit World Space:** Right-handed, Y-up, Z toward user, origin at session start
**ARKit Camera Space:** Right-handed, Y-down, Z away from camera (into scene)
**UIKit Image Space:** Top-left origin (0,0), Y-down, pixel coordinates
**Core Image Space:** Bottom-left origin (0,0), Y-up, pixel coordinates

**Conversions:**
- ARKit 3D → Camera Image: `ARCamera.projectPoint(worldPoint)`
- UIKit ↔ Core Image: `y' = imageHeight - y`
- Landscape → Portrait: Rotate coordinates by 90° clockwise

### Perspective Transformation Mathematics

**Corner Ordering Convention:**
```
[0] Top-Left      [1] Top-Right
[3] Bottom-Left   [2] Bottom-Right
```

**Quality Thresholds:**
- Minimum camera angle: 20° from horizontal
- Minimum resolution: 50 pixels/meter
- All 4 corners must be visible in frame
- Capture region: 0.2m × 0.2m (20cm × 20cm)
- Output max width: 1024 pixels (maintains aspect ratio)

**Core Image Filter Parameters:**
```swift
filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
```

### Performance Considerations

- **Metal Acceleration**: Singleton CIContext with Metal device for GPU-accelerated image processing
- **Async Processing**: Frame capture and transformation on background queue
- **Single Plane Lock**: Only process frames for locked plane, ignore other detected planes
- **High-Quality Downsampling**: Core Image kCIContextHighQualityDownsampling for better output
- **Minimal Copies**: Direct CVPixelBuffer → CIImage pipeline without intermediate UIImage conversion

### Device Requirements

Requires a physical iOS device with ARKit support. The iOS Simulator does not support ARKit AR features including camera capture and plane detection.

### Current Limitations

1. **Fixed Capture Region**: Always uses 20cm × 20cm, not full plane extent
2. **Single Plane**: Only transforms first detected plane (subsequent planes ignored)
3. **Snapshot Mode**: One-time capture only (no live/continuous transformation)
4. **Portrait Orientation**: Camera orientation hardcoded to `.right` rotation
5. **No Export**: Transformed images not saved to file system
6. **Corner Overlay Disabled**: CornerMarkersOverlay structure present but renders empty canvas

### Future Development (PLAN.md Steps 10-15)

**Planned Features:**
- Live transformation mode with continuous updates (Step 10)
- Orientation lock and rotation controls (Step 11)
- Zoom, pan, and interaction controls (Step 12)
- Image quality enhancements (sharpening, exposure) (Step 13)
- Annotation tools and measurements (Step 14)
- Export to Photos or Files app (Step 15)

### Logging and Debugging

The project uses **Apple's Unified Logging** (`os.Logger`) for structured, filterable logging.

**Subsystem:** `Peterror.CarcassoneAR`

**Categories:**
- `ARViewContainer.Coordinator` - AR session, frame capture, visualization
- `ARViewContainer.PlaneDetectionDelegate` - Plane detection events
- `PerspectiveTransformCalculator` - 3D→2D projections, quality validation
- `ImageTransformProcessor` - Core Image perspective correction
- `ContentView` - Main view interactions
- `View2D` - 2D view interactions

**Log Levels:** `.debug` (diagnostics), `.info` (events), `.notice` (user actions), `.error` (failures)

**Filtering in Console.app:**

View all app logs:
```
subsystem:Peterror.CarcassoneAR
```

View errors only:
```
subsystem:Peterror.CarcassoneAR level:error
```

View specific class:
```
category:ARViewContainer.Coordinator
```

Debug transformation pipeline:
```
category:PerspectiveTransformCalculator OR category:ImageTransformProcessor
```

**Common Issues:**
- **"Raycast did not hit plane"**: Camera not pointing at detected plane
- **"Failed to create transformation"**: Corners not visible or camera angle too shallow (<20°)
- **"Failed to create CGImage"**: CVPixelBuffer format issue or Metal unavailable
