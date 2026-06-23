//
//  SIMDExtensionsTests.swift
//  CarcassoneARTests
//
//  Unit tests for the pure-math SIMD helper extensions.
//

import Testing
import simd
@testable import CarcassoneAR

@Suite("SIMD Extensions")
struct SIMDExtensionsTests {

    // MARK: - simd_float4.xyz

    @Test("xyz drops the w component")
    func xyzExtractsFirstThreeComponents() {
        let v = SIMD4<Float>(1, 2, 3, 4)
        #expect(v.xyz == SIMD3<Float>(1, 2, 3))
    }

    // MARK: - simd_quatf.toEulerAngles

    @Test("Identity quaternion has zero Euler angles")
    func identityQuaternionIsZero() {
        let euler = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)).toEulerAngles()
        #expect(approx(euler.x, 0))
        #expect(approx(euler.y, 0))
        #expect(approx(euler.z, 0))
    }

    @Test("90° about Z maps to 90° yaw")
    func yawRotationExtracted() {
        let q = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
        let euler = q.toEulerAngles()
        #expect(approx(euler.x, 0, tol: 1e-3))   // roll
        #expect(approx(euler.y, 0, tol: 1e-3))   // pitch
        #expect(approx(euler.z, 90, tol: 1e-3))  // yaw
    }

    @Test("90° about X maps to 90° roll")
    func rollRotationExtracted() {
        let q = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let euler = q.toEulerAngles()
        #expect(approx(euler.x, 90, tol: 1e-3))  // roll
        #expect(approx(euler.y, 0, tol: 1e-3))   // pitch
        #expect(approx(euler.z, 0, tol: 1e-3))   // yaw
    }

    @Test("Pitch near gimbal lock clamps to ±90°")
    func pitchGimbalLockIsClamped() {
        // 90° about Y produces sinp ≈ 1, exercising the gimbal-lock branch.
        let q = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        let euler = q.toEulerAngles()
        #expect(approx(abs(euler.y), 90, tol: 1e-2))
    }
}
