# Technical Design Document: Top-Down Perspective Transformation

## Overview

This document describes the technical implementation of perspective transformation to convert oblique AR camera views of horizontal surfaces into orthogonal top-down views, creating the effect of a virtual overhead camera.

---

## 1. Problem Statement

### Current State
- ARKit detects horizontal planes and provides their position, orientation, and dimensions
- Camera captures oblique (angled) views of the surface
- Raw camera image shows perspective distortion (parallel lines converge, far objects appear smaller)

### Desired State
- Transform camera image to show surface as if viewed from directly above
- Preserve real-world proportions and measurements
- Maintain image quality despite geometric transformation
- Support both static snapshots and live transformation

---

## 2. Mathematical Foundation

### 2.1 Coordinate Systems

**World Coordinate System (ARKit)**
- Origin: AR session initialization point
- X-axis: Right (device perspective)
- Y-axis: Up (gravity direction)
- Z-axis: Backward (right-hand rule)
- Units: Meters

**Camera Coordinate System**
- Origin: Camera optical center
- X-axis: Right in camera view
- Y-axis: Up in camera view
- Z-axis: Into the scene (viewing direction)
- Units: Meters

**Image Coordinate System (UIKit/CoreImage)**
- Origin: Top-left corner
- X-axis: Right
- Y-axis: Down
- Units: Pixels

**Plane Local Coordinate System**
- Origin: Plane center (anchor position)
- X-axis: Plane width direction
- Z-axis: Plane depth direction
- Y-axis: Normal to plane (perpendicular up)
- Units: Meters

### 2.2 Transformation Pipeline

```
3D World Coordinates → Camera Projection → 2D Image Coordinates → Homography → Top-Down View
```

**Step 1: Define Plane Corners in World Space**
Given plane data (center position, width, height, transform):
```
corner_TL = center + transform * (-width/2, 0, -height/2)
corner_TR = center + transform * (+width/2, 0, -height/2)
corner_BR = center + transform * (+width/2, 0, +height/2)
corner_BL = center + transform * (-width/2, 0, +height/2)
```

**Step 2: Project to Camera Image**
Use ARCamera.projectPoint() to convert 3D world positions to 2D pixel coordinates:
```
pixel_TL = camera.projectPoint(corner_TL)
pixel_TR = camera.projectPoint(corner_TR)
pixel_BR = camera.projectPoint(corner_BR)
pixel_BL = camera.projectPoint(corner_BL)
```

**Step 3: Define Output Rectangle**
Top-down view should show plane as axis-aligned rectangle:
```
output_TL = (0, 0)
output_TR = (outputWidth, 0)
output_BR = (outputWidth, outputHeight)
output_BL = (0, outputHeight)
```

Output dimensions maintain aspect ratio:
```
aspectRatio = planeWidth / planeHeight
outputWidth = desiredWidth
outputHeight = outputWidth / aspectRatio
```

**Step 4: Compute Perspective Transform**
Homography matrix H maps source quadrilateral to destination rectangle.
Using Core Image's CIPerspectiveCorrection filter with corner points.

---

## 3. Implementation Architecture

### 3.1 Data Structures

```swift
// Enhanced plane data with transformation info
struct PlaneData {
    var width: Float
    var height: Float
    var position: SIMD3<Float>      // Center position in world space
    var transform: simd_float4x4     // Plane's orientation transform

    // Computed properties
    var corners3D: [SIMD3<Float>]    // Four corners in world space
    var rotation: Float               // Plane rotation around Y-axis for orientation lock
}

// Transformation data
struct PerspectiveTransform {
    var sourceCorners: [CGPoint]      // Pixel coordinates of plane corners
    var destinationSize: CGSize       // Output image dimensions
    var transformMatrix: CGAffineTransform?  // Optional cached transform
    var timestamp: TimeInterval       // When transform was calculated
}

// Camera capture with metadata
struct CapturedFrame {
    var image: UIImage                // Raw camera image
    var transform: PerspectiveTransform  // Associated transformation
    var planeData: PlaneData          // Plane state at capture time
    var cameraTransform: simd_float4x4   // Camera pose at capture time
}
```

### 3.2 Core Components

**PerspectiveTransformCalculator**
```swift
class PerspectiveTransformCalculator {
    // Calculate 3D corners from plane data
    static func calculatePlaneCorners(planeData: PlaneData) -> [SIMD3<Float>]

    // Project 3D corners to 2D image coordinates
    static func projectCornersToImage(
        corners3D: [SIMD3<Float>],
        camera: ARCamera,
        imageResolution: CGSize
    ) -> [CGPoint]

    // Compute output dimensions maintaining aspect ratio
    static func calculateOutputSize(
        planeData: PlaneData,
        maxWidth: CGFloat
    ) -> CGSize

    // Create full transformation data
    static func createTransform(
        planeData: PlaneData,
        camera: ARCamera,
        imageResolution: CGSize,
        outputMaxWidth: CGFloat
    ) -> PerspectiveTransform
}
```

**ImageTransformProcessor**
```swift
class ImageTransformProcessor {
    // Apply perspective correction to image
    static func applyPerspectiveCorrection(
        image: UIImage,
        transform: PerspectiveTransform
    ) -> UIImage?

    // Enhanced version with quality settings
    static func applyPerspectiveCorrectionEnhanced(
        image: UIImage,
        transform: PerspectiveTransform,
        interpolationQuality: CGInterpolationQuality,
        applySharpening: Bool
    ) -> UIImage?
}
```

**ARFrameCapture (Enhanced Coordinator)**
```swift
class ARFrameCapture {
    var arView: ARView?

    // Capture current frame with full metadata
    func captureFrameWithTransform(
        planeData: PlaneData
    ) -> CapturedFrame?

    // For live mode: continuous capture
    func startLiveCapture(
        interval: TimeInterval,
        callback: @escaping (CapturedFrame) -> Void
    )

    func stopLiveCapture()
}
```

### 3.3 Integration Points

**ARViewContainer Updates**
```swift
struct ARViewContainer: UIViewRepresentable {
    @Binding var planeData: PlaneData?
    @Binding var capturedFrame: CapturedFrame?
    @Binding var captureNow: Bool

    class Coordinator {
        func captureCameraFrameWithTransform() {
            // Get current frame
            guard let frame = arView?.session.currentFrame,
                  let planeData = parent.planeData else { return }

            // Calculate transformation
            let transform = PerspectiveTransformCalculator.createTransform(
                planeData: planeData,
                camera: frame.camera,
                imageResolution: CGSize(width: 1920, height: 1440), // ARKit image size
                outputMaxWidth: 1024
            )

            // Create captured frame
            let capturedFrame = CapturedFrame(
                image: extractUIImage(from: frame),
                transform: transform,
                planeData: planeData,
                cameraTransform: frame.camera.transform
            )

            // Update binding
            parent.capturedFrame = capturedFrame
        }
    }
}
```

**View2D Updates**
```swift
struct View2D: View {
    var capturedFrame: CapturedFrame?
    @State private var transformedImage: UIImage?
    @State private var isProcessing: Bool = false

    var body: some View {
        // Show loading indicator while processing
        if isProcessing {
            ProgressView("Transforming...")
        }

        // Display transformed image
        if let transformed = transformedImage {
            Image(uiImage: transformed)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    // Process transformation when frame is available
    func processTransformation() {
        guard let frame = capturedFrame else { return }

        isProcessing = true

        DispatchQueue.global(qos: .userInitiated).async {
            let result = ImageTransformProcessor.applyPerspectiveCorrection(
                image: frame.image,
                transform: frame.transform
            )

            DispatchQueue.main.async {
                transformedImage = result
                isProcessing = false
            }
        }
    }
}
```

---

## 4. Core Image Implementation

### 4.1 CIPerspectiveCorrection Filter

```swift
func applyPerspectiveCorrection(
    image: UIImage,
    transform: PerspectiveTransform
) -> UIImage? {
    guard let ciImage = CIImage(image: image) else { return nil }

    // Create filter
    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
        return nil
    }

    filter.setValue(ciImage, forKey: kCIInputImageKey)

    // Set corner points (Core Image uses bottom-left origin)
    let imageHeight = ciImage.extent.height
    let corners = transform.sourceCorners

    // Convert UIKit coordinates (top-left origin) to Core Image (bottom-left origin)
    filter.setValue(
        CIVector(x: corners[3].x, y: imageHeight - corners[3].y), // Bottom-left
        forKey: "inputBottomLeft"
    )
    filter.setValue(
        CIVector(x: corners[2].x, y: imageHeight - corners[2].y), // Bottom-right
        forKey: "inputBottomRight"
    )
    filter.setValue(
        CIVector(x: corners[0].x, y: imageHeight - corners[0].y), // Top-left
        forKey: "inputTopLeft"
    )
    filter.setValue(
        CIVector(x: corners[1].x, y: imageHeight - corners[1].y), // Top-right
        forKey: "inputTopRight"
    )

    // Get output
    guard let outputImage = filter.outputImage else { return nil }

    // Render to UIImage
    let context = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true
    ])

    guard let cgImage = context.createCGImage(
        outputImage,
        from: outputImage.extent
    ) else { return nil }

    return UIImage(cgImage: cgImage)
}
```

### 4.2 Corner Ordering Convention

```
Source (Camera Image):          Destination (Top-Down):
     0 -------- 1                    0 -------- 1
    /            \                   |          |
   /              \                  |          |
  3 -------------- 2                 3 -------- 2

0 = Top-Left
1 = Top-Right
2 = Bottom-Right
3 = Bottom-Left
```

---

## 5. Performance Considerations

### 5.1 Optimization Strategies

**Computation Caching**
- Cache transformation matrix until plane updates
- Only recalculate when plane anchor changes significantly
- Use timestamp comparison to detect stale data

**Image Resolution Management**
```swift
// Use lower resolution for live mode
let resolution: CGSize = liveMode ?
    CGSize(width: 960, height: 720) :   // Live: 720p
    CGSize(width: 1920, height: 1440)   // Snapshot: 1080p
```

**Async Processing**
```swift
// Never block main thread
DispatchQueue.global(qos: .userInitiated).async {
    let transformed = processImage(...)
    DispatchQueue.main.async {
        updateUI(transformed)
    }
}
```

**Metal Acceleration**
- Core Image automatically uses GPU via Metal
- Ensure CIContext is created with Metal device
- Reuse CIContext instances (expensive to create)

### 5.2 Memory Management

```swift
// Singleton context for image processing
class ImageProcessor {
    static let shared = ImageProcessor()
    private let context: CIContext

    private init() {
        // Create Metal-backed context once
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false, // Reduce memory footprint
                .priorityRequestLow: false
            ])
        } else {
            context = CIContext(options: [:])
        }
    }
}
```

---

## 6. Edge Cases and Error Handling

### 6.1 Problematic Scenarios

**Extreme Viewing Angles**
- When camera is nearly parallel to plane, projection becomes unstable
- Corners may project outside image bounds
- Solution: Detect angle between camera and plane normal, warn user if < 20°

```swift
func isCameraAngleSafe(planeNormal: SIMD3<Float>, cameraDirection: SIMD3<Float>) -> Bool {
    let angle = acos(dot(planeNormal, cameraDirection))
    return angle > .pi / 9  // > 20 degrees
}
```

**Partial Plane Visibility**
- Some corners may be outside camera frustum
- Solution: Check if projectPoint() returns valid coordinates within image bounds

```swift
func areAllCornersVisible(corners: [CGPoint], imageSize: CGSize) -> Bool {
    return corners.allSatisfy { corner in
        corner.x >= 0 && corner.x <= imageSize.width &&
        corner.y >= 0 && corner.y <= imageSize.height
    }
}
```

**Moving Camera/Plane**
- Motion blur during capture
- Plane detection updates during transformation
- Solution: Freeze plane data at capture time, use high shutter speed if possible

### 6.2 Quality Validation

```swift
struct TransformQuality {
    var cameraAngle: Float       // Degrees from perpendicular
    var allCornersVisible: Bool
    var estimatedResolution: Float  // Pixels per meter

    var isGoodQuality: Bool {
        return cameraAngle < 70 &&   // Not too oblique
               allCornersVisible &&
               estimatedResolution > 100  // Sufficient detail
    }
}
```

---

## 7. Testing Strategy

### 7.1 Unit Tests

- Test corner calculation with known plane parameters
- Verify coordinate system conversions
- Test transformation matrix computation

### 7.2 Integration Tests

- Test with synthetic AR frames
- Verify end-to-end transformation pipeline
- Test performance benchmarks

### 7.3 Device Testing Checklist

- [ ] Various table sizes (0.4m to 2m)
- [ ] Different camera angles (30°, 45°, 60°, 75°)
- [ ] Different camera distances (0.5m, 1m, 2m)
- [ ] Various lighting conditions
- [ ] Different surface textures and patterns
- [ ] Moving objects on surface
- [ ] Rectangular vs. square tables
- [ ] Performance on different devices (iPhone 12+, iPad)

### 7.4 Visual Validation

Place reference objects with known dimensions:
- Ruler or measuring tape
- Square grid paper
- Chess board (8x8 squares)
- Rectangular book or card

Verify transformed image shows:
- Correct proportions
- Right angles preserved
- Parallel lines remain parallel
- Accurate measurements

---

## 8. Future Enhancements

### 8.1 Advanced Features

**Multi-Plane Support**
- Detect and transform multiple surfaces simultaneously
- Composite multiple planes into single view

**Temporal Stability**
- Use multiple frames to reduce noise
- Average transformations over time
- Optical flow for smooth transitions

**Enhanced Geometry**
- Use ARPlaneAnchor.geometry for precise boundaries
- Handle non-rectangular plane shapes
- Detect and mask objects above plane

**Image Enhancement**
- Auto white balance and exposure
- Shadow removal
- HDR compositing from multiple exposures

### 8.2 AR Integration

**Annotations Overlay**
- Draw directly on transformed view
- Project annotations back to AR view
- Persistent coordinate system

**Measurement Tools**
- Distance measurement
- Area calculation
- Angle measurement

---

## 9. References

### Apple Documentation
- [ARKit Framework](https://developer.apple.com/documentation/arkit)
- [ARCamera](https://developer.apple.com/documentation/arkit/arcamera)
- [ARPlaneAnchor](https://developer.apple.com/documentation/arkit/arplaneanchor)
- [Core Image Filter Reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/)
- [CIPerspectiveCorrection](https://developer.apple.com/documentation/coreimage/ciperspectivecorrection)

### Mathematical Background
- Homography and perspective transformation
- Camera projection models
- Coordinate system transformations

---

## 10. Implementation Roadmap

### Phase 1: Foundation (Step 9)
- Implement PerspectiveTransformCalculator
- Calculate plane corners in 3D
- Project to 2D camera coordinates
- Validate coordinate transformations

### Phase 2: Basic Transformation (Step 10)
- Implement ImageTransformProcessor
- Apply CIPerspectiveCorrection
- Display transformed snapshot in View2D
- Handle edge cases and errors

### Phase 3: Live Mode (Step 11)
- Implement continuous capture
- Optimize for real-time performance
- Add mode switching UI

### Phase 4: Polish (Steps 12-15)
- Orientation lock
- Zoom/pan controls
- Quality enhancements
- Export functionality

---

## Appendix A: Coordinate System Diagrams

```
ARKit World Space (Right-handed, Y-up):
        Y (up)
        |
        |
        +------ X (right)
       /
      Z (backward toward user)

Camera Space (Right-handed, Z-forward):
        Y (up in image)
        |
        |
        +------ X (right in image)
       /
      Z (into scene, viewing direction)

UIKit Image Space (Top-left origin):
    (0,0) -------- X (right)
      |
      |
      Y (down)

Plane Local Space (on horizontal surface):
        Y (normal, up)
        |
        |
        +------ X (width)
       /
      Z (depth)
```

## Appendix B: Key Formulas

**Plane Corner in World Space:**
```
corner = planeCenter + planeTransform * localOffset
where localOffset ∈ {
    (-w/2, 0, -h/2),  // Top-left
    (+w/2, 0, -h/2),  // Top-right
    (+w/2, 0, +h/2),  // Bottom-right
    (-w/2, 0, +h/2)   // Bottom-left
}
```

**Camera Projection:**
```
pixelCoord = camera.projectPoint(worldPoint)
// Returns CGPoint in pixel coordinates relative to camera image resolution
```

**Aspect Ratio Preservation:**
```
outputAspectRatio = planeWidth / planeHeight
outputHeight = outputWidth / outputAspectRatio
```
