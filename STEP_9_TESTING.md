# Step 9 Implementation: Testing Guide

## What Was Implemented

Step 9 has been completed with the following components:

### New Files Created

1. **PerspectiveTransform.swift** - Core transformation engine containing:
   - `PerspectiveTransform` struct - Stores transformation data and quality metrics
   - `TransformQuality` struct - Validates transformation quality (camera angle, corner visibility, resolution)
   - `CapturedFrame` struct - Combines image, transformation, and metadata
   - `PerspectiveTransformCalculator` class - Calculates 3D corners, projects to 2D, validates quality
   - `ImageTransformProcessor` class - Applies Core Image perspective correction

2. **TECHNICAL_DESIGN.md** - Complete technical documentation

### Modified Files

1. **ContentView.swift** - Updated to use new transformation system:
   - Replaced `capturedSnapshot: UIImage?` with `capturedFrame: CapturedFrame?`
   - Updated `Coordinator.captureCameraFrameWithTransform()` to calculate transformations
   - Enhanced `View2D` to process and display transformed images
   - Added processing indicator and quality feedback

---

## How to Test

### Prerequisites
- iPhone with ARKit support (iPhone 6s or newer)
- iOS 18.0+ (check deployment target)
- Xcode 16+

### Testing Steps

#### 1. Build and Deploy
```bash
# Open in Xcode
open "CarcassoneAR/CarcassoneAR.xcodeproj"

# Select your iPhone as the target device
# Build and run (Cmd+R)
```

#### 2. Basic Functionality Test

**Step 2.1: Launch and Scan**
- Launch the app on your device
- Point camera at a table or flat surface
- Look for:
  - ✅ "Scanning..." indicator at top
  - ✅ Cyan cursor appears when surface detected
  - ✅ Green semi-transparent plane overlay
  - ✅ Status changes to "Surface Detected"
  - ✅ 2D button becomes enabled (bright white text)

**Step 2.2: Capture and Transform**
- With plane detected, tap the **2D** button
- Watch the console output (Xcode Console) for:
  ```
  === Capturing Camera Frame with Transformation ===
  Camera image captured: (width, height)
  Image resolution: (width, height)
  Transformation calculated:
    Camera angle: X.X°
    All corners visible: true/false
    Pixels per meter: XXX.X
    Quality: (quality description)
    Source corners:
      [0]: (x, y)  // Top-left
      [1]: (x, y)  // Top-right
      [2]: (x, y)  // Bottom-right
      [3]: (x, y)  // Bottom-left
    Destination size: (width, height)
  Captured frame updated successfully

  === Processing Perspective Transformation ===
  Perspective correction applied successfully
    Input size: (width, height)
    Output size: (width, height)
    Quality: (description)
  Transformation completed successfully
  ```

**Step 2.3: View Transformed Image**
- You should see:
  - ✅ "Top-Down View" title
  - ✅ Quality indicator (green dot = good, orange = needs improvement)
  - ✅ Transformed image showing top-down perspective
  - ✅ Plane dimensions (e.g., "0.80m × 1.20m")
  - ✅ Camera angle (e.g., "Camera angle: 45.0°")

**Step 2.4: Return to AR**
- Tap the **3D** button
- Verify you return to AR view

---

#### 3. Quality Validation Tests

**Test 3.1: Good Quality Capture**
- Position camera **45-60° above table**, about 1 meter away
- Ensure entire plane is visible in camera view
- Tap 2D button
- Expected console output:
  - Camera angle: 30-60°
  - All corners visible: true
  - Quality: "Good quality"
- Expected UI: Green quality indicator

**Test 3.2: Oblique Angle (Too Flat)**
- Position camera nearly parallel to table (< 20° above surface)
- Tap 2D button
- Expected console output:
  - Camera angle: 70-90°
  - Quality: "Camera angle too oblique..."
- Expected UI: Orange quality indicator

**Test 3.3: Partial Visibility**
- Position camera so table edges are outside frame
- Tap 2D button
- Expected console output:
  - All corners visible: false
  - Quality: "Plane partially outside view"
- Expected UI: Orange quality indicator

**Test 3.4: Close vs. Far Distance**
- **Close** (0.5m): High pixels per meter, better detail
- **Far** (2m): Lower pixels per meter
- Compare console output for "Pixels per meter" values

---

#### 4. Visual Validation Tests

**Setup**: Place reference objects on table
- Ruler or measuring tape
- Rectangular book or notecard
- Square coaster or tile

**Test 4.1: Parallel Lines**
- Place ruler along table edge
- Capture from oblique angle
- In transformed view, verify:
  - ✅ Table edges appear parallel (not converging)
  - ✅ Ruler appears straight

**Test 4.2: Right Angles**
- Place rectangular object (book/card)
- Capture and verify:
  - ✅ Corners appear as right angles (90°)
  - ✅ Rectangle looks rectangular (not trapezoid)

**Test 4.3: Proportions**
- If table is square: verify transformed image is square
- If table is rectangular (e.g., 2:1 ratio): verify aspect ratio preserved

**Test 4.4: Compare Different Angles**
- Capture from 30°, 45°, 60°, 75° angles
- Verify all produce similar top-down results
- Note: Lower angles (75°+) should show quality warnings

---

#### 5. Corner Projection Validation

**Check Console Logs for Corner Coordinates**

Example valid output:
```
Source corners:
  [0]: (543.2, 234.1)   // Top-left
  [1]: (1234.5, 198.3)  // Top-right
  [2]: (1298.7, 987.6)  // Bottom-right
  [3]: (478.9, 1023.4)  // Bottom-left
```

**Validation Checks**:
- ✅ All X values are between 0 and image width (typically 1920)
- ✅ All Y values are between 0 and image height (typically 1440)
- ✅ Corners form a quadrilateral (not all colinear)
- ✅ Order: TL → TR → BR → BL (clockwise from top-left)

**Invalid Examples** (should trigger warnings):
```
# Corner outside image bounds
[0]: (-23.4, 123.5)  ❌ Negative X

# Corner at infinity (extreme angle)
[1]: (9999.9, 8888.8)  ❌ Outside bounds
```

---

#### 6. Transformation Quality Tests

**Test 6.1: Image Sharpness**
- After transformation, zoom in on text or fine details
- Expected: Should be reasonably sharp, not overly blurred
- Note: Some softening is normal due to perspective correction

**Test 6.2: No Distortion Artifacts**
- Check edges of transformed image
- Should not see:
  - ❌ Extreme warping
  - ❌ Black borders or gaps
  - ❌ Stretched/compressed regions

**Test 6.3: Color Preservation**
- Original and transformed images should have same colors
- No color shifts or saturation changes

---

#### 7. Edge Cases

**Test 7.1: Very Small Plane (0.4m × 0.4m)**
- Use minimum detection size
- Verify transformation still works
- Check "Pixels per meter" - may be lower

**Test 7.2: Large Plane (1.5m × 2m)**
- Use large table
- Verify entire plane is captured
- Check corner visibility

**Test 7.3: Non-Square Planes**
- Test with 2:1, 3:1 aspect ratios
- Verify destination size maintains aspect ratio

**Test 7.4: Reset and Re-capture**
- Detect plane → Capture → View 2D
- Return to AR → Press Reset
- Detect new plane → Capture again
- Verify new capture works correctly

---

## Expected Console Output Pattern

### Successful Capture Flow
```
=== Capturing Camera Frame with Transformation ===
Camera image captured: (1080.0, 1920.0)
Image resolution: (1920.0, 1440.0)
Transformation calculated:
  Camera angle: 42.3°
  All corners visible: true
  Pixels per meter: 256.7
  Quality: Good quality
  Source corners:
    [0]: (534.2, 312.8)
    [1]: (1385.6, 289.4)
    [2]: (1423.1, 1098.7)
    [3]: (496.8, 1122.3)
  Destination size: (1024.0, 682.7)
Captured frame updated successfully

=== Processing Perspective Transformation ===
Perspective correction applied successfully
  Input size: (1920.0, 1440.0)
  Output size: (1024.0, 682.7)
  Quality: Good quality
Transformation completed successfully
```

### Poor Quality Capture
```
Transformation calculated:
  Camera angle: 73.8°
  All corners visible: true
  Pixels per meter: 142.3
  Quality: Camera angle too oblique - move more directly above
```

---

## Troubleshooting

### Problem: No console output when tapping 2D button
**Check**:
- Is plane detected? (Green "Surface Detected" indicator)
- Is 2D button enabled? (Should be white, not gray)
- Check Xcode console is showing debug output

### Problem: "Failed to create transformation" in console
**Possible Causes**:
- Plane data is incomplete
- Camera projection failed
- Corners outside valid range

**Debug**:
- Print planeData values
- Check camera.projectPoint() returns valid coordinates

### Problem: Transformation shows black screen or crashes
**Possible Causes**:
- CIPerspectiveCorrection filter failed
- Invalid corner coordinates
- Memory issue with large image

**Debug**:
- Check corner coordinates are within image bounds
- Verify image size is reasonable
- Check Metal/GPU availability

### Problem: Transformed image looks wrong (heavily distorted)
**Possible Causes**:
- Corner order incorrect
- Coordinate system mismatch (UIKit vs Core Image)
- Extreme viewing angle

**Debug**:
- Verify corner ordering: [TL, TR, BR, BL]
- Check camera angle is < 70°
- Verify all corners visible

---

## Success Criteria for Step 9

- ✅ App builds without errors
- ✅ Plane detection works (from previous steps)
- ✅ Console shows detailed transformation logs
- ✅ Corner coordinates are calculated and projected correctly
- ✅ Quality metrics are displayed (camera angle, visibility, resolution)
- ✅ Perspective transformation is applied
- ✅ Transformed image shows top-down view
- ✅ UI shows quality indicator
- ✅ Process completes in < 1 second on device

---

## Next Steps

Once Step 9 is validated:
- **Step 10**: Enhance transformation quality (sharpening, auto-enhancement)
- **Step 11**: Implement live transformation mode
- **Step 12**: Add orientation lock and zoom controls
- **Step 13**: Optimize edge detection
- **Step 14**: Add annotation tools
- **Step 15**: Polish and export features

---

## Notes for Developers

### Performance Benchmarks
- Transformation calculation: < 50ms
- Image processing: 100-500ms (depends on resolution)
- Total capture-to-display: < 1 second

### Memory Usage
- Raw camera frame: ~8-12 MB
- Transformed image: ~2-4 MB
- Keep only one CapturedFrame in memory at a time

### Known Limitations
- Requires all 4 corners visible in camera frame
- Quality degrades at extreme angles (> 70°)
- Minimum plane size: 0.4m × 0.4m
- iOS Simulator does not support ARKit - must test on device
