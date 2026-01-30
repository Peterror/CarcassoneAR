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
        let xAxis = normalize(transform.columns.0.xyz)
        let zAxis = normalize(transform.columns.2.xyz)

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
    /// Calculates the pixel distance of both the top edge (corner[0] to corner[1]) and bottom edge
    /// (corner[3] to corner[2]) of the quadrilateral, then uses the longer distance as the basis
    /// for output width. This ensures the output image has sufficient resolution to represent the
    /// most detailed edge of the perspective-distorted capture region.
    ///
    /// Maintains the plane's aspect ratio while constraining to a maximum width to prevent
    /// excessive memory usage. Since the plane is square, the output will also be square.
    ///
    /// - Parameters
    ///   - corners: Array of corner positions in pixel coordinates [topLeft, topRight, bottomRight, bottomLeft]
    ///   - planeData: Contains the plane dimensions (width and height in meters)
    ///   - maxWidth: Maximum width in pixels for the output image. Defaults to 2048px.
    /// - Returns: CGSize representing the output image dimensions (width × height in pixels)
    static func calculateOutputSize(
        corners: [CGPoint],
        planeData: PlaneData,
        maxWidth: CGFloat = 2048
    ) -> CGSize {
        // Calculate top width: distance from corner[0] (top-left) to corner[1] (top-right)
        let topWidth = sqrt(pow(corners[1].x - corners[0].x, 2) + pow(corners[1].y - corners[0].y, 2))

        // Calculate bottom width: distance from corner[3] (bottom-left) to corner[2] (bottom-right)
        let bottomWidth = sqrt(pow(corners[2].x - corners[3].x, 2) + pow(corners[2].y - corners[3].y, 2))

        // Use the longer edge as the basis for output width (ensures best resolution)
        let maxEdgeWidth = max(topWidth, bottomWidth)

        let aspectRatio = CGFloat(planeData.width / planeData.height)
        let outputWidth = min(maxWidth, maxEdgeWidth)
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

    /// Estimate the spatial resolution of the captured image based on projected corner area.
    ///
    /// Calculates how many pixels represent one meter of real-world distance by measuring
    /// the actual pixel area covered by the projected corners in the camera image. This
    /// provides a more accurate resolution estimate than using the output image dimensions,
    /// since it accounts for perspective distortion and camera angle.
    ///
    /// Uses the shoelace formula to calculate the area of the quadrilateral formed by
    /// the four projected corners, then derives pixels per meter from the ratio of
    /// pixel area to real-world area.
    ///
    /// - Parameters:
    ///   - corners2D: Array of projected corner positions in pixel coordinates [topLeft, topRight, bottomRight, bottomLeft]
    ///   - planeData: Contains the physical dimensions of the plane in meters (width × height)
    /// - Returns: Estimated pixels per meter (square root of pixel density)
    static func estimatePixelsPerMeter(
        corners2D: [CGPoint],
        planeData: PlaneData
    ) -> Float {
        // Calculate area of quadrilateral using shoelace formula
        // Area = 0.5 * |sum of (x[i] * y[i+1] - x[i+1] * y[i])|
        var area: CGFloat = 0.0
        let n = corners2D.count

        for i in 0..<n {
            let j = (i + 1) % n
            area += corners2D[i].x * corners2D[j].y
            area -= corners2D[j].x * corners2D[i].y
        }
        area = abs(area) / 2.0

        // Calculate real-world area in square meters
        let realWorldArea = planeData.width * planeData.height

        // Pixels per square meter
        let pixelsPerSquareMeter = Float(area) / realWorldArea

        // Return square root to get linear pixels per meter
        return sqrt(pixelsPerSquareMeter)
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
        AppLogger.transformCalculator.debug("  Rotation quaternion: \(String(describing: rotationQuaternion.toEulerAngles()))")
        AppLogger.transformCalculator.debug("  Iterations: \(iteration)")

        return PlaneData(
            width: bestSize,
            height: bestSize,
            position: captureCenter,
            transform: planeTransform,
            rotationQuaternion: rotationQuaternion
        )
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
    /// **Coordinate System Strategy:**
    /// - Input image comes with `.right` orientation (portrait mode, rotated 90° CW from landscape)
    /// - Input corners are already rotated to match the portrait-oriented image coordinate system
    /// - We work directly with the portrait image's pixel buffer (ignoring UIImage orientation metadata)
    /// - Core Image uses bottom-left origin, so we flip Y coordinates
    /// - Output is created with `.up` (no rotation) since the pixel buffer is already correctly oriented
    ///
    /// - Parameters:
    ///   - image: The raw camera image (oblique view) to be corrected, with `.right` orientation
    ///   - perspectiveTransform: PerspectiveTransform containing source corner positions (in portrait coordinates) and output dimensions
    /// - Returns: Perspective-corrected UIImage showing orthogonal top-down view, or nil if the
    ///            transformation fails (e.g., invalid corners or Core Image errors)
    static func applyPerspectiveCorrection(
        image: UIImage,
        perspectiveTransform: PerspectiveTransform
    ) -> UIImage? {
        AppLogger.imageProcessor.info("═══════════════════════════════════════════════════════")
        AppLogger.imageProcessor.info("Starting Perspective Correction")
        AppLogger.imageProcessor.info("═══════════════════════════════════════════════════════")

        // Log input image details
        AppLogger.imageProcessor.debug("Input UIImage Details:")
        AppLogger.imageProcessor.debug("  UIImage.size: \(image.size.width, format: .fixed(precision: 0)) × \(image.size.height, format: .fixed(precision: 0))")
        AppLogger.imageProcessor.debug("  UIImage.scale: \(image.scale, format: .fixed(precision: 1))")
        AppLogger.imageProcessor.debug("  UIImage.orientation: \(String(describing: image.imageOrientation)) (rawValue: \(image.imageOrientation.rawValue))")

        guard let cgImageSource = image.cgImage else {
            AppLogger.imageProcessor.error("Failed to extract CGImage from UIImage")
            return nil
        }

        AppLogger.imageProcessor.debug("  CGImage.width: \(cgImageSource.width)")
        AppLogger.imageProcessor.debug("  CGImage.height: \(cgImageSource.height)")

        // Create CIImage directly from CGImage to bypass orientation metadata
        // This gives us the actual pixel buffer dimensions
        let ciImage = CIImage(cgImage: cgImageSource)

        AppLogger.imageProcessor.debug("CIImage Details:")
        AppLogger.imageProcessor.debug("  CIImage.extent: \(String(describing: ciImage.extent))")
        AppLogger.imageProcessor.debug("  CIImage.extent.size: \(ciImage.extent.width, format: .fixed(precision: 0)) × \(ciImage.extent.height, format: .fixed(precision: 0))")

        // Get actual pixel buffer dimensions (this is what Core Image will work with)
        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height

        AppLogger.imageProcessor.debug("Working dimensions: \(imageWidth, format: .fixed(precision: 0)) × \(imageHeight, format: .fixed(precision: 0))")

        // Use LANDSCAPE corners (these match the actual pixel buffer dimensions)
        let corners = perspectiveTransform.landscapeCorners

        AppLogger.imageProcessor.debug("─────────────────────────────────────────────────────")
        AppLogger.imageProcessor.debug("Input Corners (Landscape coordinates, matching pixel buffer):")
        AppLogger.imageProcessor.debug("  [0] Top-Left:     (\(corners[0].x, format: .fixed(precision: 1)), \(corners[0].y, format: .fixed(precision: 1)))")
        AppLogger.imageProcessor.debug("  [1] Top-Right:    (\(corners[1].x, format: .fixed(precision: 1)), \(corners[1].y, format: .fixed(precision: 1)))")
        AppLogger.imageProcessor.debug("  [2] Bottom-Right: (\(corners[2].x, format: .fixed(precision: 1)), \(corners[2].y, format: .fixed(precision: 1)))")
        AppLogger.imageProcessor.debug("  [3] Bottom-Left:  (\(corners[3].x, format: .fixed(precision: 1)), \(corners[3].y, format: .fixed(precision: 1)))")

        // Validate corners are within bounds
        let margin: CGFloat = 0
        let allInBounds = corners.allSatisfy { corner in
            corner.x >= margin && corner.x <= imageWidth - margin &&
            corner.y >= margin && corner.y <= imageHeight - margin
        }

        if !allInBounds {
            AppLogger.imageProcessor.error("Corner coordinates are outside image bounds!")
            AppLogger.imageProcessor.error("  Image dimensions: \(imageWidth, format: .fixed(precision: 0)) × \(imageHeight, format: .fixed(precision: 0))")
            for (index, corner) in corners.enumerated() {
                let outOfBounds = corner.x < margin || corner.x > imageWidth - margin ||
                                 corner.y < margin || corner.y > imageHeight - margin
                if outOfBounds {
                    AppLogger.imageProcessor.error("  Corner[\(index)]: (\(corner.x, format: .fixed(precision: 1)), \(corner.y, format: .fixed(precision: 1))) - OUT OF BOUNDS")
                }
            }
        }

        // Create perspective correction filter
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            AppLogger.imageProcessor.error("Failed to create CIPerspectiveCorrection filter")
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)

        // Convert from UIKit coordinates (top-left origin, Y-down) to Core Image coordinates (bottom-left origin, Y-up)
        // Formula: ciY = imageHeight - uiKitY
        let ciTopLeft = CIVector(x: corners[0].x, y: imageHeight - corners[0].y)
        let ciTopRight = CIVector(x: corners[1].x, y: imageHeight - corners[1].y)
        let ciBottomRight = CIVector(x: corners[2].x, y: imageHeight - corners[2].y)
        let ciBottomLeft = CIVector(x: corners[3].x, y: imageHeight - corners[3].y)

        AppLogger.imageProcessor.debug("─────────────────────────────────────────────────────")
        AppLogger.imageProcessor.debug("Converted Corners (Core Image coordinates, bottom-left origin):")
        AppLogger.imageProcessor.debug("  inputTopLeft:     \(ciTopLeft)")
        AppLogger.imageProcessor.debug("  inputTopRight:    \(ciTopRight)")
        AppLogger.imageProcessor.debug("  inputBottomRight: \(ciBottomRight)")
        AppLogger.imageProcessor.debug("  inputBottomLeft:  \(ciBottomLeft)")

        // Set filter parameters with correct parameter names
        filter.setValue(ciTopLeft, forKey: "inputTopLeft")
        filter.setValue(ciTopRight, forKey: "inputTopRight")
        filter.setValue(ciBottomRight, forKey: "inputBottomRight")
        filter.setValue(ciBottomLeft, forKey: "inputBottomLeft")

        // Get output image
        guard var outputImage = filter.outputImage else {
            AppLogger.imageProcessor.error("Filter produced no output image")
            return nil
        }

        AppLogger.imageProcessor.debug("─────────────────────────────────────────────────────")
        AppLogger.imageProcessor.debug("Filter Output:")
        AppLogger.imageProcessor.debug("  Output extent: \(String(describing: outputImage.extent))")
        AppLogger.imageProcessor.debug("  Output size: \(outputImage.extent.width, format: .fixed(precision: 0)) × \(outputImage.extent.height, format: .fixed(precision: 0))")

        // Force output to be square by scaling
        // The physical plane is square, but CIPerspectiveCorrection determines output dimensions
        // based on the trapezoid geometry, which doesn't account for the known square shape
        let desiredSize = perspectiveTransform.destinationSize.width  // Square: width == height
        let outputWidth = outputImage.extent.width
        let outputHeight = outputImage.extent.height

        if abs(outputWidth - outputHeight) > 1 {
            AppLogger.imageProcessor.debug("─────────────────────────────────────────────────────")
            AppLogger.imageProcessor.debug("Scaling to square (physical plane is square):")
            AppLogger.imageProcessor.debug("  Filter output: \(outputWidth, format: .fixed(precision: 0)) × \(outputHeight, format: .fixed(precision: 0))")
            AppLogger.imageProcessor.debug("  Target size: \(desiredSize, format: .fixed(precision: 0)) × \(desiredSize, format: .fixed(precision: 0))")

            let scaleX = desiredSize / outputWidth
            let scaleY = desiredSize / outputHeight

            AppLogger.imageProcessor.debug("  Scale factors: X=\(scaleX, format: .fixed(precision: 3)), Y=\(scaleY, format: .fixed(precision: 3))")

            // Apply non-uniform scaling, then translate to origin (0,0)
            let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            outputImage = outputImage.transformed(by: scaleTransform)

            // Translate extent back to origin (scaling may shift it)
            let translateTransform = CGAffineTransform(translationX: -outputImage.extent.origin.x,
                                                        y: -outputImage.extent.origin.y)
            outputImage = outputImage.transformed(by: translateTransform)

            AppLogger.imageProcessor.debug("  After scaling: \(outputImage.extent.width, format: .fixed(precision: 0)) × \(outputImage.extent.height, format: .fixed(precision: 0))")
        }

        // Render to CGImage
        guard let cgImage = ciContext.createCGImage(
            outputImage,
            from: outputImage.extent
        ) else {
            AppLogger.imageProcessor.error("Failed to create CGImage from filtered output")
            return nil
        }

        AppLogger.imageProcessor.debug("CGImage created:")
        AppLogger.imageProcessor.debug("  CGImage.width: \(cgImage.width)")
        AppLogger.imageProcessor.debug("  CGImage.height: \(cgImage.height)")

        // Create UIImage with .up orientation (no rotation needed - pixels are already correctly oriented)
        let resultImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)

        AppLogger.imageProcessor.info("─────────────────────────────────────────────────────")
        AppLogger.imageProcessor.info("✓ Perspective Correction Completed Successfully")
        AppLogger.imageProcessor.info("  Final UIImage.size: \(resultImage.size.width, format: .fixed(precision: 0)) × \(resultImage.size.height, format: .fixed(precision: 0))")
        AppLogger.imageProcessor.info("  Orientation: .up (no rotation)")
        AppLogger.imageProcessor.info("  Quality: \(perspectiveTransform.quality.qualityDescription)")
        AppLogger.imageProcessor.info("  Camera angle: \(perspectiveTransform.quality.cameraAngleDegrees, format: .fixed(precision: 1))°")
        AppLogger.imageProcessor.info("  Resolution: \(perspectiveTransform.quality.estimatedPixelsPerMeter, format: .fixed(precision: 0)) pixels/meter")
        AppLogger.imageProcessor.info("═══════════════════════════════════════════════════════")

        return resultImage
    }
}
