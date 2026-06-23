//
//  TestApproxHelpers.swift
//  CarcassoneARTests
//
//  Shared floating-point approximate-equality helpers for the test suite.
//

import simd
import CoreGraphics

/// Approximate equality for `Float` values within a tolerance.
func approx(_ a: Float, _ b: Float, tol: Float = 1e-4) -> Bool {
    abs(a - b) <= tol
}

/// Approximate equality for `CGFloat` values within a tolerance.
func approx(_ a: CGFloat, _ b: CGFloat, tol: CGFloat = 1e-4) -> Bool {
    abs(a - b) <= tol
}

/// Approximate equality for `SIMD3<Float>` vectors, component-wise.
func approx(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tol: Float = 1e-4) -> Bool {
    approx(a.x, b.x, tol: tol) && approx(a.y, b.y, tol: tol) && approx(a.z, b.z, tol: tol)
}

/// Approximate equality for `CGPoint` values, component-wise.
func approx(_ a: CGPoint, _ b: CGPoint, tol: CGFloat = 1e-4) -> Bool {
    approx(a.x, b.x, tol: tol) && approx(a.y, b.y, tol: tol)
}
