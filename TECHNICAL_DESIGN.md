# Technical Design Document: CarcassoneAR

## 1. Project Overview

### 1.1 Vision & Goals

CarcassoneAR is an iOS augmented reality application designed to enhance the Carcassonne board game experience. Using AR and computer vision, the app captures the physical game board, recognizes placed tiles, tracks game state, and provides intelligent assistance to players.

**Primary Goals:**
- Capture and digitize physical Carcassonne game boards using AR
- Automatically recognize and classify placed tiles
- Track remaining tiles and calculate placement probabilities
- Validate tile placements and suggest legal moves

**Design Principles:**
- On-device processing for privacy and offline capability
- Non-intrusive assistance that enhances rather than replaces gameplay
- Hybrid recognition with user confirmation for accuracy
- Progressive enhancement from basic capture to full game assistance

### 1.2 Target Features

| Feature | Description | Priority |
|---------|-------------|----------|
| **Remaining Tiles** | Display count and types of unplayed tiles | Core |
| **Placement Hints** | Show valid positions for a drawn tile | Core |
| **Probability Calculator** | % chance of finding tiles matching specific edge requirements | Core |
| **Game State Tracking** | Maintain digital representation of physical board | Core |
| **Scoring Assistance** | Calculate potential and current additional points per player | Future |
| **Pawn Detection** | Detect and localize player pawns (meeples) on tiles | Future |
| **Save/Resume** | Persist game state across sessions | Future |
| **Expansion Support** | Additional tile sets beyond base + river | Future |

### 1.3 User Experience Flow

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   AR Scanning   │───▶│  Board Capture  │───▶│ Tile Detection  │
│ (Detect Table)  │    │ (Perspective)   │    │ (YOLO)          │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                       ┌───────────────────────────────┘
                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Classification │───▶│  User Confirm   │───▶│  Game State     │
│  (MobileNetV2)  │    │  (Hybrid Mode)  │    │  Update         │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       │
                       ┌───────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HELPER FEATURES                              │
│  • Remaining tiles display    • Valid placement overlay         │
│  • Probability percentages    • (Future: Score calculation)     │
└─────────────────────────────────────────────────────────────────┘
```

**Typical Session:**
1. User starts game, places physical tiles on table
2. User opens app and scans the table surface (AR plane detection)
3. App captures top-down view of board (perspective transformation)
4. App detects tiles using YOLO and classifies each one (object detection + ML)
5. User confirms/corrects recognition results (hybrid validation)
6. App tracks game state and provides assistance (remaining tiles, suggestions)
7. User can re-scan after placing new tiles

---

## 2. System Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CarcassoneAR App                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐   │
│  │   AR Layer   │    │   CV Layer   │    │     Game Logic Layer     │   │
│  │              │    │              │    │                          │   │
│  │ • ARKit      │───▶│ • YOLO Det.  │───▶│ • Board State            │   │
│  │ • RealityKit │    │ • Tile Crop  │    │ • Tile Validation        │   │
│  │ • Plane Det. │    │ • Preprocess │    │ • Remaining Tiles        │   │
│  │ • Persp.Xfrm │    │              │    │ • Probability Calc       │   │
│  └──────────────┘    └──────────────┘    └──────────────────────────┘   │
│                             │                                           │
│                             ▼                                           │
│                    ┌──────────────┐                                     │
│                    │   ML Layer   │                                     │
│                    │              │                                     │
│                    │ • CoreML     │                                     │
│                    │ • YOLO       │                                     │
│                    │ • MobileNetV2│                                     │
│                    └──────────────┘                                     │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                          UI Layer (SwiftUI)                             │
│  • AR View  • 2D View  • Tile Grid  • Remaining List  • Overlays        │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Technology Stack

| Component               | Technology           | Purpose                               |
|-------------------------|----------------------|---------------------------------------|
| **AR Engine**           | ARKit + RealityKit   | Plane detection, world tracking       |
| **Image Processing**    | Core Image           | Perspective correction, preprocessing |
| **Tile Detection**      | YOLO (CoreML)        | Detect and localize tiles in image    |
| **Tile Classification** | MobileNetV2 (CoreML) | Classify tile types                   |
| **UI Framework**        | SwiftUI              | Declarative UI, AR overlays           |
| **Logging**             | os.Logger            | Structured debugging                  |
| **Target Platform**     | iOS 26.0+            | Latest ARKit/ML capabilities          |

### 2.3 Data Flow Overview

```
Physical Board
      │
      ▼ (Camera)
┌─────────────────┐
│   CVPixelBuffer │ 1920×1440 landscape
└────────┬────────┘
         │
         ▼ (Perspective Transform)
┌─────────────────┐
│   Top-Down View │ Corrected orthogonal image
└────────┬────────┘
         │
         ▼ (YOLO Detection)
┌─────────────────┐
│  Tile Bboxes    │ Position + rotation of each tile
└────────┬────────┘
         │
         ▼ (Tile Extraction)
┌─────────────────┐
│  64×64 Images   │ Normalized, rotation-corrected
└────────┬────────┘
         │
         ▼ (MobileNetV2)
┌─────────────────┐
│  Classifications│ TileType + confidence
└────────┬────────┘
         │
         ▼ (Game Logic)
┌─────────────────┐
│   BoardState    │ Complete game state
└─────────────────┘
```

---

## 3. AR Capture Pipeline (Implemented)

### 3.1 Plane Detection

The app uses ARKit's ARWorldTrackingConfiguration to detect horizontal surfaces suitable for board game play.

**Configuration:**
```swift
let configuration = ARWorldTrackingConfiguration()
configuration.planeDetection = [.horizontal]
configuration.environmentTexturing = .automatic
```

**Detection Criteria:**
- Minimum plane size: 0.4m × 0.4m (ARKit default for stable detection)
- Dynamic play area: Adapts to actual game size (base game ~1m×1m, expansions larger)
- Single plane lock: First detected plane is locked for consistent tracking

**Plane Locking Strategy:**
1. Start AR session with horizontal plane detection
2. Wait for first plane anchor that meets minimum size
3. Store `planeAnchor.identifier` as `lockedPlaneID`
4. Subsequent updates only process the locked plane
5. Reset button clears lock and restarts detection

### 3.2 Perspective Transformation

Converts oblique camera views to orthogonal top-down representation using homography transformation.

**Pipeline:**

```
3D World Corners → Camera Projection → 2D Pixel Coords → CIPerspectiveCorrection → Top-Down Image
```

**Implementation Classes:**
- `PerspectiveTransformCalculator`: 3D→2D projection, quality validation
- `ImageTransformProcessor`: Core Image CIPerspectiveCorrection filter application

**Key Methods:**
```swift
// Calculate plane corners in 3D world space
static func calculatePlaneCorners(planeData: PlaneData, rotationQuaternion: simd_quatf?) -> [SIMD3<Float>]

// Project 3D corners to 2D pixel coordinates
static func projectCornersToImage(corners3D: [SIMD3<Float>], camera: ARCamera, imageResolution: CGSize) -> [CGPoint]

// Apply perspective correction
static func applyPerspectiveCorrection(image: UIImage, perspectiveTransform: PerspectiveTransform) -> UIImage?
```

**Quality Thresholds:**
| Metric            | Good     | Acceptable | Poor    |
|-------------------|----------|------------|---------|
| Camera Angle      | >45°     | 20-45°     | <20°    |
| Resolution        | >640 ppm | 50-640 ppm | <50 ppm |
| Corner Visibility | All 4    | All 4      | <4      |

### 3.3 Image Export for Training Data

The app exports captured and transformed images to Photos Library for ML training data collection.

**Export Format:**
- File type: PNG (lossless)
- Filename: `carcassonne_YYYYMMDD_HHmmss_ppmQQQQ_angleAA.png`
- Quality metrics embedded in filename:
  - `ppmQQQQ`: Pixels per meter (0000-9999)
  - `angleAA`: Camera angle in degrees (00-90)

**Implementation:** `ImageExporter.swift`
- Uses PHPhotoLibrary with `.addOnly` authorization
- Async/await pattern for non-blocking export
- Error handling for denied/restricted access

### 3.4 Coordinate Systems Reference

**ARKit World Space:**
```
        Y (up, gravity opposite)
        │
        │
        +──────── X (right)
       /
      Z (toward user)

- Right-handed coordinate system
- Origin: AR session start position
- Units: Meters
```

**Camera Image Space (Landscape):**
```
    (0,0) ──────────── X (1920)
      │
      │
      Y (1440)

- Origin: Top-left
- Units: Pixels
- Native camera buffer orientation
```

**Portrait Display Space:**
```
    (0,0) ──────────── X (1440)
      │
      │
      Y (1920)

- Rotated 90° CW from landscape
- Used for UI display
```

**Core Image Space:**
```
      Y (height)
      │
      │
    (0,0) ──────────── X (width)

- Origin: Bottom-left
- Y-axis inverted from UIKit
- Conversion: ciY = imageHeight - uiKitY
```

**Tile Grid Space:**
```
         +Y (North)
           │
           │
   -X ─────┼───── +X
   (West)  │      (East)
           │
         -Y (South)

- Origin: First tile placed (typically center of board)
- Units: Tile positions (integer grid)
- Standard convention: +Y = North (top of board)
- Rotation: 0° = tile top edge facing North (+Y)
```

### 3.5 Quality Validation

**TransformQuality Structure:**
```swift
struct TransformQuality {
    var cameraAngleDegrees: Float    // 0-90°, higher is better
    var allCornersVisible: Bool      // All 4 corners in frame
    var estimatedPixelsPerMeter: Float // Higher = more detail

    var isGoodQuality: Bool {
        cameraAngleDegrees > 20 && allCornersVisible && estimatedPixelsPerMeter > 640
    }
}
```

---

## 4. Tile Detection Pipeline (Planned)

### 4.1 YOLO-Based Detection

Use YOLO (You Only Look Once) object detection to reliably detect and localize tiles regardless of board rotation or orientation.

**Why YOLO over Edge Detection:**
- Robust to image rotation and perspective distortion
- Handles varying lighting conditions
- Detects tiles as objects with bounding boxes + orientation (if reliable)
- Single-pass detection is faster than multi-stage edge processing
- Better handles partial occlusions and tile gaps

**Detection Output:**
```swift
struct DetectedTile {
    let boundingBox: CGRect      // Tile location in image
    let rotation: Float          // Detected tile rotation (-180° - 180°)
    let confidence: Float        // Detection confidence
}
```

### 4.2 YOLO Model Architecture

**Model Choice: YOLOv8-nano or YOLOv5-nano**

Rationale:
- Optimized for mobile deployment
- Single-class detection (just "tile")
- Includes rotation estimation
- CoreML compatible

**Training Configuration:**
```
Input: Variable size (640×640 recommended)
Classes: 1 (Carcassonne tile)
Output: Bounding boxes + rotation angle + confidence
```

**Training Data Requirements:**
- 500+ annotated board images
- Various lighting conditions
- Different camera angles
- Rotated boards
- Partial boards (mid-game states)

### 4.3 Individual Tile Extraction

Extract each detected tile as a separate image for classification.

**Process:**
```swift
func extractTiles(from image: UIImage, detections: [DetectedTile]) -> [ExtractedTile] {
    return detections.map { detection in
        // Crop bounding box region
        let cropped = cropImage(image, to: detection.boundingBox)

        // Rotate to normalize orientation
        let normalized = rotateImage(cropped, by: -detection.rotation)

        // Resize to classifier input size
        let resized = resize(normalized, to: CGSize(width: 64, height: 64))

        return ExtractedTile(
            image: resized,
            position: calculateGridPosition(detection.boundingBox),
            rotation: detection.rotation
        )
    }
}
```

### 4.4 Preprocessing for Classification

Normalize extracted tiles for consistent ML input.

**Steps:**
1. Crop using YOLO bounding box
2. Apply rotation correction (align to 0°)
3. Resize to 64×64 (or 128×128)
4. Apply contrast normalization
5. Convert to ML-compatible tensor format

---

## 5. Tile Classification System (Planned)

### 5.1 Edge-Based Classification Approach

Instead of classifying 84 different tile types, the model classifies **tile edges and features**. This approach offers significant advantages:

**Why Edge-Based Classification:**
- **Simplified problem**: 4 edge types instead of 84 tile classes
- **Training data multiplication**: Each tile provides 4 edge samples (4× more training data)
- **Better generalization**: Fewer classes = more robust with limited data
- **Expansion-friendly**: New tile sets only need edge recognition, not new classes

**Classification Output:**
```swift
struct TileClassification {
    // Edge types for each direction
    let northEdge: EdgeType       // field, road, city, river
    let eastEdge: EdgeType
    let southEdge: EdgeType
    let westEdge: EdgeType

    // Tile features
    let hasShield: Bool           // Contains shield emblem
    let hasMonastery: Bool        // Contains monastery in center
    let hasSeparatedCities: Bool  // Multiple city edges are NOT connected internally

    // Confidence scores
    let edgeConfidences: [Direction: Float]
    let featureConfidences: (shield: Float, monastery: Float, separated: Float)
}
```

**Separated Cities Explanation:**

Some tiles have multiple city edges. These can be either:
- **Connected**: City edges form a single contiguous city (scored together)
- **Separated**: City edges are independent cities (scored separately)

```
Connected (single city):          Separated (two cities):
┌─────────────────┐              ┌─────────────────┐
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│              │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  │
│    ▓▓▓▓▓▓▓▓▓▓▓▓▓│              │    ▓▓▓▓▓▓▓     ▓│
│            ▓▓▓▓▓│              │              ▓▓▓│
│             ▓▓▓▓│              │              ▓▓▓│
│              ▓▓▓│              │              ▓▓▓│
│                ▓│              │                ▓│
└─────────────────┘              └─────────────────┘
  N+E cities wrap                  N and E cities
  around corner                    are separate
```
```
Connected (single city):          Separated (two cities):
┌─────────────────┐              ┌─────────────────┐
│▓▓             ▓▓│              │▓               ▓│
│▓▓▓▓▓       ▓▓▓▓▓│              │▓▓▓           ▓▓▓│
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│              │▓▓▓           ▓▓▓│
│▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│              │▓▓▓           ▓▓▓│
│▓▓▓▓▓       ▓▓▓▓▓│              │▓▓▓           ▓▓▓│
│▓▓             ▓▓│              │▓               ▓│
└─────────────────┘              └─────────────────┘
  W+E cities create                W and E cities
  a corridor                       are separate
```

### 5.2 Model Architecture

**Primary Choice: MobileNetV2 with Multi-Head Output**

```
Input: 64×64×3 RGB image (normalized tile)

Base: MobileNetV2 (pretrained on ImageNet, frozen initially)
  │
  └─▶ GlobalAveragePooling2D
        │
        └─▶ Dense(256, relu) + Dropout(0.3)
              │
              ├─▶ Dense(4, softmax) → North Edge  [field, road, city, river]
              ├─▶ Dense(4, softmax) → East Edge
              ├─▶ Dense(4, softmax) → South Edge
              ├─▶ Dense(4, softmax) → West Edge
              ├─▶ Dense(1, sigmoid) → Has Shield
              ├─▶ Dense(1, sigmoid) → Has Monastery
              └─▶ Dense(1, sigmoid) → Has Separated Cities

Total outputs: 4×4 + 3 = 19 values
```

**Alternative Approach: Single Edge Classifier**

Train a model that classifies a single edge, then run it 4 times (once per edge):
- Input: Cropped edge region (e.g., top 1/4 of tile for North edge)
- Output: 4-class softmax (field, road, city, river)
- Advantage: Even simpler model, more training data per class
- Disadvantages: Loses context from tile center (monastery, shield, city connectivity); Has to be run multiple times on a single tile increasing inference time. 

### 5.3 Training Strategy

**Dataset Requirements:**
- Target: 300+ tile images (not per-class!)
- Each tile image yields 4 edge training samples = 1,200+ edge samples
- Collection: Use app's export feature to capture real tiles

**Training Data Format:**
```python
# Each tile image is labeled with:
{
    "image": "tile_001.png",
    "edges": {
        "north": "city",
        "east": "city",
        "south": "field",
        "west": "field"
    },
    "has_shield": true,
    "has_monastery": false,
    "has_separated_cities": false  # N and E cities are connected
}
```

**Data Augmentation:**
| Augmentation     | Range                 | Purpose              |
|------------------|-----------------------|----------------------|
| 90° Rotations    | 0°, 90°, 180°, 270°   | Rotate tile + labels |
| Brightness       | ±20%                  | Lighting variation   |
| Contrast         | ±15%                  | Different conditions |
| Gaussian Noise   | σ=0.02                | Sensor noise         |
| Slight Rotation  | ±5°                   | Imperfect alignment  |
| Scale            | 95-105%               | Size variation       |

**Label Rotation for Augmentation:**
```python
def rotate_labels(labels, degrees):
    """Rotate edge labels when image is rotated."""
    edges = labels['edges']
    order = ['north', 'east', 'south', 'west']
    shift = degrees // 90
    rotated_order = order[-shift:] + order[:-shift]
    rotated_edges = {rotated_order[i]: edges[order[i]] for i in range(4)}

    return {
        'edges': rotated_edges,
        'has_shield': labels['has_shield'],
        'has_monastery': labels['has_monastery'],
        'has_separated_cities': labels['has_separated_cities']  # Unchanged by rotation
    }
```

**Training Parameters:**
```python
# Multi-task loss: weighted sum of edge losses + feature losses
losses = {
    'north_edge': 'categorical_crossentropy',
    'east_edge': 'categorical_crossentropy',
    'south_edge': 'categorical_crossentropy',
    'west_edge': 'categorical_crossentropy',
    'has_shield': 'binary_crossentropy',
    'has_monastery': 'binary_crossentropy',
    'has_separated_cities': 'binary_crossentropy'
}

loss_weights = {
    'north_edge': 1.0, 'east_edge': 1.0,
    'south_edge': 1.0, 'west_edge': 1.0,
    'has_shield': 0.5, 'has_monastery': 0.5,
    'has_separated_cities': 0.5
}

optimizer = Adam(learning_rate=0.0001)
epochs = 50
batch_size = 32
```

### 5.4 Tile Reconstruction from Edges

After classification, reconstruct the tile type by matching detected edges and features to known tile definitions.

**Matching Algorithm:**
```swift
func reconstructTileType(classification: TileClassification) -> (TileType, Int)? {
    let detectedEdges = TileEdges(
        north: classification.northEdge,
        east: classification.eastEdge,
        south: classification.southEdge,
        west: classification.westEdge
    )

    // Try all tile types and rotations
    for tileType in TileType.allCases {
        // Skip if features don't match
        if tileType.hasShield != classification.hasShield { continue }
        if tileType.hasMonastery != classification.hasMonastery { continue }
        if tileType.hasSeparatedCities != classification.hasSeparatedCities { continue }

        // Check all rotations
        for rotation in [0, 90, 180, 270] {
            let canonicalEdges = tileType.edges.rotated(by: rotation)
            if canonicalEdges == detectedEdges {
                return (tileType, rotation)
            }
        }
    }

    return nil  // No matching tile found (possible misclassification)
}
```

**Handling Ambiguity:**

Some edge combinations may match multiple tile types. Resolution strategies:
1. Use shield/monastery/separated flags to disambiguate
2. Return all possible matches with confidence scores
3. Consider game context (remaining tiles in inventory)

### 5.5 CoreML Integration

**Model Conversion:**
```python
import coremltools as ct

mlmodel = ct.convert(
    keras_model,
    inputs=[ct.ImageType(shape=(1, 64, 64, 3), scale=1/255.0, name="tile_image")],
    outputs=[
        ct.TensorType(name="north_edge"),
        ct.TensorType(name="east_edge"),
        ct.TensorType(name="south_edge"),
        ct.TensorType(name="west_edge"),
        ct.TensorType(name="has_shield"),
        ct.TensorType(name="has_monastery"),
        ct.TensorType(name="has_separated_cities")
    ]
)
mlmodel.save("CarcassonneTileClassifier.mlmodel")
```

**Swift Integration:**
```swift
class TileClassifier {
    private let model: CarcassonneTileClassifier

    func classify(tile: UIImage) -> TileClassification? {
        guard let pixelBuffer = tile.toPixelBuffer(width: 64, height: 64) else { return nil }
        guard let prediction = try? model.prediction(tile_image: pixelBuffer) else { return nil }

        let edgeTypes: [EdgeType] = [.field, .road, .city, .river]

        func parseEdge(_ output: MLMultiArray) -> (EdgeType, Float) {
            let probs = (0..<4).map { Float(truncating: output[$0]) }
            let maxIdx = probs.indices.max(by: { probs[$0] < probs[$1] })!
            return (edgeTypes[maxIdx], probs[maxIdx])
        }

        let (northEdge, northConf) = parseEdge(prediction.north_edge)
        let (eastEdge, eastConf) = parseEdge(prediction.east_edge)
        let (southEdge, southConf) = parseEdge(prediction.south_edge)
        let (westEdge, westConf) = parseEdge(prediction.west_edge)

        let shieldProb = Float(truncating: prediction.has_shield[0])
        let monasteryProb = Float(truncating: prediction.has_monastery[0])
        let separatedProb = Float(truncating: prediction.has_separated_cities[0])

        return TileClassification(
            northEdge: northEdge,
            eastEdge: eastEdge,
            southEdge: southEdge,
            westEdge: westEdge,
            hasShield: shieldProb > 0.5,
            hasMonastery: monasteryProb > 0.5,
            hasSeparatedCities: separatedProb > 0.5,
            edgeConfidences: [.north: northConf, .east: eastConf, .south: southConf, .west: westConf],
            featureConfidences: (shield: shieldProb, monastery: monasteryProb, separated: separatedProb)
        )
    }
}
```

### 5.6 Future: Pawn Detection

Player pawns (meeples) placed on tiles affect scoring ownership. Pawn detection is planned as a future feature.

**Approach Options:**
1. **YOLO multi-class**: Extend tile detector to also detect pawns by color
2. **Separate pawn detector**: Dedicated small model for pawn detection
3. **Color segmentation**: Simple CV approach using HSV color thresholds

**Pawn Detection Output:**
```swift
struct DetectedPawn {
    let color: PlayerColor           // red, blue, yellow, green, black
    let position: CGPoint            // Position within tile image
    let placementType: PawnPlacement // road, city, monastery, field
    let confidence: Float
}

enum PlayerColor: String, CaseIterable {
    case red, blue, yellow, green, black
}

enum PawnPlacement {
    case road, city, monastery, field
}
```

**Challenges:**
- Small object detection (pawns are ~5% of tile area)
- Color variation under different lighting
- Pawn orientation and shadows
- Distinguishing placement type (which feature the pawn claims)

---

## 6. Game State Engine (Planned)

### 6.1 Board Representation

**Grid-Based Board Model:**
```swift
struct BoardState: Codable {
    private(set) var tiles: [GridPosition: PlacedTile]
    private(set) var bounds: GridBounds

    mutating func place(tile: PlacedTile) {
        tiles[tile.position] = tile
        bounds.expand(to: tile.position)
    }

    func tile(at position: GridPosition) -> PlacedTile? {
        return tiles[position]
    }

    func adjacentPositions(to position: GridPosition) -> [GridPosition] {
        Direction.allCases.map { position.adjacent($0) }
    }

    func emptyAdjacentPositions() -> [GridPosition] {
        // All empty positions adjacent to at least one placed tile
    }

    func validPlacements(for tileType: TileType) -> [ValidPlacement] {
        // Return all valid positions and rotations
    }
}

struct GridPosition: Hashable, Codable {
    let row: Int  // +Y = North
    let col: Int  // +X = East

    func adjacent(_ direction: Direction) -> GridPosition {
        switch direction {
        case .north: return GridPosition(row: row + 1, col: col)
        case .south: return GridPosition(row: row - 1, col: col)
        case .east:  return GridPosition(row: row, col: col + 1)
        case .west:  return GridPosition(row: row, col: col - 1)
        }
    }
}

struct PlacedTile: Codable {
    let type: TileType
    let rotation: Int  // 0, 90, 180, 270
    let position: GridPosition

    var edges: TileEdges {
        type.edges.rotated(by: rotation)
    }
}

struct GridBounds: Codable {
    var minRow: Int
    var maxRow: Int
    var minCol: Int
    var maxCol: Int

    var width: Int { maxCol - minCol + 1 }
    var height: Int { maxRow - minRow + 1 }

    mutating func expand(to position: GridPosition) {
        minRow = min(minRow, position.row)
        maxRow = max(maxRow, position.row)
        minCol = min(minCol, position.col)
        maxCol = max(maxCol, position.col)
    }
}
```

### 6.2 Edge Matching Rules

**Edge Types:**
```swift
enum EdgeType: String, CaseIterable, Codable {
    case field = "F"    // Green grass texture, connects to other fields
    case road = "R"     // White/beige path, must connect to road edges
    case city = "C"     // Brown/orange walls, must connect to city edges
    case river = "W"    // Blue water, only matches river edges, placed before regular tiles
}

struct TileEdges: Codable, Equatable {
    let north: EdgeType
    let east: EdgeType
    let south: EdgeType
    let west: EdgeType

    func rotated(by degrees: Int) -> TileEdges {
        switch degrees % 360 {
        case 90:  return TileEdges(north: west, east: north, south: east, west: south)
        case 180: return TileEdges(north: south, east: west, south: north, west: east)
        case 270: return TileEdges(north: east, east: south, south: west, west: north)
        default:  return self
        }
    }

    func edge(facing direction: Direction) -> EdgeType {
        switch direction {
        case .north: return north
        case .east:  return east
        case .south: return south
        case .west:  return west
        }
    }
}
```

**Matching Rules:**
```swift
func canPlace(tile: TileType, rotation: Int, at position: GridPosition, board: BoardState) -> Bool {
    let edges = tile.edges.rotated(by: rotation)

    // Check all adjacent tiles
    for direction in Direction.allCases {
        if let neighbor = board.tile(at: position.adjacent(direction)) {
            let neighborEdge = neighbor.edges.edge(facing: direction.opposite)
            let tileEdge = edges.edge(facing: direction)

            if !edgesMatch(tileEdge, neighborEdge) {
                return false
            }
        }
    }

    // At least one neighbor required (except first tile)
    return board.tiles.isEmpty || hasAdjacentTile(position, board)
}

func edgesMatch(_ a: EdgeType, _ b: EdgeType) -> Bool {
    return a == b  // Same type matches; river only matches river
}
```

### 6.3 Remaining Tiles Calculation

**Tile Inventory:**
```swift
struct TileInventory: Codable {
    private var counts: [TileType: Int]

    init(edition: GameEdition) {
        counts = edition.initialTileCounts
    }

    mutating func remove(_ type: TileType) {
        counts[type, default: 0] -= 1
    }

    func remaining(_ type: TileType) -> Int {
        return counts[type, default: 0]
    }

    var totalRemaining: Int {
        return counts.values.reduce(0, +)
    }

    var remainingByCategory: [TileCategory: Int] {
        // Group counts by category
    }
}
```

### 6.4 Placement Validation

**Valid Placement Finder:**
```swift
func findValidPlacements(for tile: TileType, on board: BoardState) -> [ValidPlacement] {
    var placements: [ValidPlacement] = []

    for position in board.emptyAdjacentPositions() {
        for rotation in [0, 90, 180, 270] {
            if canPlace(tile: tile, rotation: rotation, at: position, board: board) {
                placements.append(ValidPlacement(
                    position: position,
                    rotation: rotation,
                    tile: tile
                ))
            }
        }
    }

    return placements
}

struct ValidPlacement: Hashable {
    let position: GridPosition
    let rotation: Int
    let tileType: TileType
}
```

### 6.5 Probability Calculation

**Calculate probability of drawing a tile that fits a specific position:**

```swift
func probabilityOfFit(at position: GridPosition, board: BoardState, inventory: TileInventory) -> PlacementAnalysis {
    var matchingTileCount = 0
    var matchingTypes: [TileType] = []
    var totalRemaining = 0

    for tileType in TileType.allCases {
        let count = inventory.remaining(tileType)
        if count > 0 {
            totalRemaining += count

            for rotation in [0, 90, 180, 270] {
                if canPlace(tile: tileType, rotation: rotation, at: position, board: board) {
                    matchingTileCount += count
                    matchingTypes.append(tileType)
                    break // Count tile type only once even if multiple rotations work
                }
            }
        }
    }

    let probability = totalRemaining > 0 ? Float(matchingTileCount) / Float(totalRemaining) : 0

    return PlacementAnalysis(
        position: position,
        probability: probability,
        validTileCount: matchingTileCount,
        matchingTiles: matchingTypes
    )
}

struct PlacementAnalysis {
    let position: GridPosition
    let probability: Float  // 0.0 - 1.0
    let validTileCount: Int
    let matchingTiles: [TileType]
}
```

**Display Format:**
- Show valid tiles remaining number on each empty position
- Color code: Green (>10%), Yellow (3-10%), Red (<3%)
- Show "No valid tiles" for positions with 0% probability

---

## 7. Scoring System (Future)

### 7.1 Overview

The scoring system calculates **additional points** players could gain, not cumulative game scores. This helps players understand the value of completing features.

**Two Score Types:**

| Type                | Description                                       | Use Case                                                     |
|---------------------|---------------------------------------------------|--------------------------------------------------------------|
| **Potential Score** | Points gained if feature is completed             | "If you finish this city, you get +12 points"                |
| **Current Score**   | Points gained if game ends now (incomplete value) | "If game ends now, this incomplete road gives you +2 points" |

### 7.2 Feature Detection

**Feature Types:**
```swift
enum Feature {
    case road(tiles: [GridPosition], isComplete: Bool)
    case city(tiles: [GridPosition], shields: Int, isComplete: Bool)
    case monastery(center: GridPosition, surroundingCount: Int)
}
```

**Feature Tracing:**
Traces connected edges to identify complete features. See Section 6.2 for edge definitions.

### 7.3 Point Calculation

**Potential Score (if completed):**
| Feature             | Points                     |
|---------------------|----------------------------|
| Road                | 1 per tile in road         |
| City (no shields)   | 2 per tile                 |
| City (with shields) | 2 per tile + 2 per shield  |
| Monastery           | 9 (center + 8 surrounding) |

**Current Score (if game ends now):**
| Feature              | Points                                   |
|----------------------|------------------------------------------|
| Incomplete Road      | 1 per tile                               |
| Incomplete City      | 1 per tile + 1 per shield                |
| Incomplete Monastery | 1 per tile (center + filled surrounding) |

### 7.4 Display

```swift
struct ScoreAnalysis {
    let features: [ScoredFeature]
}

struct ScoredFeature {
    let feature: Feature
    let potentialValue: Int
    let currentValue: Int
    let owningPlayer: PlayerColor?
}
```

---

## 8. Additional Data Models

This section defines models not covered in previous sections.

### 8.1 TileType Enum

```swift
enum TileType: String, CaseIterable, Codable {
    // Base game - City configurations (43 tiles)
    case cityFull                    // Full city (4 walls)
    case cityThreeSides              // City on 3 sides
    case cityTwoAdjacentConnected    // City on 2 adjacent sides, connected
    case cityTwoAdjacentSeparated    // City on 2 adjacent sides, separated
    case cityTwoOppositeConnected    // City on 2 opposite sides, connected (corridor)
    case cityTwoOppositeSeparated    // City on 2 opposite sides, separated
    // ... (complete enumeration of all 72 base types)

    // River expansion (12 tiles)
    case riverSource
    case riverEnd
    case riverStraight
    case riverCurve
    // ... (complete enumeration of all 12 river types)

    var edges: TileEdges { /* return edge configuration */ }
    var hasShield: Bool { /* return if tile has shield */ }
    var hasMonastery: Bool { /* return if tile has monastery */ }
    var hasSeparatedCities: Bool { /* return if multiple city edges are independent */ }
    var category: TileCategory { /* return category */ }
}

enum TileCategory: String, Codable {
    case city
    case road
    case monastery
    case river
    case mixed
}
```

### 8.2 GameSession Structure

```swift
struct GameSession: Codable {
    let id: UUID
    let createdAt: Date
    var lastModified: Date

    var edition: GameEdition
    var board: BoardState          // See Section 6.1
    var inventory: TileInventory   // See Section 6.3

    var isComplete: Bool {
        inventory.totalRemaining == 0
    }
}

enum GameEdition: String, Codable {
    case base = "BASE"
    case baseWithRiver = "BASE_RIVER"

    var initialTileCounts: [TileType: Int] {
        // Return tile counts for edition
    }

    var totalTiles: Int {
        switch self {
        case .base: return 72
        case .baseWithRiver: return 84
        }
    }
}
```

### 8.3 Direction Enum

```swift
enum Direction: CaseIterable {
    case north, east, south, west

    var opposite: Direction {
        switch self {
        case .north: return .south
        case .south: return .north
        case .east:  return .west
        case .west:  return .east
        }
    }
}
```

---

## 9. Implementation Roadmap

### Phase 3: Tile Detection
**Goal:** Detect and localize tiles using YOLO

**Tasks:**
- Train YOLOv8-nano on annotated board images
- Convert to CoreML format
- Implement tile extraction from detections
- Handle rotation normalization

**Deliverables:**
- `CarcassonneTileDetector.mlmodel` (YOLO)
- `TileDetector.swift` - Detection wrapper
- `TileExtractor.swift` - Crop and normalize tiles

### Phase 4: Tile Classification
**Goal:** Identify tile types using MobileNetV2

**Tasks:**
- Collect training data (300+ images per class)
- Train MobileNetV2 with augmentation
- Convert to CoreML format
- Integrate with YOLO detection pipeline

**Deliverables:**
- `CarcassonneTileClassifier.mlmodel`
- `TileClassifier.swift` - Classification wrapper
- End-to-end detection + classification pipeline

### Phase 5: Game Logic
**Goal:** Track game state and validate placements

**Tasks:**
- Implement BoardState and tile placement
- Encode all 84 tile edge configurations
- Implement edge matching validation
- Calculate remaining tiles and probabilities

**Deliverables:**
- `Models/BoardState.swift`
- `Models/TileType.swift` (complete definitions)
- `GameEngine/PlacementValidator.swift`
- `GameEngine/ProbabilityCalculator.swift`

### Phase 6: Helper Features
**Goal:** User-facing assistance features

**Tasks:**
- Remaining tiles display UI
- Valid placement overlay on AR view
- Probability percentage display
- Integration with existing AR/2D views

**Deliverables:**
- `Views/RemainingTilesView.swift`
- `Views/PlacementOverlay.swift`
- Updated ContentView integration

### Phase 7: Polish & Scoring (Future)
**Goal:** Production-ready UX and optional scoring

**Tasks:**
- AR overlay animations
- Performance optimization
- Scoring engine implementation
- Error handling and edge cases

---

## 10. Performance Considerations

### 10.1 On-Device ML Constraints

**Target Device:** iPhone 12 or newer (A14 Bionic+)

**Model Size Targets:**
| Model                  | Size Target |
|------------------------|-------------|
| YOLO detector          | ~5-10MB     |
| MobileNetV2 classifier | ~10-15MB    |
| Total ML assets        | <25MB       |

**Inference Time Targets:**
| Operation                   | Target | Acceptable |
|-----------------------------|--------|------------|
| YOLO detection (full board) | <500ms | <1s        |
| Single tile classification  | <10ms  | <20ms      |
| Full pipeline (80 tiles)    | <1s    | <2s        |

**Optimization Techniques:**
- FP16 quantization
- Neural Engine delegation (automatic in CoreML)
- Batch inference for tile classification

### 10.2 Memory Budget

| Component        | Budget     |
|------------------|------------|
| AR session       | ~100MB     |
| ML models        | ~50MB      |
| Image buffers    | ~50MB      |
| Game state       | <10MB      |
| **Total target** | **<250MB** |

### 10.3 Memory Management

**Best Practices:**
```swift
// Use autorelease pools for batch processing
for tile in extractedTiles {
    autoreleasepool {
        let result = classifier.classify(tile.image)
        // Process result
    }
}
```

- Reuse CVPixelBuffer for consecutive frames
- Use shared CIContext (singleton pattern)
- Clear processed images promptly

---

## 11. Testing Strategy

### 11.1 Unit Tests for Game Logic

**Test Categories:**
- Edge matching: All valid/invalid edge combinations
- Placement validation: Edge cases, first tile, surrounded positions
- Probability calculation: Known game states with expected results
- Tile inventory: Addition, removal, remaining counts

### 11.2 ML Model Validation

**Metrics:**
- Per-class accuracy (target: >90%)
- Confusion matrix analysis
- Cross-validation on held-out set

**Real-World Testing:**
- Different lighting conditions
- Various camera angles
- Worn/damaged tiles

### 11.3 Integration Testing

**Scenarios:**
- Full game simulation (72 tiles)
- Mid-game recognition (partial boards)
- River extension games
- Rotated board captures

---

*Document Version: 2.0*
*Last Updated: December 2025*
*Status: Phase 1-2 Implemented, Phases 3-7 Planned*
