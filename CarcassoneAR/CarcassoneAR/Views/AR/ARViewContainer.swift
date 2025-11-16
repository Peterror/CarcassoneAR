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
    @Binding var planeData: PlaneData?
    @Binding var capturedFrame: CapturedFrame?
    @Binding var resetTrigger: Bool
    @Binding var captureNow: Bool
    @Binding var projectedCorners: [CGPoint]?
    @Binding var cameraImageSize: CGSize

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Store reference in coordinator
        context.coordinator.arView = arView

        // Start AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        arView.session.run(configuration)

        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        // Set up session delegate if not already set
        if context.coordinator.sessionDelegate == nil {
            let delegate = PlaneDetectionDelegate(coordinator: context.coordinator, parent: self)
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
                planeData = nil
                resetTrigger = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // ARSession delegate to handle plane detection events
    class PlaneDetectionDelegate: NSObject, ARSessionDelegate {
        weak var coordinator: Coordinator?
        var parent: ARViewContainer

        init(coordinator: Coordinator, parent: ARViewContainer) {
            self.coordinator = coordinator
            self.parent = parent
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

                        guard let arView = coordinator.arView else { return }

                        // Calculate and update screen-centered capture region
                        coordinator.updateScreenCenteredCaptureRegion(arView: arView, planeAnchor: planeAnchor)
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
                        guard let arView = coordinator.arView else { return }

                        // Update locked plane transform as ARKit refines it
                        coordinator.lockedPlaneTransform = planeAnchor.transform

                        // Recalculate screen-centered capture region (follows camera movement)
                        coordinator.updateScreenCenteredCaptureRegion(arView: arView, planeAnchor: planeAnchor)
                    }
                }
            }
        }
    }

    class Coordinator {
        var parent: ARViewContainer
        var arView: ARView?
        var planeEntities: [UUID: AnchorEntity] = [:]
        var sessionDelegate: PlaneDetectionDelegate?
        var lockedPlaneID: UUID?
        var lockedPlaneTransform: simd_float4x4?  // Store locked plane's transform
        var currentPlaneData: PlaneData?  // Store plane data in coordinator

        init(_ parent: ARViewContainer) {
            self.parent = parent
        }

        /// Convert quaternion to Euler angles (in degrees) using ARKit's rotation order.
        ///
        /// ARKit applies rotations in the order: Roll (X) → Pitch (Y) → Yaw (Z).
        /// This function extracts Euler angles from a quaternion using the XYZ convention
        /// to match ARKit's coordinate system and rotation order.
        ///
        /// - Parameter q: The quaternion to convert
        /// - Returns: SIMD3<Float> containing (roll, pitch, yaw) in degrees
        func quaternionToEulerAngles(_ q: simd_quatf) -> SIMD3<Float> {
            // Extract quaternion components
            let w = q.vector.w
            let x = q.vector.x
            let y = q.vector.y
            let z = q.vector.z

            // Roll (X-axis rotation) - applied first
            let sinr_cosp = 2 * (w * x + y * z)
            let cosr_cosp = 1 - 2 * (x * x + y * y)
            let roll = atan2(sinr_cosp, cosr_cosp)

            // Pitch (Y-axis rotation) - applied second
            let sinp = 2 * (w * y - z * x)
            let pitch: Float
            if abs(sinp) >= 1 {
                // Gimbal lock case: use ±90 degrees
                pitch = copysign(.pi / 2, sinp)
            } else {
                pitch = asin(sinp)
            }

            // Yaw (Z-axis rotation) - applied third
            let siny_cosp = 2 * (w * z + x * y)
            let cosy_cosp = 1 - 2 * (y * y + z * z)
            let yaw = atan2(siny_cosp, cosy_cosp)

            // Convert radians to degrees
            let radToDeg: Float = 180.0 / .pi
            return SIMD3<Float>(roll * radToDeg, pitch * radToDeg, yaw * radToDeg)
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
        ///   - arView: The ARView instance containing the AR session
        ///   - planeAnchor: The detected plane anchor (locked plane)
        func updateScreenCenteredCaptureRegion(arView: ARView, planeAnchor: ARPlaneAnchor) {
            guard let frame = arView.session.currentFrame else { return }

            let imageResolution = CGSize(
                width: CGFloat(CVPixelBufferGetWidth(frame.capturedImage)),
                height: CGFloat(CVPixelBufferGetHeight(frame.capturedImage))
            )

            // Extract plane position and orientation
            let planePosition = SIMD3<Float>(
                planeAnchor.transform.columns.3.xyz
            )
            let planeQuaternion = simd_quatf(planeAnchor.transform)
            let planeEuler = quaternionToEulerAngles(planeQuaternion)

            // Extract camera position and orientation
            let cameraPosition = SIMD3<Float>(
                frame.camera.transform.columns.3.xyz
            )
            let cameraQuaternion = simd_quatf(frame.camera.transform)
            let cameraEuler = quaternionToEulerAngles(cameraQuaternion)

            AppLogger.arCoordinator.debug("Plane & Camera Transforms:")
            AppLogger.arCoordinator.debug("  Plane Position: (\(planePosition.x, format: .fixed(precision: 3)), \(planePosition.y, format: .fixed(precision: 3)), \(planePosition.z, format: .fixed(precision: 3)))")
            AppLogger.arCoordinator.debug("  Plane Euler (deg): Roll=\(planeEuler.x, format: .fixed(precision: 1))°, Pitch=\(planeEuler.y, format: .fixed(precision: 1))°, Yaw=\(planeEuler.z, format: .fixed(precision: 1))°")
            AppLogger.arCoordinator.debug("  Camera Position: (\(cameraPosition.x, format: .fixed(precision: 3)), \(cameraPosition.y, format: .fixed(precision: 3)), \(cameraPosition.z, format: .fixed(precision: 3)))")
            AppLogger.arCoordinator.debug("  Camera Euler (deg): Roll=\(cameraEuler.x, format: .fixed(precision: 1))°, Pitch=\(cameraEuler.y, format: .fixed(precision: 1))°, Yaw=\(cameraEuler.z, format: .fixed(precision: 1))°")

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

            // Extract the 3D world position where the ray hit the plane
            let captureCenter = SIMD3<Float>(
                firstResult.worldTransform.columns.3.xyz
            )

            AppLogger.arCoordinator.debug("  Raycast hit at: (\(captureCenter.x, format: .fixed(precision: 3)), \(captureCenter.y, format: .fixed(precision: 3)), \(captureCenter.z, format: .fixed(precision: 3)))")

            // Calculate rotation quaternion using viewing direction (camera → raycast hit)
            let captureRegionRotationQuaternion = PerspectiveTransformCalculator.calculateRotationFromViewingDirection(
                planeTransform: planeAnchor.transform,
                cameraWorldPosition: cameraPosition,
                screenCenterHitWorldPosition: captureCenter
            )

            // Calculate largest square region that fits in view
            let squareRegionData = PerspectiveTransformCalculator.calculateVisibleSquareRegion(
                planeTransform: planeAnchor.transform,
                captureCenter: captureCenter,
                rotationQuaternion: captureRegionRotationQuaternion,
                camera: frame.camera,
                imageResolution: imageResolution,
                minDimension: 0.2
            )

            // Update visualization with square region at screen center
            updatePlaneVisualization(
                arView: arView,
                planeAnchor: planeAnchor,
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

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.currentPlaneData = squareRegionData
                self.parent.planeData = squareRegionData
                self.parent.projectedCorners = corners2D
                self.parent.cameraImageSize = imageResolution
            }
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
        ///   - arView: The ARView instance to add/update entities in
        ///   - planeAnchor: The detected plane anchor providing the coordinate system
        ///   - captureCenter: 3D world position where the capture region is centered (currently unused for fixed visualization)
        ///   - rotationQuaternion: Quaternion rotation (currently unused for fixed visualization)
        ///   - width: Width of the capture region in meters
        ///   - height: Height of the capture region in meters
        func updatePlaneVisualization(
            arView: ARView,
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
        /// It performs the following steps:
        /// 1. Captures the raw camera image from ARSession
        /// 2. Converts CVPixelBuffer to UIImage with correct orientation
        /// 3. Creates a PerspectiveTransform using the stored capture region data
        /// 4. Rotates corner coordinates to match portrait orientation
        /// 5. Packages everything into a CapturedFrame for display in View2D
        ///
        /// The transformation data includes corner positions, quality metrics, and the plane geometry,
        /// which can later be used to apply perspective correction and show a top-down orthogonal view.
        func captureCameraFrameWithTransform() {
            guard let arView = arView else {
                AppLogger.arCoordinator.error("arView is nil")
                return
            }

            guard let frame = arView.session.currentFrame else {
                AppLogger.arCoordinator.error("arView.session.currentFrame is nil")
                return
            }

            guard let planeData = currentPlaneData else {
                AppLogger.arCoordinator.error("currentPlaneData is nil")
                return
            }

            AppLogger.arCoordinator.notice("Capturing camera frame with transformation")

            // Get the camera image buffer
            let pixelBuffer = frame.capturedImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            // Create CIContext for rendering
            let context = CIContext()

            // Convert to CGImage
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                AppLogger.arCoordinator.error("Failed to create CGImage")
                return
            }

            // Rotate to correct orientation (portrait)
            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
            AppLogger.arCoordinator.info("Camera image captured: \(uiImage.size.width, format: .fixed(precision: 0)) × \(uiImage.size.height, format: .fixed(precision: 0))")

            // Get image resolution for projection calculations
            let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
            let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
            let imageResolution = CGSize(
                width: CGFloat(bufferWidth),
                height: CGFloat(bufferHeight)
            )
            AppLogger.arCoordinator.debug("Pixel buffer dimensions: \(bufferWidth) × \(bufferHeight)")

            // Calculate perspective transformation
            guard var transform = PerspectiveTransformCalculator.createTransform(
                planeData: planeData,
                camera: frame.camera,
                cameraTransform: frame.camera.transform,
                imageResolution: imageResolution,
                outputMaxWidth: 2048
            ) else {
                AppLogger.arCoordinator.error("Failed to create transformation")
                return
            }

            AppLogger.arCoordinator.info("Transformation calculated:")
            AppLogger.arCoordinator.info("  Camera angle: \(transform.quality.cameraAngleDegrees, format: .fixed(precision: 1))°")
            AppLogger.arCoordinator.info("  Quality: \(transform.quality.qualityDescription)")

            // Rotate corners to match portrait orientation
            let rotatedCorners = transform.sourceCorners.map { corner -> CGPoint in
                CGPoint(
                    x: imageResolution.height - corner.y,
                    y: corner.x
                )
            }

            // Update transform with rotated corners
            transform = PerspectiveTransform(
                sourceCorners: rotatedCorners,
                destinationSize: transform.destinationSize,
                timestamp: transform.timestamp,
                quality: transform.quality
            )

            // Create captured frame
            let capturedFrame = CapturedFrame(
                image: uiImage,
                transform: transform,
                planeData: planeData,
                cameraTransform: frame.camera.transform
            )

            DispatchQueue.main.async {
                self.parent.capturedFrame = capturedFrame
                AppLogger.arCoordinator.info("Captured frame updated successfully")
            }
        }
    }
}
