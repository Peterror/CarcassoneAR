//
//  ARViewContainer.swift
//  CarcassoneAR
//
//  ARKit wrapper to access camera frames and handle plane detection
//

import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    @Binding var planeData: PlaneData?
    @Binding var capturedFrame: CapturedFrame?
    @Binding var resetTrigger: Bool
    @Binding var captureNow: Bool
    @Binding var projectedCorners: [CGPoint]?

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

            print("🔄 Reset: Unlocked plane, ready to detect new surface")

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
                        print("✅ Plane detected and locked! Size: \(planeAnchor.planeExtent.width)m × \(planeAnchor.planeExtent.height)m")

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

        /// Calculate and update the screen-centered capture region with phone-aligned rotation.
        ///
        /// This is the main method that orchestrates the capture region calculation. It:
        /// 1. Projects screen center onto the plane's infinite surface
        /// 2. Calculates rotation angle to align with camera's forward direction
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

            // Calculate rotation angle to align with camera's forward direction
            let rotationAngle = PerspectiveTransformCalculator.calculateCameraAlignedRotation(
                planeTransform: planeAnchor.transform,
                cameraTransform: frame.camera.transform
            )

            // Project screen center onto plane's infinite surface
            guard let captureCenter = PerspectiveTransformCalculator.projectScreenCenterToPlane(
                planeTransform: planeAnchor.transform,
                camera: frame.camera,
                imageResolution: imageResolution
            ) else { return }

            // Calculate largest square region that fits in view
            let squareRegionData = PerspectiveTransformCalculator.calculateVisibleSquareRegion(
                planeTransform: planeAnchor.transform,
                captureCenter: captureCenter,
                rotationAngle: rotationAngle,
                camera: frame.camera,
                imageResolution: imageResolution
            )

            // Update visualization with square region at screen center
            updatePlaneVisualization(
                arView: arView,
                planeAnchor: planeAnchor,
                captureCenter: captureCenter,
                rotationAngle: squareRegionData.rotationAngle,
                width: squareRegionData.width,
                height: squareRegionData.height
            )

            // Calculate projected corners for visualization
            // Note: squareRegionData already contains rotationAngle, so we use it from there
            let corners3D = PerspectiveTransformCalculator.calculatePlaneCorners(
                planeData: squareRegionData,
                rotationAngle: squareRegionData.rotationAngle
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
            }
        }

        /// Update the 3D visualization of the capture region in the AR scene.
        ///
        /// Creates or updates the visual indicators showing where the capture region is located:
        /// - Green semi-transparent mesh: Shows the capture region boundaries
        /// - Cyan sphere: Marks the center point of the capture region
        ///
        /// Both elements are positioned at the screen-centered capture location and the green mesh
        /// is rotated to align with the phone's orientation. The visualization is anchored to the
        /// detected plane's coordinate system.
        ///
        /// - Parameters:
        ///   - arView: The ARView instance to add/update entities in
        ///   - planeAnchor: The detected plane anchor providing the coordinate system
        ///   - captureCenter: 3D world position where the capture region is centered
        ///   - rotationAngle: Rotation in radians to apply to the green mesh (aligns with camera)
        ///   - width: Width of the capture region in meters
        ///   - height: Height of the capture region in meters
        func updatePlaneVisualization(
            arView: ARView,
            planeAnchor: ARPlaneAnchor,
            captureCenter: SIMD3<Float>,
            rotationAngle: Float,
            width: Float,
            height: Float
        ) {
            let anchorID = planeAnchor.identifier

            if let existingAnchor = planeEntities[anchorID] {
                // Update existing visualization - move to screen-centered position and rotate
                if let planeVisual = existingAnchor.children.first(where: { $0.name == "planeVisual" }) {
                    let newMesh = MeshResource.generatePlane(width: width, depth: height)
                    var planeMaterial = SimpleMaterial()
                    planeMaterial.color = .init(tint: .green.withAlphaComponent(0.3))
                    planeVisual.components.set(ModelComponent(mesh: newMesh, materials: [planeMaterial]))

                    // Apply rotation around Y-axis (normal to plane)
                    planeVisual.orientation = simd_quatf(angle: rotationAngle, axis: SIMD3<Float>(0, 1, 0))
                }

                // Move sphere cursor to screen-centered capture position
                if let cursor = existingAnchor.children.first(where: { $0.name == "cursor" }) {
                    // Convert world position to local position relative to anchor
                    let anchorTransform = planeAnchor.transform
                    let anchorInverse = anchorTransform.inverse
                    let localPos4 = anchorInverse * SIMD4<Float>(captureCenter.x, captureCenter.y, captureCenter.z, 1.0)
                    cursor.position = SIMD3<Float>(localPos4.x, localPos4.y + 0.001, localPos4.z)
                }

                // Move plane visual to screen-centered capture position
                if let planeVisual = existingAnchor.children.first(where: { $0.name == "planeVisual" }) {
                    let anchorTransform = planeAnchor.transform
                    let anchorInverse = anchorTransform.inverse
                    let localPos4 = anchorInverse * SIMD4<Float>(captureCenter.x, captureCenter.y, captureCenter.z, 1.0)
                    planeVisual.position = SIMD3<Float>(localPos4.x, localPos4.y + 0.001, localPos4.z)
                }
            } else {
                // Create new visualization anchored to plane
                let anchorEntity = AnchorEntity(world: planeAnchor.transform)

                // Convert world capture center to local coordinates
                let anchorInverse = planeAnchor.transform.inverse
                let localPos4 = anchorInverse * SIMD4<Float>(captureCenter.x, captureCenter.y, captureCenter.z, 1.0)
                let localPosition = SIMD3<Float>(localPos4.x, localPos4.y + 0.001, localPos4.z)

                // Create cursor at screen-centered position
                let cursor = Entity()
                cursor.name = "cursor"
                let cursorMesh = MeshResource.generateSphere(radius: 0.025)
                cursor.components.set(ModelComponent(
                    mesh: cursorMesh,
                    materials: [SimpleMaterial(color: .cyan, roughness: 0.15, isMetallic: true)]
                ))
                cursor.position = localPosition

                // Create plane visualization at screen-centered position with rotation
                let planeVisual = Entity()
                planeVisual.name = "planeVisual"
                let planeMesh = MeshResource.generatePlane(width: width, depth: height)
                var planeMaterial = SimpleMaterial()
                planeMaterial.color = .init(tint: .green.withAlphaComponent(0.3))
                planeVisual.components.set(ModelComponent(mesh: planeMesh, materials: [planeMaterial]))
                planeVisual.position = localPosition

                // Apply rotation around Y-axis (normal to plane) to align with camera
                planeVisual.orientation = simd_quatf(angle: rotationAngle, axis: SIMD3<Float>(0, 1, 0))

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
                print("ERROR: arView is nil")
                return
            }

            guard let frame = arView.session.currentFrame else {
                print("ERROR: arView.session.currentFrame is nil")
                return
            }

            guard let planeData = currentPlaneData else {
                print("ERROR: currentPlaneData is nil")
                return
            }

            print("\n=== Capturing Camera Frame with Transformation ===")

            // Get the camera image buffer
            let pixelBuffer = frame.capturedImage
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            // Create CIContext for rendering
            let context = CIContext()

            // Convert to CGImage
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
                print("Failed to create CGImage")
                return
            }

            // Rotate to correct orientation (portrait)
            let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
            print("Camera image captured: \(uiImage.size)")

            // Get image resolution for projection calculations
            let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
            let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
            let imageResolution = CGSize(
                width: CGFloat(bufferWidth),
                height: CGFloat(bufferHeight)
            )
            print("Pixel buffer dimensions: \(bufferWidth) × \(bufferHeight)")

            // Calculate perspective transformation
            guard var transform = PerspectiveTransformCalculator.createTransform(
                planeData: planeData,
                camera: frame.camera,
                cameraTransform: frame.camera.transform,
                imageResolution: imageResolution,
                outputMaxWidth: 2048
            ) else {
                print("Failed to create transformation")
                return
            }

            print("Transformation calculated:")
            print("  Camera angle: \(transform.quality.cameraAngleDegrees)°")
            print("  Quality: \(transform.quality.qualityDescription)")

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
                print("Captured frame updated successfully\n")
            }
        }
    }
}
