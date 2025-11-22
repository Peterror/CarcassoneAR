//
//  SIMDExtensions.swift
//  CarcassoneAR
//
//  Utility extensions for SIMD types
//

import simd

/// Extension to extract xyz components from simd_float4
extension simd_float4 {
    /// Convenience property to extract the first three components (x, y, z) as a SIMD3<Float>
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}

/// Extension to convert quaternion to Euler angles
extension simd_quatf {
    /// Convert quaternion to Euler angles (in degrees) using ARKit's rotation order.
    ///
    /// ARKit applies rotations in the order: Roll (X) → Pitch (Y) → Yaw (Z).
    /// This function extracts Euler angles from a quaternion using the XYZ convention
    /// to match ARKit's coordinate system and rotation order.
    ///
    /// - Returns: SIMD3<Float> containing (roll, pitch, yaw) in degrees
    func toEulerAngles() -> SIMD3<Float> {
        // Extract quaternion components
        let w = self.vector.w
        let x = self.vector.x
        let y = self.vector.y
        let z = self.vector.z

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
}
