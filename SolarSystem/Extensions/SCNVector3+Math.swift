// SCNVector3+Math.swift
// SolarSystem
//
// SceneKit node extensions for extracting world-space basis vectors, plus
// a cross-platform SCNVector3 constructor. `SCNVector3` component type is
// `Float` on iOS but `CGFloat` on macOS, so arithmetic mixing Doubles
// (from the orbital maths) with `.x`/`.y`/`.z` breaks one platform or the
// other. The `SCNVector3.init(doubles:)` helper below hides that gap.

import SceneKit
import simd

// MARK: - SCNNode World-Space Basis Vectors

extension SCNNode {
    /// The right direction in world space (x-axis of the node's transform).
    var worldRight: SCNVector3 {
        let m = worldTransform
        return SCNVector3(m.m11, m.m12, m.m13)
    }

    /// The up direction in world space (y-axis of the node's transform).
    var worldUp: SCNVector3 {
        let m = worldTransform
        return SCNVector3(m.m21, m.m22, m.m23)
    }
}

// MARK: - Cross-platform construction from Doubles

extension SCNVector3 {
    /// Build an `SCNVector3` from three `Double` components, widening or
    /// narrowing as needed per platform. The orbital-mechanics layer works
    /// entirely in `Double` precision; this keeps the handful of places that
    /// bridge to scene coordinates free of `#if`.
    init(_ x: Double, _ y: Double, _ z: Double) {
        #if os(macOS)
        self.init(CGFloat(x), CGFloat(y), CGFloat(z))
        #else
        self.init(Float(x), Float(y), Float(z))
        #endif
    }

    /// Add a `Double`-space offset to an existing scene vector. Used by
    /// mission-marker runtime maths to avoid `SCNFloat + Float` / `+ CGFloat`
    /// mismatches between iOS and macOS.
    func adding(_ x: Double, _ y: Double, _ z: Double) -> SCNVector3 {
        #if os(macOS)
        return SCNVector3(CGFloat(self.x) + CGFloat(x),
                           CGFloat(self.y) + CGFloat(y),
                           CGFloat(self.z) + CGFloat(z))
        #else
        return SCNVector3(Float(self.x) + Float(x),
                           Float(self.y) + Float(y),
                           Float(self.z) + Float(z))
        #endif
    }
}
