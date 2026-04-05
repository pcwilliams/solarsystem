// SCNVector3+Math.swift
// SolarSystem
//
// SceneKit node extensions for extracting world-space basis vectors.
// Used by the camera controller to translate the camera in its local
// right and up directions during pan gestures.

import SceneKit

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
