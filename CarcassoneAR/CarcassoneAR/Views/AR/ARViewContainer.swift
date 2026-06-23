//
//  ARViewContainer.swift
//  CarcassoneAR
//
//  ARKit wrapper to access camera frames and handle plane detection
//

import SwiftUI
import RealityKit
import ARKit
import OSLog

struct ARViewContainer: UIViewRepresentable {
    @Binding var lockedPlane: PlaneData?
    @Binding var capturedFrame: CapturedFrame?
    @Binding var resetTrigger: Bool
    @Binding var captureNow: Bool
    @Binding var projectedCorners: [CGPoint]?
    @Binding var cameraImageSize: CGSize

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Store reference in coordinator
        context.coordinator.arView = arView

        // Store bindings in coordinator
        context.coordinator.lockedPlaneDataBinding = $lockedPlane
        context.coordinator.projectedCornersBinding = $projectedCorners
        context.coordinator.cameraImageSizeBinding = $cameraImageSize
        context.coordinator.capturedFrameBinding = $capturedFrame

        // Start AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        arView.session.run(configuration)

        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        // Update bindings in case they changed (though they shouldn't in this case)
        context.coordinator.lockedPlaneDataBinding = $lockedPlane
        context.coordinator.projectedCornersBinding = $projectedCorners
        context.coordinator.cameraImageSizeBinding = $cameraImageSize
        context.coordinator.capturedFrameBinding = $capturedFrame

        // Set up session delegate if not already set
        if context.coordinator.sessionDelegate == nil {
            let delegate = PlaneDetectionDelegate(coordinator: context.coordinator)
            arView.session.delegate = delegate
            context.coordinator.sessionDelegate = delegate
        }

        // Handle camera capture
        if captureNow {
            context.coordinator.captureCameraFrameWithTransform()
            DispatchQueue.main.async {
                captureNow = false
            }
        }

        // Handle reset
        if resetTrigger {
            // Remove all plane visualizations
            arView.scene.anchors.removeAll()
            context.coordinator.planeEntities.removeAll()
            context.coordinator.lockedPlaneID = nil  // Unlock plane

            // Reset the AR session to clear plane detection
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

            AppLogger.arCoordinator.info("Reset: Unlocked plane, ready to detect new surface")

            DispatchQueue.main.async {
                lockedPlane = nil
                resetTrigger = false
            }
        }
    }

    // TODO read how other projects use this
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // ARSession delegate to handle plane detection events
    class PlaneDetectionDelegate: NSObject, ARSessionDelegate {
        weak var coordinator: Coordinator?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    guard let coordinator = coordinator else { return }

                    // Only lock onto the first plane if we haven't already
                    if coordinator.lockedPlaneID == nil {
                        AppLogger.planeDetection.info("Plane detected and locked! Size: \(planeAnchor.planeExtent.width, format: .fixed(precision: 2))m × \(planeAnchor.planeExtent.height, format: .fixed(precision: 2))m")

                        // Lock onto this plane - store transform for future calculations
                        coordinator.lockedPlaneID = planeAnchor.identifier
                        coordinator.lockedPlaneTransform = planeAnchor.transform

                        // Calculate and update screen-centered capture region
                        coordinator.updateScreenCenteredCaptureRegion()
                    }
                }
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor {
                    guard let coordinator = coordinator else { return }

                    // Only update if this is our locked plane
                    if coordinator.lockedPlaneID == planeAnchor.identifier {
                        // Update locked plane transform as ARKit refines it
                        coordinator.lockedPlaneTransform = planeAnchor.transform

                    }
                    // Recalculate screen-centered capture region (follows camera movement)
                    coordinator.updateScreenCenteredCaptureRegion()
                }
            }
        }
    }

    class Coordinator {
        var arView: ARView!  // Implicitly unwrapped - always set in makeUIView before use
        var planeEntities: [UUID: AnchorEntity] = [:]
        var sessionDelegate: PlaneDetectionDelegate?
        var lockedPlaneID: UUID?
        var lockedPlaneTransform: simd_float4x4?  // Store locked plane's transform
        var currentPlaneData: PlaneData?  // Store plane data in coordinator

        // Store bindings directly to avoid stale parent struct
        var lockedPlaneDataBinding: Binding<PlaneData?>!
        var projectedCornersBinding: Binding<[CGPoint]?>!
        var cameraImageSizeBinding: Binding<CGSize>!
        var capturedFrameBinding: Binding<CapturedFrame?>!

        init() {
        }

        /// Result of computing the capture region for a single AR frame.
        ///
        /// Bundles the geometry derived from one frame so callers always work with a
        /// self-consistent snapshot — image, corners, and plane data all originate from
        /// the same camera pose. This is what prevents the projected corners from
        /// drifting out of sync with the pixels they describe.
        struct CaptureRegion {
            let planeData: PlaneData
            let cornersInImage: [CGPoint]
            let imageResolution: CGSize
            let planeAnchor: ARPlaneAnchor
            let captureCenter: SIMD3<Float>
        }

        /// Compute the screen-centered square capture region for a specific frame.
        ///
        /// All geometry is derived from the supplied `frame`, guaranteeing the returned
        /// corners correspond exactly to that frame's `capturedImage`. This is the single
        /// source of truth used both for continuous visualization updates and for the
        /// final capture, eliminating any mismatch between the image pixels and the
        /// projected corners.
        ///
        /// The method:
        /// 1. Raycasts from screen center onto the locked plane
        /// 2. Calculates a rotation quaternion aligned with the camera's viewing direction
        /// 3. Finds the largest square that fits in the camera view
        /// 4. Projects that square's corners back into image space
        ///
        /// - Parameter frame: The ARFrame to compute the capture region from.
        /// - Returns: A `CaptureRegion` snapshot, or nil if no plane is locked or the
        ///            screen-center raycast misses the plane.
        func computeCaptureRegion(for frame: ARFrame) -> CaptureRegion? {
            guard lockedPlaneID != nil else { return nil }  // If no plane locked, return

            let imageResolution = CGSize(
                width: CGFloat(CVPixelBufferGetWidth(frame.capturedImage)),
                height: CGFloat(CVPixelBufferGetHeight(frame.capturedImage))
            )

            // Use ARRaycastQuery to find where screen center intersects the plane
            let raycastQuery = ARRaycastQuery(
                origin: frame.camera.transform.columns.3.xyz,
                direction: -frame.camera.transform.columns.2.xyz,
                allowing: .existingPlaneGeometry,
                alignment: .horizontal
            )

            guard let firstResult = arView.session.raycast(raycastQuery).first else {
                AppLogger.arCoordinator.error("Raycast did not hit plane")
                return nil
            }

            guard let resolvedPlaneAnchor = firstResult.anchor as? ARPlaneAnchor else {
                AppLogger.arCoordinator.error("Raycast result does not contain a plane anchor")
                return nil
            }

            let cameraPosition = frame.camera.transform.columns.3.xyz
            // 3D world position where the screen-center ray hit the plane
            let captureCenter = firstResult.worldTransform.columns.3.xyz

            AppLogger.arCoordinator.debug("  Raycast hit at: (\(captureCenter.x, format: .fixed(precision: 3)), \(captureCenter.y, format: .fixed(precision: 3)), \(captureCenter.z, format: .fixed(precision: 3)))")

            // Calculate rotation quaternion using viewing direction (camera → raycast hit)
            let captureRegionRotationQuaternion = PerspectiveTransformCalculator.calculateRotationFromViewingDirection(
                planeTransform: resolvedPlaneAnchor.transform,
                cameraWorldPosition: cameraPosition,
                screenCenterHitWorldPosition: captureCenter
            )

            // Calculate largest square region that fits in view
            let squareRegionData = PerspectiveTransformCalculator.calculateVisibleSquareRegion(
                planeTransform: resolvedPlaneAnchor.transform,
                captureCenter: captureCenter,
                rotationQuaternion: captureRegionRotationQuaternion,
                camera: frame.camera,
                imageResolution: imageResolution,
                minDimension: 0.2
            )

            // Project the square's corners back into this frame's image space
            let corners3D = PerspectiveTransformCalculator.calculatePlaneCorners(
                planeData: squareRegionData
            )
            let cornersInImage = PerspectiveTransformCalculator.projectCornersToImage(
                corners3D: corners3D,
                camera: frame.camera,
                imageResolution: imageResolution
            )

            return CaptureRegion(
                planeData: squareRegionData,
                cornersInImage: cornersInImage,
                imageResolution: imageResolution,
                planeAnchor: resolvedPlaneAnchor,
                captureCenter: captureCenter
            )
        }

        /// Recompute the screen-centered capture region and refresh the live overlay.
        ///
        /// Derives the region from the current frame, then updates the 3D visualization
        /// and the bindings that drive the corner overlay. Called continuously as the
        /// plane updates and the camera moves, so the overlay always reflects the current
        /// screen center and phone orientation.
        func updateScreenCenteredCaptureRegion() {
            guard let frame = arView.session.currentFrame else { return }
            guard let region = computeCaptureRegion(for: frame) else { return }

            // Update visualization with square region at screen center
            updatePlaneVisualization(
                planeAnchor: region.planeAnchor,
                captureCenter: region.captureCenter,
                rotationQuaternion: region.planeData.rotationQuaternion,
                width: region.planeData.width,
                height: region.planeData.height
            )

            // Update coordinator state and bindings immediately
            // ARSession delegate runs on main thread in iOS 26+
            currentPlaneData = region.planeData
            lockedPlaneDataBinding.wrappedValue = region.planeData
            projectedCornersBinding.wrappedValue = region.cornersInImage
            cameraImageSizeBinding.wrappedValue = region.imageResolution
        }

        /// Update the 3D visualization of the capture region in the AR scene.
        ///
        /// Creates or updates the visual indicators showing where the capture region is located:
        /// - Green semi-transparent square mesh: Shows the plane's orientation (fixed to plane surface)
        /// - Cyan sphere: Marks the plane's geometric center (fixed position on plane)
        ///
        /// Both elements are fixed to the plane's coordinate system with NO rotation applied,
        /// allowing us to visualize the plane's actual orientation for debugging purposes.
        /// Both visualizations are anchored to the detected plane's coordinate system.
        ///
        /// - Parameters:
        ///   - planeAnchor: The detected plane anchor providing the coordinate system
        ///   - captureCenter: 3D world position where the capture region is centered (currently unused for fixed visualization)
        ///   - rotationQuaternion: Quaternion rotation (currently unused for fixed visualization)
        ///   - width: Width of the capture region in meters
        ///   - height: Height of the capture region in meters
        func updatePlaneVisualization(
            planeAnchor: ARPlaneAnchor,
            captureCenter: SIMD3<Float>,
            rotationQuaternion: simd_quatf,
            width: Float,
            height: Float
        ) {
            let anchorID = planeAnchor.identifier

            // Use fixed square size for debugging (0.5m x 0.5m)
            let fixedSize: Float = 0.5

            if let existingAnchor = planeEntities[anchorID] {
                // Update existing visualization
                if let planeVisual = existingAnchor.children.first(where: { $0.name == "planeVisual" }) {
                    let newMesh = MeshResource.generatePlane(width: fixedSize, depth: fixedSize)
                    var planeMaterial = SimpleMaterial()
                    planeMaterial.color = .init(tint: .green.withAlphaComponent(0.3))
                    planeVisual.components.set(ModelComponent(mesh: newMesh, materials: [planeMaterial]))

                    // NO rotation - fixed to plane's coordinate system
                    planeVisual.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
                }

                // Cyan sphere stays at plane's geometric center (origin) - no position update needed
                // It was positioned at (0, 0.001, 0) in local coordinates when created

                // Green mesh also stays at plane center for debugging
                if let planeVisual = existingAnchor.children.first(where: { $0.name == "planeVisual" }) {
                    planeVisual.position = SIMD3<Float>(0, 0.001, 0)
                }
            } else {
                // Create new visualization anchored to plane
                let anchorEntity = AnchorEntity(world: planeAnchor.transform)

                // Create cyan sphere at plane's geometric center (origin)
                let cursor = Entity()
                cursor.name = "cursor"
                let cursorMesh = MeshResource.generateSphere(radius: 0.025)
                cursor.components.set(ModelComponent(
                    mesh: cursorMesh,
                    materials: [SimpleMaterial(color: .cyan, roughness: 0.15, isMetallic: true)]
                ))
                // Position at plane center (local origin)
                cursor.position = SIMD3<Float>(0, 0.001, 0)

                // Create green square mesh at plane center (local origin) with NO rotation
                let planeVisual = Entity()
                planeVisual.name = "planeVisual"
                let planeMesh = MeshResource.generatePlane(width: fixedSize, depth: fixedSize)
                var planeMaterial = SimpleMaterial()
                planeMaterial.color = .init(tint: .green.withAlphaComponent(0.3))
                planeVisual.components.set(ModelComponent(mesh: planeMesh, materials: [planeMaterial]))
                planeVisual.position = SIMD3<Float>(0, 0.001, 0)

                // NO rotation - fixed to plane's coordinate system for debugging
                planeVisual.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))

                anchorEntity.addChild(cursor)
                anchorEntity.addChild(planeVisual)
                arView.scene.addAnchor(anchorEntity)

                planeEntities[anchorID] = anchorEntity
            }
        }

        /// Capture the current camera frame and create a perspective transformation for it.
        ///
        /// This method is called when the user taps the "2D" button to capture the current view.
        /// 1. Captures the raw camera image from ARSession
        /// 2. Recomputes the capture region from that same frame via computeCaptureRegion(for:)
        /// 3. Converts CVPixelBuffer to UIImage with correct orientation
        /// 4. Rotates corner coordinates to match portrait orientation
        /// 5. Packages everything into a CapturedFrame for display in View2D
        ///
        /// The corners are recomputed from the captured frame (rather than reused from the
        /// live overlay bindings) so the projected corners always correspond to the exact
        /// pixels being captured, even if the camera moved since the last overlay update.
        func captureCameraFrameWithTransform() {
            AppLogger.arCoordinator.info("═══════════════════════════════════════════════════════")
            AppLogger.arCoordinator.info("Capturing Camera Frame")
            AppLogger.arCoordinator.info("═══════════════════════════════════════════════════════")

            guard let frame = arView.session.currentFrame else {
                AppLogger.arCoordinator.error("arView.session.currentFrame is nil")
                return
            }

            // Recompute the capture region from THIS frame so the projected corners
            // correspond exactly to the pixels we are about to capture. Reusing the
            // cached binding here would mismatch the image whenever the camera moved
            // between the last overlay update and this capture.
            guard let region = computeCaptureRegion(for: frame) else {
                AppLogger.arCoordinator.error("Failed to compute capture region for current frame")
                return
            }

            let planeData = region.planeData
            let corners2D = region.cornersInImage
            let imageResolution = region.imageResolution

            // Get the camera image buffer
            let pixelBuffer = frame.capturedImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            AppLogger.arCoordinator.debug("Camera Buffer Details:")
            AppLogger.arCoordinator.debug("  CVPixelBuffer width: \(CVPixelBufferGetWidth(pixelBuffer))")
            AppLogger.arCoordinator.debug("  CVPixelBuffer height: \(CVPixelBufferGetHeight(pixelBuffer))")
            AppLogger.arCoordinator.debug("  CIImage.extent: \(String(describing: ciImage.extent))")
            AppLogger.arCoordinator.debug("  CIImage.extent.size: \(ciImage.extent.width, format: .fixed(precision: 0)) × \(ciImage.extent.height, format: .fixed(precision: 0))")

            // Create CIContext for rendering
            let context = CIContext()

            // Convert to CGImage
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                AppLogger.arCoordinator.error("Failed to create CGImage")
                return
            }

            AppLogger.arCoordinator.debug("  CGImage.width: \(cgImage.width)")
            AppLogger.arCoordinator.debug("  CGImage.height: \(cgImage.height)")

            // Rotate to correct orientation (portrait)
            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
            AppLogger.arCoordinator.debug("  UIImage.size (after .right orientation): \(uiImage.size.width, format: .fixed(precision: 0)) × \(uiImage.size.height, format: .fixed(precision: 0))")
            AppLogger.arCoordinator.debug("  UIImage.orientation: .right (rawValue: \(uiImage.imageOrientation.rawValue))")

            AppLogger.arCoordinator.debug("─────────────────────────────────────────────────────")
            AppLogger.arCoordinator.debug("Image Resolution: \(imageResolution.width, format: .fixed(precision: 0)) × \(imageResolution.height, format: .fixed(precision: 0))")

            // Log landscape corners (as projected by ARCamera)
            AppLogger.arCoordinator.debug("─────────────────────────────────────────────────────")
            AppLogger.arCoordinator.debug("Projected Corners (Landscape coordinates from ARCamera):")
            AppLogger.arCoordinator.debug("  [0] (\(corners2D[0].x, format: .fixed(precision: 1)), \(corners2D[0].y, format: .fixed(precision: 1)))")
            AppLogger.arCoordinator.debug("  [1] (\(corners2D[1].x, format: .fixed(precision: 1)), \(corners2D[1].y, format: .fixed(precision: 1)))")
            AppLogger.arCoordinator.debug("  [2] (\(corners2D[2].x, format: .fixed(precision: 1)), \(corners2D[2].y, format: .fixed(precision: 1)))")
            AppLogger.arCoordinator.debug("  [3] (\(corners2D[3].x, format: .fixed(precision: 1)), \(corners2D[3].y, format: .fixed(precision: 1)))")

            // Rotate corners to match portrait orientation
            // corners2D are in landscape orientation (from ARCamera), convert to portrait
            // Rotation formula: portrait_x = landscape_image_height - landscape_y, portrait_y = landscape_x
            let rotatedCorners = corners2D.map { corner -> CGPoint in
                CGPoint(
                    x: imageResolution.height - corner.y,
                    y: corner.x
                )
            }

            AppLogger.arCoordinator.debug("Rotated Corners (Portrait coordinates for UIImage):")
            AppLogger.arCoordinator.debug("  [0] (\(rotatedCorners[0].x, format: .fixed(precision: 1)), \(rotatedCorners[0].y, format: .fixed(precision: 1)))")
            AppLogger.arCoordinator.debug("  [1] (\(rotatedCorners[1].x, format: .fixed(precision: 1)), \(rotatedCorners[1].y, format: .fixed(precision: 1)))")
            AppLogger.arCoordinator.debug("  [2] (\(rotatedCorners[2].x, format: .fixed(precision: 1)), \(rotatedCorners[2].y, format: .fixed(precision: 1)))")
            AppLogger.arCoordinator.debug("  [3] (\(rotatedCorners[3].x, format: .fixed(precision: 1)), \(rotatedCorners[3].y, format: .fixed(precision: 1)))")
            AppLogger.arCoordinator.debug("  (These should match CGImage dimensions: \(cgImage.width) × \(cgImage.height))")

            // Calculate quality metrics (these are cheap calculations)
            let cameraAngle = PerspectiveTransformCalculator.calculateCameraAngle(
                planeTransform: planeData.transform,
                cameraTransform: frame.camera.transform
            )

            let allVisible = PerspectiveTransformCalculator.areAllCornersVisible(
                corners: corners2D,
                imageSize: imageResolution
            )

            let outputSize = PerspectiveTransformCalculator.calculateOutputSize(
                corners: corners2D,
                planeData: planeData,
                maxWidth: 2048
            )

            let pixelsPerMeter = PerspectiveTransformCalculator.estimatePixelsPerMeter(
                corners2D: corners2D,
                planeData: planeData
            )

            let quality = TransformQuality(
                cameraAngleDegrees: cameraAngle,
                allCornersVisible: allVisible,
                estimatedPixelsPerMeter: pixelsPerMeter
            )

            AppLogger.arCoordinator.info("─────────────────────────────────────────────────────")
            AppLogger.arCoordinator.info("Transformation Quality Metrics:")
            AppLogger.arCoordinator.info("  Camera angle: \(quality.cameraAngleDegrees, format: .fixed(precision: 1))°")
            AppLogger.arCoordinator.info("  All corners visible: \(quality.allCornersVisible)")
            AppLogger.arCoordinator.info("  Pixels per meter: \(quality.estimatedPixelsPerMeter, format: .fixed(precision: 0))")
            AppLogger.arCoordinator.info("  Overall quality: \(quality.qualityDescription)")
            AppLogger.arCoordinator.info("  Output size: \(outputSize.width, format: .fixed(precision: 0)) × \(outputSize.height, format: .fixed(precision: 0))")

            // Create transform with both landscape and portrait corners
            let transform = PerspectiveTransform(
                landscapeCorners: corners2D,        // Original landscape corners for CIPerspectiveCorrection
                portraitCorners: rotatedCorners,    // Rotated portrait corners for UI display
                destinationSize: outputSize,
                timestamp: Date().timeIntervalSince1970,
                quality: quality
            )

            // Create captured frame
            let capturedFrame = CapturedFrame(
                image: uiImage,
                transform: transform,
                planeData: planeData,
                cameraTransform: frame.camera.transform
            )

            AppLogger.arCoordinator.info("─────────────────────────────────────────────────────")
            AppLogger.arCoordinator.info("✓ Captured Frame Created Successfully")
            AppLogger.arCoordinator.info("  Ready for perspective transformation")
            AppLogger.arCoordinator.info("═══════════════════════════════════════════════════════")

            // Update binding asynchronously to avoid "modifying state during view update" warning
            DispatchQueue.main.async {
                self.capturedFrameBinding.wrappedValue = capturedFrame
                AppLogger.arCoordinator.info("Captured frame binding updated")
            }
        }
    }
}
