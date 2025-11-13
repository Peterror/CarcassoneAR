//
//  PerspectiveTransform.swift
//  CarcassoneAR
//
//  Utilities for perspective transformation calculations
//  Converts oblique AR camera views into orthogonal top-down views
//

import Foundation
import ARKit
import CoreImage
import simd
import OSLog

// MARK: - Perspective Transform Calculator

class PerspectiveTransformCalculator {

    /// Calculate the four corners of a rectangular plane region in 3D world space.
    ///
    /// This method computes corner positions by applying the plane's transform matrix and a quaternion
    /// rotation that aligns the capture region with the camera's orientation. The quaternion properly
    /// handles all three rotation axes (yaw, pitch, roll).
    ///
    /// - Parameters:
    ///   - planeData: Contains the plane's dimensions (width, height), center position, transform matrix, and rotation quaternion
    ///   - rotationQuaternion: Optional quaternion override for rotation. If nil, uses planeData.rotationQuaternion.
    /// - Returns: Array of 4 corner positions in world space, ordered as [topLeft, topRight, bottomRight, bottomLeft]
    ///            where "top" and "bottom" refer to the plane's local Z-axis direction
    static func calculatePlaneCorners(planeData: PlaneData, rotationQuaternion: simd_quatf? = nil) -> [SIMD3<Float>] {
        let captureCenter = planeData.position
        let transform = planeData.transform
        let halfWidth = planeData.width / 2.0
        let halfHeight = planeData.height / 2.0

        // Use provided quaternion or fall back to planeData's quaternion
        let rotation = rotationQuaternion ?? planeData.rotationQuaternion

        // Extract plane's local axes from transform matrix
        let xAxis = normalize(SIMD3<Float>(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z))
        let zAxis = normalize(SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))

        // Apply quaternion rotation to plane's X and Z axes
        let rotatedXAxis = rotation.act(xAxis)
        let rotatedZAxis = rotation.act(zAxis)

        // Calculate corners relative to capture center (which is in world space)
        let worldCorners: [SIMD3<Float>] = [
            captureCenter - rotatedXAxis * halfWidth - rotatedZAxis * halfHeight,  // Top-left
            captureCenter + rotatedXAxis * halfWidth - rotatedZAxis * halfHeight,  // Top-right
            captureCenter + rotatedXAxis * halfWidth + rotatedZAxis * halfHeight,  // Bottom-right
            captureCenter - rotatedXAxis * halfWidth + rotatedZAxis * halfHeight   // Bottom-left
        ]

        return worldCorners
    }

    /// Project 3D world-space corner positions to 2D pixel coordinates in the camera image.
    ///
    /// Uses ARKit's camera projection to convert 3D points to screen coordinates. The resulting
    /// pixel coordinates can be used for drawing overlays or defining perspective transformation regions.
    ///
    /// - Parameters:
    ///   - corners3D: Array of 3D positions in world space (typically from calculatePlaneCorners)
    ///   - camera: ARCamera providing the projection matrix and camera parameters
    ///   - imageResolution: Size of the camera image in pixels (width × height)
    /// - Returns: Array of CGPoint values representing pixel coordinates in the camera image,
    ///            maintaining the same order as the input corners3D array
    static func projectCornersToImage(
        corners3D: [SIMD3<Float>],
        camera: ARCamera,
        imageResolution: CGSize
    ) -> [CGPoint] {
        let projected = corners3D.enumerated().map { (index, corner) -> CGPoint in
            let projected = camera.projectPoint(
                corner,
                orientation: .landscapeRight,  // TODO: Double-check for correct orientation.
                viewportSize: imageResolution
            )
            return CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        }

        return projected
    }

    /// Calculate the output image dimensions for the transformed perspective-corrected image.
    ///
    /// Maintains the plane's aspect ratio while constraining to a maximum width to prevent
    /// excessive memory usage. Since the plane is square, the output will also be square.
    ///
    /// - Parameters:
    ///   - planeData: Contains the plane dimensions (width and height in meters)
    ///   - maxWidth: Maximum width in pixels for the output image. Defaults to 2048px.
    /// - Returns: CGSize representing the output image dimensions (width × height in pixels)
    static func calculateOutputSize(
        planeData: PlaneData,
        maxWidth: CGFloat = 2048
    ) -> CGSize {
        let aspectRatio = CGFloat(planeData.width / planeData.height)
        let outputWidth = maxWidth
        let outputHeight = outputWidth / aspectRatio
        return CGSize(width: outputWidth, height: outputHeight)
    }

    /// Verify that all corner points fall within the camera image boundaries.
    ///
    /// Checks each corner to ensure it's within the image bounds with an optional safety margin.
    /// This is critical for ensuring the perspective transformation has valid source coordinates.
    /// The margin creates an inset from the edges to prevent corners from being too close to the edge.
    ///
    /// - Parameters:
    ///   - corners: Array of corner positions in pixel coordinates
    ///   - imageSize: Dimensions of the camera image in pixels
    ///   - margin: Inset distance in pixels from each edge. Defaults to 10px.
    ///                Corners must be at least this many pixels inside the image bounds.
    /// - Returns: true if all corners are within bounds (including margin), false otherwise
    static func areAllCornersVisible(
        corners: [CGPoint],
        imageSize: CGSize,
        margin: CGFloat = 10
    ) -> Bool {
        return corners.allSatisfy { corner in
            corner.x >= margin &&
            corner.x <= imageSize.width - margin &&
            corner.y >= margin &&
            corner.y <= imageSize.height - margin
        }
    }

    /// Calculate the angle between the camera's viewing direction and the horizontal plane.
    ///
    /// This angle indicates how directly the camera is looking down at the plane, which affects
    /// the quality of perspective correction. Larger angles (closer to 90°) produce better results.
    ///
    /// - Parameters:
    ///   - planeTransform: The plane's 4×4 transform matrix containing its position and orientation
    ///   - cameraTransform: The camera's 4×4 transform matrix from ARFrame
    /// - Returns: Angle in degrees from the horizontal plane.
    ///            0° = camera parallel to plane (edge-on view)
    ///            90° = camera looking straight down (perfect top-down view)
    static func calculateCameraAngle(
        planeTransform: simd_float4x4,
        cameraTransform: simd_float4x4
    ) -> Float {
        // Extract plane normal (Y-axis in plane's local space, pointing up from surface)
        let planeNormal = normalize(SIMD3<Float>(
            planeTransform.columns.1.x,
            planeTransform.columns.1.y,
            planeTransform.columns.1.z
        ))

        // Extract camera viewing direction (negative Z-axis in camera space)
        let cameraDirection = normalize(SIMD3<Float>(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        ))

        // Calculate angle between camera direction and plane normal
        // When looking straight down at plane: dot = -1 (opposite directions)
        // When parallel to plane: dot = 0 (perpendicular)
        let dotProduct = dot(planeNormal, cameraDirection)
        let clampedDot = max(-1.0, min(1.0, dotProduct))
        let angleFromNormalRadians = acos(clampedDot)

        // Convert to angle from horizontal plane
        // angleFromNormal = 180° → camera looking down → return 90° (top-down)
        // angleFromNormal = 90° → camera parallel to plane → return 0°
        let angleFromHorizontalRadians = angleFromNormalRadians - (.pi / 2.0)
        let angleDegrees = abs(angleFromHorizontalRadians * 180.0 / .pi)

        return angleDegrees
    }

    /// Estimate the spatial resolution of the transformed output image.
    ///
    /// Calculates how many pixels represent one meter of real-world distance in the
    /// perspective-corrected image. Higher values indicate better detail capture.
    ///
    /// - Parameters:
    ///   - planeData: Contains the physical dimensions of the plane in meters
    ///   - outputSize: The dimensions of the output image in pixels
    /// - Returns: Average pixels per meter across both width and height dimensions
    static func estimatePixelsPerMeter(
        planeData: PlaneData,
        outputSize: CGSize
    ) -> Float {
        // Average pixels per meter in both dimensions
        let pixelsPerMeterWidth = Float(outputSize.width) / planeData.width
        let pixelsPerMeterHeight = Float(outputSize.height) / planeData.height
        return (pixelsPerMeterWidth + pixelsPerMeterHeight) / 2.0
    }

    /// Calculate rotation quaternion using the viewing direction from camera to raycast point.
    ///
    /// This method uses the vector from the camera position to the raycast hit point (where
    /// the screen center intersects the plane) to define the square's orientation. This vector
    /// is projected onto the plane and normalized to get a direction that defines how the
    /// square should be rotated.
    ///
    /// The method:
    /// 1. Calculates vector from camera to raycast hit point
    /// 2. Projects this vector onto the plane (removes component along plane normal)
    /// 3. Creates a quaternion that rotates plane's Z-axis to align with this viewing direction
    /// 4. This quaternion only rotates around the plane's normal (Y-axis), keeping rotation in-plane
    ///
    /// - Parameters:
    ///   - planeTransform: The plane's 4×4 transform matrix
    ///   - cameraWorldPosition: The camera's 3D position in world space
    ///   - screenCenterHitWorldPosition: The 3D position where screen center ray hits the plane
    /// - Returns: Quaternion representing in-plane rotation to align with viewing direction
    static func calculateRotationFromViewingDirection(
        planeTransform: simd_float4x4,
        cameraWorldPosition: SIMD3<Float>,
        screenCenterHitWorldPosition: SIMD3<Float>
    ) -> simd_quatf {
        // Extract plane's forward axis (Z-axis) and normal (Y-axis) from transform matrix
        let planeForwardAxisInWorldSpace = normalize(SIMD3<Float>(
            planeTransform.columns.2.x,
            planeTransform.columns.2.y,
            planeTransform.columns.2.z
        ))
        let planeNormalAxisInWorldSpace = normalize(SIMD3<Float>(
            planeTransform.columns.1.x,
            planeTransform.columns.1.y,
            planeTransform.columns.1.z
        ))

        // Calculate viewing direction: from hit point back to camera (reversed)
        // We reverse it because we want to orient the square as if looking from the plane toward the camera
        let hitPointToCameraDirection = normalize(cameraWorldPosition - screenCenterHitWorldPosition)

        // Project viewing direction onto the plane surface
        // Remove the component along the plane's normal to get in-plane component
        let hitPointToCameraDirectionAlongPlaneNormal = planeNormalAxisInWorldSpace * dot(hitPointToCameraDirection, planeNormalAxisInWorldSpace)
        let hitPointToCameraDirectionProjectedOnPlane = hitPointToCameraDirection - hitPointToCameraDirectionAlongPlaneNormal

        // Check if projection is valid
        if length(hitPointToCameraDirectionProjectedOnPlane) < 0.001 {
            // Edge case: viewing direction is perpendicular to plane, return identity
            return simd_quatf(angle: 0, axis: planeNormalAxisInWorldSpace)
        }

        let hitPointToCameraDirectionProjectedOnPlaneNormalized = normalize(hitPointToCameraDirectionProjectedOnPlane)

        // Create quaternion that rotates from plane's forward axis to projected viewing direction
        // This built-in initializer handles all edge cases (parallel, anti-parallel vectors) automatically
        return simd_quatf(from: planeForwardAxisInWorldSpace, to: hitPointToCameraDirectionProjectedOnPlaneNormalized)
    }

    /// Project the screen center point onto the plane's infinite geometric surface.
    ///
    /// Performs ray-plane intersection to find where the center of the camera viewport
    /// intersects with the plane (extended infinitely). This allows the capture region to be
    /// centered at whatever the user is looking at, even if it's beyond the detected plane bounds.
    ///
    /// - Parameters:
    ///   - planeTransform: The plane's 4×4 transform matrix defining its position and orientation
    ///   - camera: ARCamera providing projection matrix and camera parameters
    ///   - imageResolution: Size of the camera image in pixels
    /// - Returns: 3D world position where screen center ray intersects the plane, or nil if the
    ///            ray is parallel to the plane (extremely rare edge case)
    static func projectScreenCenterToPlane(
        planeTransform: simd_float4x4,
        camera: ARCamera,
        imageResolution: CGSize
    ) -> SIMD3<Float>? {
        // Screen center in normalized coordinates (0.5, 0.5)
        let screenCenter = CGPoint(x: imageResolution.width / 2, y: imageResolution.height / 2)

        // Get camera's view matrix (inverse of camera transform)
        let cameraTransform = camera.transform
        let viewMatrix = cameraTransform.inverse

        // Get projection matrix
        let projectionMatrix = camera.projectionMatrix(for: .landscapeRight,
                                                        viewportSize: imageResolution,
                                                        zNear: 0.001,
                                                        zFar: 1000)

        // Convert screen point to normalized device coordinates (-1 to 1)
        let ndcX = (2.0 * Float(screenCenter.x) / Float(imageResolution.width)) - 1.0
        let ndcY = 1.0 - (2.0 * Float(screenCenter.y) / Float(imageResolution.height))

        // Unproject to get ray direction
        let clipCoords = SIMD4<Float>(ndcX, ndcY, -1.0, 1.0)
        let invProjection = projectionMatrix.inverse
        var eyeCoords = invProjection * clipCoords
        eyeCoords = SIMD4<Float>(eyeCoords.x, eyeCoords.y, -1.0, 0.0)

        let invView = viewMatrix.inverse
        let rayWorld = invView * eyeCoords
        let rayDirection = normalize(SIMD3<Float>(rayWorld.x, rayWorld.y, rayWorld.z))

        // Camera position in world space
        let cameraPosition = SIMD3<Float>(cameraTransform.columns.3.x,
                                           cameraTransform.columns.3.y,
                                           cameraTransform.columns.3.z)

        // Extract plane normal and position from plane transform
        let planeNormal = normalize(SIMD3<Float>(planeTransform.columns.1.x,
                                                   planeTransform.columns.1.y,
                                                   planeTransform.columns.1.z))
        let planePosition = SIMD3<Float>(planeTransform.columns.3.x,
                                          planeTransform.columns.3.y,
                                          planeTransform.columns.3.z)

        // Ray-plane intersection: find t where ray intersects plane
        // Ray: P = cameraPosition + t * rayDirection
        // Plane: dot(P - planePosition, planeNormal) = 0
        let denominator = dot(rayDirection, planeNormal)

        // Check if ray is parallel to plane
        if abs(denominator) < 0.0001 {
            return nil
        }

        let t = dot(planePosition - cameraPosition, planeNormal) / denominator

        // Calculate intersection point
        let intersectionPoint = cameraPosition + rayDirection * t

        return intersectionPoint
    }

    /// Calculate the largest possible square capture region centered at screen center that fits in the camera view.
    ///
    /// Uses binary search to find the maximum square size where all four corners remain visible
    /// within the camera frame (with a safety margin). The square is always centered at the screen
    /// center point and rotated to align with the camera's orientation. This ensures the capture
    /// region is as large as possible while guaranteeing a valid perspective transformation.
    ///
    /// - Parameters:
    ///   - planeTransform: The plane's 4×4 transform matrix
    ///   - captureCenter: 3D world position where the capture region should be centered (from projectScreenCenterToPlane)
    ///   - rotationQuaternion: Quaternion to align the square with camera orientation
    ///   - camera: ARCamera for projecting corners to check visibility
    ///   - imageResolution: Camera image dimensions in pixels
    ///   - minDimension: Minimum square size in meters. Defaults to 0.4m (ARKit's plane detection minimum)
    ///   - maxDimension: Maximum square size in meters to attempt. Defaults to 5.0m
    /// - Returns: PlaneData containing the optimal square dimensions, center position, transform, and rotation quaternion.
    ///            The width and height will be equal (square), and rotationQuaternion will be stored for later use.
    static func calculateVisibleSquareRegion(
        planeTransform: simd_float4x4,
        captureCenter: SIMD3<Float>,
        rotationQuaternion: simd_quatf,
        camera: ARCamera,
        imageResolution: CGSize,
        minDimension: Float = 0.4,
        maxDimension: Float = 5.0
    ) -> PlaneData {
        // Binary search to find maximum SQUARE size where all corners are visible
        var minSize = minDimension
        var maxSize = maxDimension
        var bestSize = minDimension

        let maxIterations = 20
        var iteration = 0

        while iteration < maxIterations && (maxSize - minSize) > 0.01 {
            let testSize = (minSize + maxSize) / 2.0

            let testPlaneData = PlaneData(
                width: testSize,
                height: testSize,  // Square: width == height
                position: captureCenter,
                transform: planeTransform,
                rotationQuaternion: rotationQuaternion
            )

            let corners3D = calculatePlaneCorners(planeData: testPlaneData, rotationQuaternion: rotationQuaternion)
            let corners2D = projectCornersToImage(
                corners3D: corners3D,
                camera: camera,
                imageResolution: imageResolution
            )

            if areAllCornersVisible(corners: corners2D, imageSize: imageResolution, margin: 50) {
                // All corners visible, try larger size
                bestSize = testSize
                minSize = testSize
            } else {
                // Corners not visible, try smaller size
                maxSize = testSize
            }

            iteration += 1
        }

        AppLogger.transformCalculator.debug("Visible square region calculation:")
        AppLogger.transformCalculator.debug("  Capture center: (\(captureCenter.x, format: .fixed(precision: 3)), \(captureCenter.y, format: .fixed(precision: 3)), \(captureCenter.z, format: .fixed(precision: 3)))")
        AppLogger.transformCalculator.debug("  Square size: \(bestSize, format: .fixed(precision: 2))m × \(bestSize, format: .fixed(precision: 2))m")
        AppLogger.transformCalculator.debug("  Rotation quaternion: \(String(describing: rotationQuaternion))")
        AppLogger.transformCalculator.debug("  Iterations: \(iteration)")

        return PlaneData(
            width: bestSize,
            height: bestSize,
            position: captureCenter,
            transform: planeTransform,
            rotationQuaternion: rotationQuaternion
        )
    }

    /// Create a complete perspective transformation with quality validation.
    ///
    /// Orchestrates the full transformation pipeline: calculates corners with rotation, projects them
    /// to the camera image, computes output dimensions, evaluates quality metrics, and packages
    /// everything into a PerspectiveTransform structure. This is the main entry point for creating
    /// transformations during image capture.
    ///
    /// - Parameters:
    ///   - planeData: Contains plane dimensions, position, transform, and rotation quaternion
    ///   - camera: ARCamera from the current frame for projection
    ///   - cameraTransform: Camera's 4×4 transform matrix for angle calculation
    ///   - imageResolution: Camera image size in pixels
    ///   - outputMaxWidth: Maximum output image width in pixels. Defaults to 2048px
    /// - Returns: PerspectiveTransform containing source corners, output dimensions, quality metrics,
    ///            and timestamp, or nil if transformation creation fails
    static func createTransform(
        planeData: PlaneData,
        camera: ARCamera,
        cameraTransform: simd_float4x4,
        imageResolution: CGSize,
        outputMaxWidth: CGFloat = 2048
    ) -> PerspectiveTransform? {
        // Calculate 3D corners with rotation applied (uses planeData.rotationQuaternion by default)
        let corners3D = calculatePlaneCorners(planeData: planeData)

        // Project to 2D image coordinates
        let corners2D = projectCornersToImage(
            corners3D: corners3D,
            camera: camera,
            imageResolution: imageResolution
        )

        // Calculate output dimensions
        let outputSize = calculateOutputSize(
            planeData: planeData,
            maxWidth: outputMaxWidth
        )

        // Calculate quality metrics
        let cameraAngle = calculateCameraAngle(
            planeTransform: planeData.transform,
            cameraTransform: cameraTransform
        )

        let allVisible = areAllCornersVisible(
            corners: corners2D,
            imageSize: imageResolution
        )

        let pixelsPerMeter = estimatePixelsPerMeter(
            planeData: planeData,
            outputSize: outputSize
        )

        let quality = TransformQuality(
            cameraAngleDegrees: cameraAngle,
            allCornersVisible: allVisible,
            estimatedPixelsPerMeter: pixelsPerMeter
        )

        // Create transformation
        let transform = PerspectiveTransform(
            sourceCorners: corners2D,
            destinationSize: outputSize,
            timestamp: Date().timeIntervalSince1970,
            quality: quality
        )
        AppLogger.transformCalculator.debug("  Transform size: \(planeData.width, format: .fixed(precision: 2))m × \(planeData.height, format: .fixed(precision: 2))m")
        return transform
    }
}

// MARK: - Image Transform Processor

class ImageTransformProcessor {

    // Shared Core Image context for better performance
    private static let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [
                .cacheIntermediates: false,
                .highQualityDownsample: true
            ])
        } else {
            return CIContext(options: [:])
        }
    }()

    /// Apply perspective correction to transform an oblique camera view into an orthogonal top-down view.
    ///
    /// Uses Core Image's CIPerspectiveCorrection filter to warp the camera image based on the
    /// provided corner coordinates. This transforms the trapezoid-shaped capture region (as seen
    /// from the oblique camera angle) into a rectangular output image showing a true top-down view.
    /// The transformation is GPU-accelerated using Metal for optimal performance.
    ///
    /// - Parameters:
    ///   - image: The raw camera image (oblique view) to be corrected
    ///   - transform: PerspectiveTransform containing source corner positions and output dimensions
    /// - Returns: Perspective-corrected UIImage showing orthogonal top-down view, or nil if the
    ///            transformation fails (e.g., invalid corners or Core Image errors)
    static func applyPerspectiveCorrection(
        image: UIImage,
        transform: PerspectiveTransform
    ) -> UIImage? {
        guard let ciImage = CIImage(image: image) else {
            AppLogger.imageProcessor.error("Failed to create CIImage from UIImage")
            return nil
        }

        AppLogger.imageProcessor.debug("Applying CIPerspectiveCorrection Filter")
        AppLogger.imageProcessor.debug("Input image extent: \(String(describing: ciImage.extent))")
        AppLogger.imageProcessor.debug("Input image size: \(String(describing: ciImage.extent.size))")

        // Create perspective correction filter
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            AppLogger.imageProcessor.error("Failed to create CIPerspectiveCorrection filter")
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)

        // Core Image uses bottom-left origin, UIKit uses top-left origin
        // Need to flip Y coordinates
        let imageHeight = ciImage.extent.height
        let corners = transform.sourceCorners

        AppLogger.imageProcessor.debug("Source corners (UIKit top-left origin):")
        AppLogger.imageProcessor.debug("  [0] topLeft: \(String(describing: corners[0]))")
        AppLogger.imageProcessor.debug("  [1] topRight: \(String(describing: corners[1]))")
        AppLogger.imageProcessor.debug("  [2] bottomRight: \(String(describing: corners[2]))")
        AppLogger.imageProcessor.debug("  [3] bottomLeft: \(String(describing: corners[3]))")

        // Convert to Core Image coordinate system (bottom-left origin)
        let ciBottomLeft = CIVector(x: corners[3].x, y: imageHeight - corners[3].y)
        let ciBottomRight = CIVector(x: corners[2].x, y: imageHeight - corners[2].y)
        let ciTopLeft = CIVector(x: corners[0].x, y: imageHeight - corners[0].y)
        let ciTopRight = CIVector(x: corners[1].x, y: imageHeight - corners[1].y)

        AppLogger.imageProcessor.debug("Converted corners (Core Image bottom-left origin):")
        AppLogger.imageProcessor.debug("  inputTopLeft: \(ciTopLeft)")
        AppLogger.imageProcessor.debug("  inputTopRight: \(ciTopRight)")
        AppLogger.imageProcessor.debug("  inputBottomRight: \(ciBottomRight)")
        AppLogger.imageProcessor.debug("  inputBottomLeft: \(ciBottomLeft)")

        // Corner order: [topLeft, topRight, bottomRight, bottomLeft]
        filter.setValue(ciBottomLeft, forKey: "inputBottomLeft")
        filter.setValue(ciBottomRight, forKey: "inputBottomRight")
        filter.setValue(ciTopLeft, forKey: "inputTopLeft")
        filter.setValue(ciTopRight, forKey: "inputTopRight")

        // Get output image
        guard let outputImage = filter.outputImage else {
            AppLogger.imageProcessor.error("Filter produced no output image")
            return nil
        }

        AppLogger.imageProcessor.debug("Output image extent: \(String(describing: outputImage.extent))")

        // Render to CGImage
        guard let cgImage = ciContext.createCGImage(
            outputImage,
            from: outputImage.extent
        ) else {
            AppLogger.imageProcessor.error("Failed to create CGImage from filtered output")
            return nil
        }

        // Convert to UIImage with correct orientation
        // The input was rotated .right, so output should maintain that orientation
        let resultImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)

        AppLogger.imageProcessor.info("Perspective correction applied successfully")
        AppLogger.imageProcessor.info("  Final output size: \(resultImage.size.width, format: .fixed(precision: 0)) × \(resultImage.size.height, format: .fixed(precision: 0))")
        AppLogger.imageProcessor.info("  Orientation: .right (rotated to match input)")
        AppLogger.imageProcessor.info("  Quality: \(transform.quality.qualityDescription)")

        return resultImage
    }
}
