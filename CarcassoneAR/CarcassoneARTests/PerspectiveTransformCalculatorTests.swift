//
//  PerspectiveTransformCalculatorTests.swift
//  CarcassoneARTests
//
//  Unit tests for the geometry helpers in PerspectiveTransformCalculator that do
//  not depend on a live ARCamera/ARSession (i.e. the pure, deterministic math).
//

import Testing
import simd
import CoreGraphics
@testable import CarcassoneAR

@Suite("PerspectiveTransformCalculator")
struct PerspectiveTransformCalculatorTests {

    // MARK: - calculatePlaneCorners

    @Test("Corners of an identity-aligned square are centered on the position")
    func planeCornersForIdentityTransform() {
        let plane = PlaneData(
            width: 2,
            height: 2,
            position: SIMD3<Float>(0, 0, 0),
            transform: matrix_identity_float4x4
        )

        let corners = PerspectiveTransformCalculator.calculatePlaneCorners(planeData: plane)

        #expect(corners.count == 4)
        #expect(approx(corners[0], SIMD3<Float>(-1, 0, -1)))  // top-left
        #expect(approx(corners[1], SIMD3<Float>( 1, 0, -1)))  // top-right
        #expect(approx(corners[2], SIMD3<Float>( 1, 0,  1)))  // bottom-right
        #expect(approx(corners[3], SIMD3<Float>(-1, 0,  1)))  // bottom-left
    }

    @Test("Corners are offset by the plane's world position")
    func planeCornersRespectPosition() {
        let plane = PlaneData(
            width: 2,
            height: 2,
            position: SIMD3<Float>(10, 5, -3),
            transform: matrix_identity_float4x4
        )

        let corners = PerspectiveTransformCalculator.calculatePlaneCorners(planeData: plane)

        #expect(approx(corners[0], SIMD3<Float>(9, 5, -4)))
        #expect(approx(corners[2], SIMD3<Float>(11, 5, -2)))
    }

    @Test("A 90° rotation about the normal swaps the X/Z extents")
    func planeCornersWithRotation() {
        let plane = PlaneData(
            width: 2,
            height: 2,
            position: .zero,
            transform: matrix_identity_float4x4
        )
        // Rotate the square 90° about the plane normal (Y axis).
        let rotation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))

        let corners = PerspectiveTransformCalculator.calculatePlaneCorners(
            planeData: plane,
            rotationQuaternion: rotation
        )

        // Still a unit-half square centered at origin, just reoriented.
        for corner in corners {
            #expect(approx(abs(corner.x), 1))
            #expect(approx(corner.y, 0))
            #expect(approx(abs(corner.z), 1))
        }
    }

    // MARK: - calculateOutputSize

    @Test("Square region yields a square output sized to the longest edge")
    func outputSizeForSquareRegion() {
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100)
        ]
        let plane = PlaneData(width: 1, height: 1, position: .zero, transform: matrix_identity_float4x4)

        let size = PerspectiveTransformCalculator.calculateOutputSize(corners: corners, planeData: plane)

        #expect(approx(size.width, 100))
        #expect(approx(size.height, 100))
    }

    @Test("Output width is clamped to maxWidth")
    func outputSizeClampsToMaxWidth() {
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1000, y: 0),
            CGPoint(x: 1000, y: 1000),
            CGPoint(x: 0, y: 1000)
        ]
        let plane = PlaneData(width: 1, height: 1, position: .zero, transform: matrix_identity_float4x4)

        let size = PerspectiveTransformCalculator.calculateOutputSize(corners: corners, planeData: plane, maxWidth: 256)

        #expect(approx(size.width, 256))
        #expect(approx(size.height, 256))
    }

    @Test("Non-square aspect ratio is preserved")
    func outputSizeRespectsAspectRatio() {
        // Top/bottom edges 200px wide; plane is twice as wide as tall.
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 200, y: 0),
            CGPoint(x: 200, y: 100),
            CGPoint(x: 0, y: 100)
        ]
        let plane = PlaneData(width: 2, height: 1, position: .zero, transform: matrix_identity_float4x4)

        let size = PerspectiveTransformCalculator.calculateOutputSize(corners: corners, planeData: plane)

        #expect(approx(size.width, 200))
        #expect(approx(size.height, 100))
    }

    @Test("Longer of the top/bottom edges drives the width")
    func outputSizeUsesLongestEdge() {
        // Bottom edge (300px) longer than top edge (100px).
        let corners = [
            CGPoint(x: 100, y: 0),
            CGPoint(x: 200, y: 0),
            CGPoint(x: 300, y: 100),
            CGPoint(x: 0, y: 100)
        ]
        let plane = PlaneData(width: 1, height: 1, position: .zero, transform: matrix_identity_float4x4)

        let size = PerspectiveTransformCalculator.calculateOutputSize(corners: corners, planeData: plane)

        #expect(approx(size.width, 300))
    }

    // MARK: - areAllCornersVisible

    @Test("All corners inside the frame (with margin) are visible")
    func cornersVisibleWhenInside() {
        let corners = [
            CGPoint(x: 50, y: 50),
            CGPoint(x: 950, y: 50),
            CGPoint(x: 950, y: 950),
            CGPoint(x: 50, y: 950)
        ]
        let visible = PerspectiveTransformCalculator.areAllCornersVisible(
            corners: corners,
            imageSize: CGSize(width: 1000, height: 1000)
        )
        #expect(visible)
    }

    @Test("A corner outside the margin fails visibility")
    func cornersNotVisibleWhenOutside() {
        let corners = [
            CGPoint(x: 5, y: 5),  // within 10px margin → not visible
            CGPoint(x: 950, y: 50),
            CGPoint(x: 950, y: 950),
            CGPoint(x: 50, y: 950)
        ]
        let visible = PerspectiveTransformCalculator.areAllCornersVisible(
            corners: corners,
            imageSize: CGSize(width: 1000, height: 1000)
        )
        #expect(!visible)
    }

    @Test("A corner exactly on the margin counts as visible")
    func cornersVisibleOnMarginBoundary() {
        let corners = [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 990, y: 10),
            CGPoint(x: 990, y: 990),
            CGPoint(x: 10, y: 990)
        ]
        let visible = PerspectiveTransformCalculator.areAllCornersVisible(
            corners: corners,
            imageSize: CGSize(width: 1000, height: 1000),
            margin: 10
        )
        #expect(visible)
    }

    // MARK: - calculateCameraAngle

    @Test("Looking straight down returns 90°")
    func cameraAngleStraightDown() {
        var camera = matrix_identity_float4x4
        // A downward-looking camera has +Z (column 2) pointing up, parallel to the plane normal.
        camera.columns.2 = SIMD4<Float>(0, 1, 0, 0)

        let angle = PerspectiveTransformCalculator.calculateCameraAngle(
            planeTransform: matrix_identity_float4x4,
            cameraTransform: camera
        )
        #expect(approx(angle, 90, tol: 1e-2))
    }

    @Test("Looking parallel to the plane returns 0°")
    func cameraAngleEdgeOn() {
        var camera = matrix_identity_float4x4
        camera.columns.2 = SIMD4<Float>(1, 0, 0, 0)

        let angle = PerspectiveTransformCalculator.calculateCameraAngle(
            planeTransform: matrix_identity_float4x4,
            cameraTransform: camera
        )
        #expect(approx(angle, 0, tol: 1e-2))
    }

    @Test("A 45° tilt returns 45°")
    func cameraAngleFortyFive() {
        var camera = matrix_identity_float4x4
        camera.columns.2 = SIMD4<Float>(0, 1, 1, 0)  // normalized internally

        let angle = PerspectiveTransformCalculator.calculateCameraAngle(
            planeTransform: matrix_identity_float4x4,
            cameraTransform: camera
        )
        #expect(approx(angle, 45, tol: 1e-2))
    }

    // MARK: - estimatePixelsPerMeter

    @Test("Pixels-per-meter derives from projected pixel area vs real area")
    func pixelsPerMeterFromArea() {
        // 100x100 px (10,000 px²) over a 0.5m x 0.5m (0.25 m²) plane.
        // pixels/m² = 40,000 → linear ppm = 200.
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100)
        ]
        let plane = PlaneData(width: 0.5, height: 0.5, position: .zero, transform: matrix_identity_float4x4)

        let ppm = PerspectiveTransformCalculator.estimatePixelsPerMeter(corners2D: corners, planeData: plane)
        #expect(approx(ppm, 200, tol: 1e-2))
    }

    @Test("Pixels-per-meter is independent of winding order")
    func pixelsPerMeterHandlesReversedWinding() {
        let plane = PlaneData(width: 0.5, height: 0.5, position: .zero, transform: matrix_identity_float4x4)
        let clockwise = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 100),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 100, y: 0)
        ]
        let ppm = PerspectiveTransformCalculator.estimatePixelsPerMeter(corners2D: clockwise, planeData: plane)
        #expect(approx(ppm, 200, tol: 1e-2))
    }

    // MARK: - calculateRotationFromViewingDirection

    @Test("Camera directly overhead yields ~identity rotation")
    func rotationOverheadIsIdentity() {
        let rotation = PerspectiveTransformCalculator.calculateRotationFromViewingDirection(
            planeTransform: matrix_identity_float4x4,
            cameraWorldPosition: SIMD3<Float>(0, 1, 0),
            screenCenterHitWorldPosition: SIMD3<Float>(0, 0, 0)
        )
        // The viewing direction projects to zero on the plane → identity fallback.
        let rotatedForward = rotation.act(SIMD3<Float>(0, 0, 1))
        #expect(approx(rotatedForward, SIMD3<Float>(0, 0, 1)))
    }

    @Test("In-plane viewing direction rotates the forward axis to match it")
    func rotationAlignsForwardWithViewingDirection() {
        // Camera offset along +X and +Y; projected viewing direction on the plane is +X.
        let rotation = PerspectiveTransformCalculator.calculateRotationFromViewingDirection(
            planeTransform: matrix_identity_float4x4,
            cameraWorldPosition: SIMD3<Float>(1, 1, 0),
            screenCenterHitWorldPosition: SIMD3<Float>(0, 0, 0)
        )
        // Plane forward (+Z) should be rotated onto the projected viewing direction (+X).
        let rotatedForward = rotation.act(SIMD3<Float>(0, 0, 1))
        #expect(approx(rotatedForward, SIMD3<Float>(1, 0, 0), tol: 1e-3))
    }
}
