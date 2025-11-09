//
//  PlaneData.swift
//  CarcassoneAR
//
//  Data model for detected AR plane information
//

import Foundation
import simd

/// Represents the geometry and orientation of a capture region on a detected AR plane.
///
/// This structure stores all the spatial information needed to define where and how large
/// the capture region is, as well as its rotation to align with the camera's orientation.
/// It's used throughout the app to calculate corner positions, project to camera coordinates,
/// and perform perspective transformations.
struct PlaneData {
    /// Width of the capture region in meters (physical world distance)
    var width: Float

    /// Height of the capture region in meters (physical world distance)
    /// For square regions, this equals width
    var height: Float

    /// Center position of the capture region in 3D world space coordinates.
    /// This is typically the screen-center projection onto the plane, not the plane's origin.
    var position: SIMD3<Float>

    /// The plane's 4×4 transformation matrix defining its position and orientation in world space.
    /// Contains rotation (columns 0-2) and translation (column 3).
    /// Column 1 (Y-axis) is the plane's normal vector pointing up from the surface.
    var transform: simd_float4x4

    /// Rotation angle in radians around the plane's normal (Y-axis).
    /// This aligns the capture region with the camera's forward direction, ensuring the
    /// captured image rotates with the phone rather than staying fixed to the plane's axes.
    /// Positive values rotate counter-clockwise when viewed from above the plane.
    var rotationAngle: Float = 0
}
