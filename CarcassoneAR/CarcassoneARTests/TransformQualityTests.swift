//
//  TransformQualityTests.swift
//  CarcassoneARTests
//
//  Unit tests for the TransformQuality value type's threshold logic.
//

import Testing
@testable import CarcassoneAR

@Suite("TransformQuality")
struct TransformQualityTests {

    // MARK: - isGoodQuality

    @Test("Passes when angle, visibility and resolution all clear thresholds")
    func goodQualityWhenAllThresholdsMet() {
        let q = TransformQuality(cameraAngleDegrees: 45, allCornersVisible: true, estimatedPixelsPerMeter: 800)
        #expect(q.isGoodQuality)
        #expect(q.qualityDescription == "Good quality")
    }

    @Test("Fails when any corner is outside the frame")
    func notGoodWhenCornersMissing() {
        let q = TransformQuality(cameraAngleDegrees: 45, allCornersVisible: false, estimatedPixelsPerMeter: 800)
        #expect(!q.isGoodQuality)
        #expect(q.qualityDescription == "Plane partially outside view")
    }

    @Test("Fails when camera angle is too low")
    func notGoodWhenAngleTooLow() {
        let q = TransformQuality(cameraAngleDegrees: 15, allCornersVisible: true, estimatedPixelsPerMeter: 800)
        #expect(!q.isGoodQuality)
        #expect(q.qualityDescription == "Camera angle too low - move more directly above")
    }

    @Test("Fails when resolution is too low")
    func notGoodWhenResolutionTooLow() {
        let q = TransformQuality(cameraAngleDegrees: 45, allCornersVisible: true, estimatedPixelsPerMeter: 100)
        #expect(!q.isGoodQuality)
        #expect(q.qualityDescription == "Low resolution - move closer")
    }

    // MARK: - Boundary conditions

    @Test("Angle threshold is strict (20° is not enough)")
    func angleBoundaryIsExclusive() {
        let q = TransformQuality(cameraAngleDegrees: 20, allCornersVisible: true, estimatedPixelsPerMeter: 800)
        #expect(!q.isGoodQuality)
    }

    @Test("Resolution threshold is strict (640 ppm is not enough)")
    func resolutionBoundaryIsExclusive() {
        let q = TransformQuality(cameraAngleDegrees: 45, allCornersVisible: true, estimatedPixelsPerMeter: 640)
        #expect(!q.isGoodQuality)
    }

    @Test("Missing corners take priority over a low angle in the description")
    func visibilityReportedBeforeAngle() {
        let q = TransformQuality(cameraAngleDegrees: 10, allCornersVisible: false, estimatedPixelsPerMeter: 800)
        #expect(q.qualityDescription == "Plane partially outside view")
    }
}
