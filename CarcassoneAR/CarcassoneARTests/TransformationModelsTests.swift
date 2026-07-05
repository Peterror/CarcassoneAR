//
//  TransformationModelsTests.swift
//  CarcassoneARTests
//
//  Unit tests for the transformation data models (PerspectiveTransform, CapturedFrame).
//

import Testing
import simd
import CoreGraphics
import UIKit
@testable import CarcassoneAR

@Suite("Transformation Models")
struct TransformationModelsTests {

    private func makeQuality() -> TransformQuality {
        TransformQuality(cameraAngleDegrees: 45, allCornersVisible: true, estimatedPixelsPerMeter: 800)
    }

    private func makeCorners(offset: CGFloat = 0) -> [CGPoint] {
        [
            CGPoint(x: 0 + offset, y: 0),
            CGPoint(x: 100 + offset, y: 0),
            CGPoint(x: 100 + offset, y: 100),
            CGPoint(x: 0 + offset, y: 100)
        ]
    }

    // MARK: - PerspectiveTransform

    @Test("Initializer stores all provided values")
    func perspectiveTransformStoresValues() {
        let landscape = makeCorners()
        let portrait = makeCorners(offset: 5)
        let transform = PerspectiveTransform(
            landscapeCorners: landscape,
            portraitCorners: portrait,
            destinationSize: CGSize(width: 100, height: 100),
            timestamp: 1234.5,
            quality: makeQuality()
        )

        #expect(transform.landscapeCorners.count == 4)
        #expect(transform.portraitCorners.count == 4)
        #expect(approx(transform.landscapeCorners[1].x, 100))
        #expect(approx(transform.portraitCorners[1].x, 105))
        #expect(approx(transform.destinationSize.width, 100))
        #expect(transform.timestamp == 1234.5)
        #expect(transform.quality.isGoodQuality)
    }

    // MARK: - CapturedFrame Equatable

    @Test("Captured frames are equal when timestamps match")
    func capturedFramesEqualByTimestamp() {
        let plane = PlaneData(width: 1, height: 1, position: .zero, transform: matrix_identity_float4x4)
        let quality = makeQuality()

        let transform = PerspectiveTransform(
            landscapeCorners: makeCorners(),
            portraitCorners: makeCorners(),
            destinationSize: CGSize(width: 100, height: 100),
            timestamp: 42,
            quality: quality
        )

        let a = CapturedFrame(image: UIImage(), transform: transform, planeData: plane, cameraTransform: matrix_identity_float4x4)
        // Different image instance, same timestamp → considered equal.
        let b = CapturedFrame(image: UIImage(), transform: transform, planeData: plane, cameraTransform: matrix_identity_float4x4)

        #expect(a == b)
    }

    @Test("Captured frames differ when timestamps differ")
    func capturedFramesDifferByTimestamp() {
        let plane = PlaneData(width: 1, height: 1, position: .zero, transform: matrix_identity_float4x4)
        let quality = makeQuality()

        let transformA = PerspectiveTransform(
            landscapeCorners: makeCorners(),
            portraitCorners: makeCorners(),
            destinationSize: CGSize(width: 100, height: 100),
            timestamp: 1,
            quality: quality
        )
        let transformB = PerspectiveTransform(
            landscapeCorners: makeCorners(),
            portraitCorners: makeCorners(),
            destinationSize: CGSize(width: 100, height: 100),
            timestamp: 2,
            quality: quality
        )

        let a = CapturedFrame(image: UIImage(), transform: transformA, planeData: plane, cameraTransform: matrix_identity_float4x4)
        let b = CapturedFrame(image: UIImage(), transform: transformB, planeData: plane, cameraTransform: matrix_identity_float4x4)

        #expect(a != b)
    }

    // MARK: - PlaneData

    @Test("PlaneData defaults to an identity rotation quaternion")
    func planeDataDefaultRotation() {
        let plane = PlaneData(width: 1, height: 1, position: .zero, transform: matrix_identity_float4x4)
        let rotatedForward = plane.rotationQuaternion.act(SIMD3<Float>(0, 0, 1))
        #expect(approx(rotatedForward, SIMD3<Float>(0, 0, 1)))
    }
}
