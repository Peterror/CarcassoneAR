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
                        coordinator.updateScreenCenteredCaptureRegion(planeAnchor: nil)
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
                    coordinator.updateScreenCenteredCaptureRegion(planeAnchor: nil)
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

        /// Calculate and update the screen-centered capture region with phone-aligned rotation.
        ///
        /// This is the main method that orchestrates the capture region calculation. It:
        /// 1. Projects screen center onto the plane's infinite surface
        /// 2. Calculates rotation quaternion to align with camera's full 3D orientation
        /// 3. Finds the largest square that fits in the camera view
        /// 4. Updates the 3D visualization (green mesh and cyan sphere)
        /// 5. Stores the capture region data for later use during image capture
        ///
        /// This method is called continuously as the plane updates and the camera moves, ensuring
        /// the capture region always reflects the current screen center and phone orientation.
        ///
        /// - Parameters:
        ///   - planeAnchor: The detected plane anchor (locked plane). If nil, the method will attempt to extract it from the raycast result.
        func updateScreenCenteredCaptureRegion(planeAnchor: ARPlaneAnchor?) {
            guard let frame = arView.session.currentFrame else { return }
            if (lockedPlaneID == nil) { return }  // If no plane locked, return
            
            let imageResolution = CGSize(
                width: CGFloat(CVPixelBufferGetWidth(frame.capturedImage)),
                height: CGFloat(CVPixelBufferGetHeight(frame.capturedImage))
            )

            // Use ARRaycastQuery to find where screen center intersects the plane
            // Create raycast query for existing plane geometry
            let raycastQuery = ARRaycastQuery(
                origin: frame.camera.transform.columns.3.xyz,
                direction: -frame.camera.transform.columns.2.xyz,
                allowing: .existingPlaneGeometry,
                alignment: .horizontal
            )

            let raycastResults = arView.session.raycast(raycastQuery)

            guard let firstResult = raycastResults.first else {
                AppLogger.arCoordinator.error("Raycast did not hit plane")
                return
            }

            // Extract plane anchor from raycast result if not provided
            let resolvedPlaneAnchor: ARPlaneAnchor
            if let providedAnchor = planeAnchor {
                resolvedPlaneAnchor = providedAnchor
            } else {
                // Try to extract plane anchor from raycast result
                guard let anchor = firstResult.anchor as? ARPlaneAnchor else {
                    AppLogger.arCoordinator.error("Raycast result does not contain a plane anchor")
                    return
                }
                resolvedPlaneAnchor = anchor
                AppLogger.arCoordinator.debug("Extracted plane anchor from raycast result")
            }

            // Extract plane position and orientation
            let planePosition = SIMD3<Float>(
                resolvedPlaneAnchor.transform.columns.3.xyz
            )
            let planeQuaternion = simd_quatf(resolvedPlaneAnchor.transform)
            let planeEuler = planeQuaternion.toEulerAngles()

            // Extract camera position and orientation
            let cameraPosition = SIMD3<Float>(
                frame.camera.transform.columns.3.xyz
            )
            let cameraQuaternion = simd_quatf(frame.camera.transform)
            let cameraEuler = cameraQuaternion.toEulerAngles()

            AppLogger.arCoordinator.debug("Plane & Camera Transforms:")
            AppLogger.arCoordinator.debug("  Plane Position: (\(planePosition.x, format: .fixed(precision: 3)), \(planePosition.y, format: .fixed(precision: 3)), \(planePosition.z, format: .fixed(precision: 3)))")
            AppLogger.arCoordinator.debug("  Plane Euler (deg): Roll=\(planeEuler.x, format: .fixed(precision: 1))°, Pitch=\(planeEuler.y, format: .fixed(precision: 1))°, Yaw=\(planeEuler.z, format: .fixed(precision: 1))°")
            AppLogger.arCoordinator.debug("  Camera Position: (\(cameraPosition.x, format: .fixed(precision: 3)), \(cameraPosition.y, format: .fixed(precision: 3)), \(cameraPosition.z, format: .fixed(precision: 3)))")
            AppLogger.arCoordinator.debug("  Camera Euler (deg): Roll=\(cameraEuler.x, format: .fixed(precision: 1))°, Pitch=\(cameraEuler.y, format: .fixed(precision: 1))°, Yaw=\(cameraEuler.z, format: .fixed(precision: 1))°")

            // Extract the 3D world position where the ray hit the plane
            let captureCenter = SIMD3<Float>(
                firstResult.worldTransform.columns.3.xyz
            )

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

            // Update visualization with square region at screen center
            updatePlaneVisualization(
                planeAnchor: resolvedPlaneAnchor,
                captureCenter: captureCenter,
                rotationQuaternion: squareRegionData.rotationQuaternion,
                width: squareRegionData.width,
                height: squareRegionData.height
            )

            // Calculate projected corners for visualization
            // Note: squareRegionData already contains rotationQuaternion, so we use it by default
            let corners3D = PerspectiveTransformCalculator.calculatePlaneCorners(
                planeData: squareRegionData
            )
            let corners2D = PerspectiveTransformCalculator.projectCornersToImage(
                corners3D: corners3D,
                camera: frame.camera,
                imageResolution: imageResolution
            )

            // Update coordinator state and bindings immediately
            // ARSession delegate runs on main thread in iOS 26+
            currentPlaneData = squareRegionData
            lockedPlaneDataBinding.wrappedValue = squareRegionData
            projectedCornersBinding.wrappedValue = corners2D
            cameraImageSizeBinding.wrappedValue = imageResolution
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
        /// It reuses the transformation data already calculated in updateScreenCenteredCaptureRegion():
        /// 1. Captures the raw camera image from ARSession
        /// 2. Converts CVPixelBuffer to UIImage with correct orientation
        /// 3. Uses already-calculated corner positions from parent.projectedCorners
        /// 4. Rotates corner coordinates to match portrait orientation
        /// 5. Packages everything into a CapturedFrame for display in View2D
        ///
        /// Note: Most transformation calculations are done in updateScreenCenteredCaptureRegion(),
        /// so this method simply captures the image and packages the pre-calculated data.
        func captureCameraFrameWithTransform() {
            AppLogger.arCoordinator.info("═══════════════════════════════════════════════════════")
            AppLogger.arCoordinator.info("Capturing Camera Frame")
            AppLogger.arCoordinator.info("═══════════════════════════════════════════════════════")

            guard let frame = arView.session.currentFrame else {
                AppLogger.arCoordinator.error("arView.session.currentFrame is nil")
                return
            }

            guard let planeData = currentPlaneData else {
                AppLogger.arCoordinator.error("currentPlaneData is nil - no plane detected")
                return
            }

            guard let corners2D = projectedCornersBinding.wrappedValue else {
                AppLogger.arCoordinator.error("projectedCorners is nil - transformation not calculated")
                return
            }

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

            // Use already-calculated image resolution from bindings
            let imageResolution = cameraImageSizeBinding.wrappedValue
            AppLogger.arCoordinator.debug("─────────────────────────────────────────────────────")
            AppLogger.arCoordinator.debug("Cached Image Resolution: \(imageResolution.width, format: .fixed(precision: 0)) × \(imageResolution.height, format: .fixed(precision: 0))")

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
                planeData: planeData,
                maxWidth: 2048
            )

            let pixelsPerMeter = PerspectiveTransformCalculator.estimatePixelsPerMeter(
                planeData: planeData,
                outputSize: outputSize
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
