# Development Plan for CarcassoneAR

This document outlines the incremental development steps for the CarcassoneAR application. Each step is designed to be testable before proceeding to the next.

## Application Requirements

- **Main AR View**: Shows live AR camera feed with horizontal plane detection
- **Reset Button**: Clears current anchor and restarts plane detection
- **2D Button**: Switches from AR view to 2D mapped surface view
- **2D View**: Displays the scanned table surface in 2D with a 3D button to return to AR view

## Development Steps

### Step 1: Create basic UI layout with Reset and 2D buttons overlaying AR view

**Implementation:**
- [x] Add two buttons overlaying the AR camera view in ContentView
- [x] Position Reset button (bottom-left corner)
- [x] Position 2D button (bottom-right corner)
- [x] Style buttons for good visibility over camera feed (background, padding, colors)

**Testing:**
- [x] Build and run on device
- [x] Verify both buttons appear on screen
- [x] Verify buttons are tappable (can add print statements)
- [x] Check button visibility against camera background

---

### Step 2: Implement view state management to switch between AR and 2D views

**Implementation:**
- [x] Create enum for view modes: `enum ViewMode { case ar, view2D }`
- [x] Add `@State var viewMode: ViewMode = .ar` to ContentView
- [x] Connect 2D button tap to change viewMode to `.view2D`
- [x] Add conditional rendering based on viewMode

**Testing:**
- [x] Tap 2D button
- [x] Verify state changes (can temporarily show Text with current mode)
- [x] Verify AR view is hidden when in 2D mode

---

### Step 3: Create 2D view with 3D button that returns to AR view

**Implementation:**
- [x] Create new `View2D` SwiftUI view with placeholder background
- [x] Add "3D" button to View2D (positioned at bottom-right)
- [x] Wire 3D button to change viewMode back to `.ar`
- [x] Integrate View2D into ContentView's conditional rendering

**Testing:**
- [x] Tap 2D button → should show View2D with placeholder content
- [x] Tap 3D button → should return to AR camera view
- [x] Test switching back and forth multiple times

---

### Step 4: Implement Reset button functionality to clear and re-detect plane anchor

**Implementation:**
- [x] Add mechanism to remove existing anchor from RealityView content
- [x] Create reset trigger (using @State Bool or custom mechanism)
- [x] Clear anchor and cursor entities when Reset is pressed
- [x] Allow RealityView to detect new plane

**Testing:**
- [x] Let plane detection find a surface (cursor appears)
- [x] Tap Reset button
- [x] Verify cursor disappears
- [x] Point camera at different surface
- [x] Verify new plane is detected and cursor appears on new location

---

### Step 5: Extract plane geometry data from detected horizontal surface

**Implementation:**
- [x] Access the `AnchorEntity`'s underlying plane anchor data
- [x] Extract plane extent (width and depth in meters)
- [x] Extract plane center position and transform
- [x] Store plane geometry in @State or ObservableObject for access across views

**Testing:**
- [x] Run app and detect a plane
- [x] Print/log plane dimensions to console
- [x] Verify logged dimensions (currently shows minimum bounds: 0.4m x 0.4m)
- [x] Plane data is successfully extracted and stored

---

### Step 6: Visualize plane boundaries in AR view for debugging

**Implementation:**
- [x] Create visual representation of detected plane boundaries
- [x] Add plane outline mesh or grid overlay to the anchor
- [x] Use contrasting color (e.g., green or white) for visibility
- [x] Update visualization when plane updates

**Testing:**
- [x] Detect a plane
- [x] Verify visual outline/grid matches the detected surface area
- [x] Walk around table to see if boundaries align with physical edges
- [x] Test with different table sizes

---

### Step 7: Convert plane geometry to 2D coordinate system and render in 2D view

**Implementation:**
- [x] Map plane's X and Z coordinates (horizontal dimensions) to 2D canvas coordinates
- [x] Calculate appropriate scale to fit screen (with margins)
- [x] Draw plane shape/outline in View2D using Canvas or Shape
- [x] Show plane dimensions or scale reference
- [x] **BONUS:** Capture and display actual camera frame in 2D view

**Testing:**
- [x] Detect a plane in AR view
- [x] Switch to 2D view
- [x] Verify 2D representation shows plane outline
- [x] Compare proportions: rectangular table should look rectangular in 2D
- [x] Test with different table sizes and shapes
- [x] **BONUS:** Verify camera image is captured and displayed

---

### Step 8: Polish UI and add visual feedback for plane detection state

**Implementation:**
- [x] Add scanning indicator before plane is detected (e.g., "Scanning for surface...")
- [x] Disable 2D button until plane data is available
- [x] Add visual feedback when plane is detected (e.g., "Surface detected")
- [x] Improve button styling: rounded corners, shadows, proper contrast
- [x] Add smooth transitions between states

**Testing:**
- [x] Fresh app launch: verify scanning indicator appears
- [x] Verify 2D button is disabled/grayed out initially
- [x] When plane detected: verify indicator changes and 2D button becomes enabled
- [x] Test Reset: verify scanning indicator reappears
- [x] Evaluate overall UX smoothness and polish

---

---

### Step 9: Implement homography matrix calculation for perspective transformation

**Implementation:**
- [x] Create PerspectiveTransform.swift with data structures and calculator classes
- [x] Implement PerspectiveTransformCalculator to calculate 3D plane corners in world space
- [x] Implement camera projection from 3D world coordinates to 2D pixel coordinates
- [x] Create TransformQuality validation (camera angle, corner visibility, resolution)
- [x] Implement ImageTransformProcessor using Core Image CIPerspectiveCorrection
- [x] Update ARViewContainer to use captureCameraFrameWithTransform()
- [x] Update View2D to process and display transformed images
- [x] Add detailed console logging for debugging

**Testing:**
- [ ] Build and run on physical device (ARKit not supported in Simulator)
- [ ] Detect plane and verify console shows transformation calculations
- [ ] Verify corner coordinates are within image bounds
- [ ] Check quality metrics (camera angle, visibility, pixels per meter)
- [ ] Capture from different angles (30°, 45°, 60°, 75°) and compare results
- [ ] Test with reference objects (ruler, rectangle) to validate transformation accuracy
- [ ] Verify transformed image shows true top-down view (parallel lines stay parallel)
- [ ] Test edge cases (small planes, large planes, oblique angles)

**Reference:** See STEP_9_TESTING.md and TECHNICAL_DESIGN.md for detailed testing procedures and technical documentation.

---

## Completion Criteria

### Phase 1 (Steps 1-8) - COMPLETED
1. Display AR camera view with Reset and 2D buttons
2. Detect horizontal surfaces (tables) automatically
3. Allow resetting plane detection via Reset button
4. Switch to 2D mapped view via 2D button
5. Show accurate 2D representation of scanned surface
6. Return to AR view via 3D button in 2D view
7. Provide clear visual feedback throughout the experience

### Phase 2 (Steps 9-15) - Top-Down Perspective Transformation
8. Calculate perspective transformation matrix from camera view to top-down orthogonal view
9. Apply transformation to create accurate top-down view of detected surface
10. Support both snapshot and live transformation modes
11. Provide consistent orientation and scale in 2D view
12. Allow zoom, pan, and basic annotations
13. Export transformed images
14. Maintain smooth performance and good image quality
