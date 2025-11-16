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
