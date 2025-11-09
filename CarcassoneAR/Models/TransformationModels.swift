//
//  TransformationModels.swift
//  CarcassoneAR
//
//  Data models for perspective transformation
//

import Foundation
import CoreGraphics
import UIKit
import simd

/// Contains all data needed to perform perspective correction on a camera image.
///
/// This structure defines the mapping from the oblique camera view (trapezoid) to an
/// orthogonal top-down view (rectangle). It's created during image capture and used
/// by Core Image's CIPerspectiveCorrection filter to warp the image.
struct PerspectiveTransform {
    /// Pixel coordinates of the capture region's four corners in the camera image.
    /// These define the quadrilateral (typically trapezoid) that will be transformed
    /// into a rectangle. Ordered as: [topLeft, topRight, bottomRight, bottomLeft]
    var sourceCorners: [CGPoint]

    /// Dimensions of the output image after perspective correction is applied.
    /// The output will be rectangular with these dimensions, showing a top-down view.
    var destinationSize: CGSize

    /// Timestamp when this transformation was calculated, used for uniqueness checking.
    var timestamp: TimeInterval

    /// Quality metrics evaluating how good the transformation will be based on
    /// camera angle, corner visibility, and estimated resolution.
    var quality: TransformQuality

    /// Initialize a perspective transformation.
    ///
    /// - Parameters:
    ///   - sourceCorners: Must contain exactly 4 CGPoint values in the order [topLeft, topRight, bottomRight, bottomLeft]
    ///   - destinationSize: Output image dimensions in pixels
    ///   - timestamp: Time when transform was calculated
    ///   - quality: Quality metrics for this transformation
    init(sourceCorners: [CGPoint], destinationSize: CGSize, timestamp: TimeInterval, quality: TransformQuality) {
        assert(sourceCorners.count == 4, "Must provide exactly 4 corners")
        self.sourceCorners = sourceCorners
        self.destinationSize = destinationSize
        self.timestamp = timestamp
        self.quality = quality
    }
}

/// Evaluates the quality of a perspective transformation based on camera position and geometry.
///
/// Quality is determined by three factors: camera viewing angle, corner visibility, and
/// output resolution. These metrics help the user understand whether they'll get a good
/// transformation result and provide guidance for improving the capture.
struct TransformQuality {
    /// Camera's angle from the horizontal plane in degrees.
    /// 0° = camera parallel to plane (edge-on, very poor)
    /// 90° = camera perpendicular to plane (directly overhead, ideal)
    /// Higher angles produce better perspective correction with less distortion.
    var cameraAngleDegrees: Float

    /// Whether all four corners of the capture region are visible within the camera frame.
    /// If false, perspective correction cannot be performed accurately.
    var allCornersVisible: Bool

    /// Estimated spatial resolution in pixels per meter of the transformed output.
    /// Higher values indicate better detail preservation. Values below 50 may appear pixelated.
    var estimatedPixelsPerMeter: Float

    /// Overall quality assessment based on threshold checks.
    /// Returns true if:
    /// - Camera angle > 20° (not too oblique)
    /// - All corners are visible
    /// - Resolution > 50 pixels/meter (sufficient detail)
    var isGoodQuality: Bool {
        return cameraAngleDegrees > 20 &&   // Not too flat/oblique
               allCornersVisible &&
               estimatedPixelsPerMeter > 50  // Sufficient detail
    }

    /// Human-readable description of the quality status with actionable guidance.
    /// Identifies the primary issue preventing good quality and suggests how to fix it.
    var qualityDescription: String {
        if isGoodQuality {
            return "Good quality"
        } else if !allCornersVisible {
            return "Plane partially outside view"
        } else if cameraAngleDegrees <= 20 {
            return "Camera angle too low - move more directly above"
        } else {
            return "Low resolution - move closer"
        }
    }
}

/// Represents a captured camera frame with all associated transformation and geometry data.
///
/// This structure packages together everything needed to display the captured image and
/// potentially apply perspective correction: the raw camera image, transformation parameters,
/// plane geometry, and camera position at the moment of capture.
struct CapturedFrame: Equatable {
    /// The raw camera image captured from ARSession in portrait orientation.
    /// This is the oblique view before perspective correction is applied.
    var image: UIImage

    /// Perspective transformation defining how to map the oblique view to top-down.
    /// Contains corner positions, output dimensions, and quality metrics.
    var transform: PerspectiveTransform

    /// Geometry of the capture region on the plane at the time of capture.
    /// Includes dimensions, position, rotation angle, and plane transform.
    var planeData: PlaneData

    /// The camera's 4×4 transform matrix at the moment of capture.
    /// Used for quality validation and potential re-projection.
    var cameraTransform: simd_float4x4

    /// Equatable conformance for comparing captured frames.
    /// Compares timestamps since UIImage doesn't support direct equality comparison.
    ///
    /// - Parameters:
    ///   - lhs: Left-hand side CapturedFrame
    ///   - rhs: Right-hand side CapturedFrame
    /// - Returns: true if both frames have the same timestamp
    static func == (lhs: CapturedFrame, rhs: CapturedFrame) -> Bool {
        return lhs.transform.timestamp == rhs.transform.timestamp
    }
}
