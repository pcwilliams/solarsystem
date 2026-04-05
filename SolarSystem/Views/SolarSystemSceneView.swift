// SolarSystemSceneView.swift
// SolarSystem
//
// UIViewRepresentable wrapper that bridges the SceneKit SCNView into SwiftUI.
// Sets up five gesture recognizers (one-finger pan for translate, two-finger
// pan for orbit, pinch for zoom, single tap for body selection, double tap
// for reset) and manages an orbital camera controller via the Coordinator.

import SwiftUI
import SceneKit

struct SolarSystemSceneView: UIViewRepresentable {
    let scene: SCNScene
    let onBodyTapped: (CelestialBody) -> Void
    let onDoubleTap: () -> Void
    let onViewReady: (SCNView, SolarSystemSceneView.Coordinator) -> Void

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = scene
        scnView.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .multisampling4X
        scnView.isJitteringEnabled = true

        // We manage the camera ourselves via gesture recognizers
        scnView.allowsCameraControl = false

        // One-finger pan: translate the camera target in the view plane
        let panGesture = UIPanGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(panGesture)

        // Two-finger pan: orbit the camera around the target
        let orbitGesture = UIPanGestureRecognizer(target: context.coordinator,
                                                   action: #selector(Coordinator.handleOrbit(_:)))
        orbitGesture.minimumNumberOfTouches = 2
        orbitGesture.maximumNumberOfTouches = 2
        scnView.addGestureRecognizer(orbitGesture)

        // Pinch: zoom (change camera distance)
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handlePinch(_:)))
        scnView.addGestureRecognizer(pinchGesture)

        // Single tap: hit-test to select a celestial body
        let tapGesture = UITapGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)

        // Double tap: reset to overview
        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                                action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scnView.addGestureRecognizer(doubleTap)

        // Single tap waits for double tap to fail before firing
        tapGesture.require(toFail: doubleTap)

        context.coordinator.scnView = scnView
        onViewReady(scnView, context.coordinator)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onBodyTapped: onBodyTapped, onDoubleTap: onDoubleTap)
    }

    // MARK: - Coordinator (Camera Controller)

    /// Manages an orbital camera that orbits around a target point using spherical coordinates.
    /// Handles all gesture input and exposes methods for programmatic camera control.
    class Coordinator: NSObject {
        let onBodyTapped: (CelestialBody) -> Void
        let onDoubleTap: () -> Void
        weak var scnView: SCNView?

        // Camera orbital state (spherical coordinates around the target)
        private var cameraDistance: Float = 40.0
        private var orbitAngleX: Float = 0.0   // Azimuth (radians)
        private var orbitAngleY: Float = 0.4   // Elevation (radians)
        private var cameraTarget = SCNVector3Zero

        // Gesture delta tracking
        private var lastPanPoint: CGPoint = .zero
        private var lastOrbitPoint: CGPoint = .zero
        private var lastPinchScale: CGFloat = 1.0

        init(onBodyTapped: @escaping (CelestialBody) -> Void,
             onDoubleTap: @escaping () -> Void) {
            self.onBodyTapped = onBodyTapped
            self.onDoubleTap = onDoubleTap
            super.init()
        }

        // MARK: - Camera Positioning

        /// Recompute the camera position from spherical coordinates and look at the target.
        func updateCamera() {
            guard let scnView = scnView,
                  let cameraNode = scnView.pointOfView else { return }

            // Clamp elevation to avoid gimbal lock at the poles
            orbitAngleY = max(-Float.pi / 2 * 0.95, min(Float.pi / 2 * 0.95, orbitAngleY))
            cameraDistance = max(0.5, min(250.0, cameraDistance))

            // Spherical to Cartesian conversion
            let x = cameraTarget.x + cameraDistance * cos(orbitAngleY) * sin(orbitAngleX)
            let y = cameraTarget.y + cameraDistance * sin(orbitAngleY)
            let z = cameraTarget.z + cameraDistance * cos(orbitAngleY) * cos(orbitAngleX)

            cameraNode.position = SCNVector3(x, y, z)
            cameraNode.look(at: cameraTarget)
        }

        /// Set camera to look at a target from a given distance.
        func setCamera(target: SCNVector3, distance: Float) {
            cameraTarget = target
            cameraDistance = distance
            updateCamera()
        }

        /// Update just the target position (for tracking a moving body).
        func updateTarget(_ target: SCNVector3) {
            cameraTarget = target
            updateCamera()
        }

        /// Current camera distance from target (used by the zoom slider).
        var currentDistance: Float { cameraDistance }

        /// Set only the camera distance (called by the zoom slider).
        func setDistance(_ distance: Float) {
            cameraDistance = max(0.5, min(250.0, distance))
            updateCamera()
        }

        /// Reset the camera to the initial overview position above the solar system.
        func resetToOverview(earthDist: Float) {
            cameraTarget = SCNVector3Zero
            cameraDistance = earthDist * 2.5
            orbitAngleX = 0
            orbitAngleY = 0.5
            updateCamera()
        }

        // MARK: - Gesture Handlers

        /// One-finger pan: translate the camera target in the camera's local right/up plane.
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = scnView,
                  let cameraNode = scnView.pointOfView else { return }

            let translation = gesture.translation(in: scnView)

            if gesture.state == .began {
                lastPanPoint = .zero
            }

            let dx = Float(translation.x - lastPanPoint.x)
            let dy = Float(translation.y - lastPanPoint.y)
            lastPanPoint = translation

            // Move target in screen-aligned directions scaled by distance
            let speed = cameraDistance * 0.002
            let right = cameraNode.worldRight
            let up = cameraNode.worldUp

            cameraTarget.x -= right.x * dx * speed - up.x * dy * speed
            cameraTarget.y -= right.y * dx * speed - up.y * dy * speed
            cameraTarget.z -= right.z * dx * speed - up.z * dy * speed

            updateCamera()
        }

        /// Two-finger pan: orbit the camera around the target (adjust azimuth and elevation).
        @objc func handleOrbit(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = scnView else { return }
            let translation = gesture.translation(in: scnView)

            if gesture.state == .began {
                lastOrbitPoint = .zero
            }

            let dx = Float(translation.x - lastOrbitPoint.x)
            let dy = Float(translation.y - lastOrbitPoint.y)
            lastOrbitPoint = translation

            orbitAngleX -= dx * 0.005
            orbitAngleY += dy * 0.005

            updateCamera()
        }

        /// Pinch: zoom by adjusting camera distance (clamped to 0.15 - 250).
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began {
                lastPinchScale = gesture.scale
            }

            let scaleDelta = Float(gesture.scale / lastPinchScale)
            lastPinchScale = gesture.scale

            cameraDistance = max(0.5, min(250.0, cameraDistance / scaleDelta))
            updateCamera()
        }

        /// Single tap: hit-test the scene and select the tapped celestial body.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView else { return }
            let location = gesture.location(in: scnView)
            let hitResults = scnView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue
            ])

            if let hit = hitResults.first {
                let nodeName = hit.node.name ?? ""

                // Check Sun first
                if nodeName == "sun" {
                    onBodyTapped(SolarSystemData.sun)
                    return
                }

                // Search planets and their moons
                let allBodies = SolarSystemData.allPlanets
                for body in allBodies {
                    if body.id == nodeName {
                        onBodyTapped(body)
                        return
                    }
                    for moon in body.moons {
                        if moon.id == nodeName {
                            onBodyTapped(moon)
                            return
                        }
                    }
                }
            }
        }

        /// Double tap: reset camera to the overview position.
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            onDoubleTap()
        }
    }
}
