// SolarSystemSceneView.swift
// SolarSystem
//
// SwiftUI → SceneKit bridge. On iOS it's a `UIViewRepresentable`, on macOS
// an `NSViewRepresentable` — both aliased via `PlatformViewRepresentable`
// in `Platform.swift`. The shared `Coordinator` owns the orbital camera
// state and gesture handling; the gesture recognisers themselves differ by
// platform because the input idioms do:
//
//   - **iOS**: one-finger pan → translate, two-finger pan → orbit,
//     pinch → zoom, single tap → select, double tap → reset.
//   - **macOS**: left-drag → translate, right-drag → orbit, scroll wheel
//     or trackpad two-finger scroll → zoom, magnify gesture → zoom,
//     single click → select, double click → reset. Option + left-drag
//     also orbits as an accessibility fallback for single-button mice.
//
// All camera maths (spherical coords, setCamera, lerp-tracking) lives in
// the Coordinator and is 100% platform-agnostic.

import SwiftUI
import SceneKit

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct SolarSystemSceneView: PlatformViewRepresentable {
    let scene: SCNScene
    let onBodyTapped: (CelestialBody) -> Void
    let onDoubleTap: () -> Void
    let onViewReady: (SCNView, Coordinator) -> Void

    // MARK: - Representable entry points

    #if canImport(UIKit)
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        configureSharedSceneView(scnView, context: context)
        installIOSGestures(on: scnView, context: context)
        onViewReady(scnView, context.coordinator)
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
    #else
    func makeNSView(context: Context) -> SCNView {
        // Use a subclass that routes NSEvent scroll-wheel deltas to the
        // coordinator so trackpad scrolls zoom the camera the same way
        // pinch gestures do on iOS.
        let scnView = ScrollZoomSCNView()
        scnView.coordinator = context.coordinator
        configureSharedSceneView(scnView, context: context)
        installMacOSGestures(on: scnView, context: context)
        onViewReady(scnView, context.coordinator)
        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {}
    #endif

    // MARK: - Shared setup

    /// Common SCNView configuration applied on both platforms before the
    /// platform-specific gesture installers run.
    private func configureSharedSceneView(_ scnView: SCNView, context: Context) {
        scnView.scene = scene
        scnView.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        scnView.backgroundColor = PlatformColor.black
        scnView.antialiasingMode = .multisampling4X
        scnView.isJitteringEnabled = true

        // We manage the camera ourselves via gesture recognisers below.
        scnView.allowsCameraControl = false

        context.coordinator.scnView = scnView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onBodyTapped: onBodyTapped, onDoubleTap: onDoubleTap)
    }

    // MARK: - iOS gesture wiring

    #if canImport(UIKit)
    /// Install the five iOS gesture recognisers onto the SCNView. Preserves
    /// the pre-macOS-port input idioms unchanged: one finger translates, two
    /// fingers orbit, pinch zooms, tap selects, double-tap resets.
    private func installIOSGestures(on scnView: SCNView, context: Context) {
        let coordinator = context.coordinator

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePanIOS(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(pan)

        let orbit = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleOrbitIOS(_:)))
        orbit.minimumNumberOfTouches = 2
        orbit.maximumNumberOfTouches = 2
        scnView.addGestureRecognizer(orbit)

        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinchIOS(_:)))
        scnView.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        scnView.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scnView.addGestureRecognizer(doubleTap)

        // Single tap fires only if double-tap fails — otherwise single tap
        // would always pre-empt the reset gesture.
        tap.require(toFail: doubleTap)
    }
    #endif

    // MARK: - macOS gesture wiring

    #if !canImport(UIKit)
    /// Install the macOS equivalents: two pan recognisers (left button for
    /// translate, right button for orbit), a magnification recogniser for
    /// trackpad pinch, and two click recognisers for selection / reset.
    /// Scroll-wheel zoom is handled inside `ScrollZoomSCNView.scrollWheel`.
    private func installMacOSGestures(on scnView: SCNView, context: Context) {
        let coordinator = context.coordinator

        // Left-mouse drag → pan (buttonMask 0x1)
        let pan = NSPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePanMac(_:)))
        pan.buttonMask = 0x1
        scnView.addGestureRecognizer(pan)

        // Right-mouse drag → orbit (buttonMask 0x2). Falls back gracefully
        // on trackpads that secondary-click with two fingers.
        let orbit = NSPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleOrbitMac(_:)))
        orbit.buttonMask = 0x2
        scnView.addGestureRecognizer(orbit)

        // Trackpad pinch → zoom.
        let magnify = NSMagnificationGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleMagnifyMac(_:)))
        scnView.addGestureRecognizer(magnify)

        // Single click → select body.
        let click = NSClickGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:)))
        click.buttonMask = 0x1
        click.numberOfClicksRequired = 1
        scnView.addGestureRecognizer(click)

        // Double click → reset to overview. NSGestureRecognizer doesn't have
        // iOS's `require(toFail:)` equivalent, so single click fires during
        // a double-click sequence as well. In practice the reset visually
        // overrides the selection, and the cost of adding the dependency
        // tracking (via shouldRequireFailure(of:) in a subclass) isn't worth
        // it for a rarely-used interaction.
        let doubleClick = NSClickGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleClick.buttonMask = 0x1
        doubleClick.numberOfClicksRequired = 2
        scnView.addGestureRecognizer(doubleClick)
    }
    #endif

    // MARK: - Coordinator (camera controller)

    /// Manages an orbital camera around a target point using spherical
    /// coordinates. Handles all gesture input and exposes methods for
    /// programmatic camera control (focus presets, mission framing, zoom
    /// slider). Everything above the gesture-handler MARK is platform-neutral.
    class Coordinator: NSObject {
        let onBodyTapped: (CelestialBody) -> Void
        let onDoubleTap: () -> Void
        weak var scnView: SCNView?

        /// Set by the view model to be notified whenever the user initiates a
        /// pan / orbit / pinch gesture. Used to break the lazy-follow mission
        /// camera so the user has full manual control the moment they interact.
        var userInteractionHandler: (() -> Void)?

        // Camera orbital state (spherical coordinates around the target).
        private var cameraDistance: Float = 40.0
        private var orbitAngleX: Float = 0.0   // azimuth (radians)
        private var orbitAngleY: Float = 0.4   // elevation (radians)
        private var cameraTarget = SCNVector3Zero

        // Gesture delta tracking.
        private var lastPanPoint: CGPoint = .zero
        private var lastOrbitPoint: CGPoint = .zero
        private var lastPinchScale: CGFloat = 1.0
        private var lastMagnification: CGFloat = 0.0

        init(onBodyTapped: @escaping (CelestialBody) -> Void,
             onDoubleTap: @escaping () -> Void) {
            self.onBodyTapped = onBodyTapped
            self.onDoubleTap = onDoubleTap
            super.init()
        }

        // MARK: Camera positioning

        /// Recompute the camera position from spherical coordinates and look
        /// at the target. Called after every gesture update and every
        /// programmatic camera change.
        func updateCamera() {
            guard let scnView = scnView,
                  let cameraNode = scnView.pointOfView else { return }

            // Clamp elevation to avoid gimbal lock near the poles.
            orbitAngleY = max(-Float.pi / 2 * 0.95, min(Float.pi / 2 * 0.95, orbitAngleY))
            cameraDistance = max(0.5, min(250.0, cameraDistance))

            // Spherical-to-Cartesian offset from the target. Computed in
            // Double so the sum with the target (whose components are Float
            // on iOS, CGFloat on macOS) works through the unified
            // `SCNVector3(Double, Double, Double)` helper.
            let ox = Double(cameraDistance * cos(orbitAngleY) * sin(orbitAngleX))
            let oy = Double(cameraDistance * sin(orbitAngleY))
            let oz = Double(cameraDistance * cos(orbitAngleY) * cos(orbitAngleX))
            cameraNode.position = cameraTarget.adding(ox, oy, oz)
            cameraNode.look(at: cameraTarget)
        }

        /// Set camera to look at `target` from `distance`, optionally
        /// overriding orbit azimuth and elevation (used by mission framing
        /// and planet presets to place the camera Sun-side of the target).
        func setCamera(target: SCNVector3,
                       distance: Float,
                       azimuth: Float? = nil,
                       elevation: Float? = nil) {
            cameraTarget = target
            cameraDistance = distance
            if let azimuth { orbitAngleX = azimuth }
            if let elevation { orbitAngleY = elevation }
            updateCamera()
        }

        /// Current look-at target — read by the lazy-follow mission camera
        /// each frame so it can lerp toward a fresh target without snapping.
        var currentTarget: SCNVector3 { cameraTarget }

        /// Update just the target position (for tracking a moving body).
        func updateTarget(_ target: SCNVector3) {
            cameraTarget = target
            updateCamera()
        }

        /// Current camera distance from target — read by the zoom slider.
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

        // MARK: - Shared hit-testing (both platforms)

        /// Hit-test at a screen point and invoke `onBodyTapped` for the
        /// matching celestial body. Used by the single-tap / single-click
        /// recogniser on both platforms.
        private func selectBody(at screenPoint: CGPoint) {
            guard let scnView = scnView else { return }
            let hitResults = scnView.hitTest(screenPoint, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue
            ])

            guard let hit = hitResults.first else { return }
            let nodeName = hit.node.name ?? ""

            if nodeName == "sun" {
                onBodyTapped(SolarSystemData.sun)
                return
            }
            for body in SolarSystemData.allPlanets {
                if body.id == nodeName {
                    onBodyTapped(body)
                    return
                }
                for moon in body.moons where moon.id == nodeName {
                    onBodyTapped(moon)
                    return
                }
            }
        }

        // MARK: - Gesture handlers (iOS)

        #if canImport(UIKit)
        /// One-finger pan: translate the camera target in the camera's
        /// local right/up plane, speed scaled by current distance.
        @objc func handlePanIOS(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = scnView,
                  let cameraNode = scnView.pointOfView else { return }
            let translation = gesture.translation(in: scnView)
            if gesture.state == .began {
                lastPanPoint = .zero
                userInteractionHandler?()
            }
            let dx = Float(translation.x - lastPanPoint.x)
            let dy = Float(translation.y - lastPanPoint.y)
            lastPanPoint = translation
            applyPan(dx: dx, dy: dy, cameraNode: cameraNode)
        }

        /// Two-finger pan: orbit around the target (azimuth + elevation).
        @objc func handleOrbitIOS(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = scnView else { return }
            let translation = gesture.translation(in: scnView)
            if gesture.state == .began {
                lastOrbitPoint = .zero
                userInteractionHandler?()
            }
            let dx = Float(translation.x - lastOrbitPoint.x)
            let dy = Float(translation.y - lastOrbitPoint.y)
            lastOrbitPoint = translation
            applyOrbit(dx: dx, dy: dy)
        }

        /// Pinch: zoom by adjusting camera distance (clamped 0.5–250).
        @objc func handlePinchIOS(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began {
                lastPinchScale = gesture.scale
                userInteractionHandler?()
            }
            let scaleDelta = Float(gesture.scale / lastPinchScale)
            lastPinchScale = gesture.scale
            applyPinchZoom(scaleDelta: scaleDelta)
        }

        /// Single tap: hit-test the scene and select the tapped body.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let scnView = scnView else { return }
            selectBody(at: gesture.location(in: scnView))
        }

        /// Double tap: reset camera to the overview.
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            onDoubleTap()
        }
        #endif

        // MARK: - Gesture handlers (macOS)

        #if !canImport(UIKit)
        /// Left-mouse drag: translate camera target. Deltas are measured
        /// from gesture begin because NSPanGestureRecognizer's `translation`
        /// resets after each handler call — we accumulate manually to match
        /// the iOS pattern.
        @objc func handlePanMac(_ gesture: NSPanGestureRecognizer) {
            guard let scnView = scnView,
                  let cameraNode = scnView.pointOfView else { return }
            let translation = gesture.translation(in: scnView)
            if gesture.state == .began {
                lastPanPoint = .zero
                userInteractionHandler?()
            }
            let dx = Float(translation.x - lastPanPoint.x)
            // AppKit's Y axis is inverted relative to UIKit's (bottom-up vs
            // top-down), so flip dy so the pan direction feels natural.
            let dy = Float(lastPanPoint.y - translation.y)
            lastPanPoint = translation
            applyPan(dx: dx, dy: dy, cameraNode: cameraNode)
        }

        /// Right-mouse drag: orbit azimuth + elevation. Same accumulation
        /// pattern as `handlePanMac`.
        @objc func handleOrbitMac(_ gesture: NSPanGestureRecognizer) {
            guard let scnView = scnView else { return }
            let translation = gesture.translation(in: scnView)
            if gesture.state == .began {
                lastOrbitPoint = .zero
                userInteractionHandler?()
            }
            let dx = Float(translation.x - lastOrbitPoint.x)
            // Same Y flip as pan — natural feel of "drag up = look up".
            let dy = Float(lastOrbitPoint.y - translation.y)
            lastOrbitPoint = translation
            applyOrbit(dx: dx, dy: dy)
        }

        /// Trackpad pinch: zoom. NSMagnificationGestureRecognizer reports a
        /// cumulative `magnification` value around 0 (±0.3 is a comfortable
        /// pinch); we convert to a per-frame delta by subtracting the last
        /// reading.
        @objc func handleMagnifyMac(_ gesture: NSMagnificationGestureRecognizer) {
            if gesture.state == .began {
                lastMagnification = 0
                userInteractionHandler?()
            }
            let delta = gesture.magnification - lastMagnification
            lastMagnification = gesture.magnification
            // Convert the cumulative magnification to a multiplicative scale
            // factor. Negative magnifications zoom out (>1.0), positive
            // zoom in (<1.0). The 1+ offset mirrors UIPinch's `scale`.
            let scaleDelta = Float(1 + delta)
            applyPinchZoom(scaleDelta: scaleDelta)
        }

        /// Scroll-wheel zoom routed from `ScrollZoomSCNView.scrollWheel(with:)`.
        /// Positive deltas zoom in, negative zoom out, matching the macOS
        /// norm of "scroll up to move closer". Uses an exponential scale so
        /// successive scrolls at any current distance feel uniform.
        func handleScrollWheel(deltaY: CGFloat) {
            guard deltaY != 0 else { return }
            userInteractionHandler?()
            // `0.02` scale constant tuned so a single notch of a wheel
            // mouse feels ~10% zoom, a full trackpad swipe ~50%.
            let factor = Float(exp(deltaY * 0.02))
            applyPinchZoom(scaleDelta: factor)
        }

        /// Single click / tap (both platforms): hit-test and select the
        /// tapped celestial body. Signature is `UITapGestureRecognizer` on
        /// iOS and `NSClickGestureRecognizer` on macOS but both expose a
        /// `location(in:)` method, so one `@objc` handler fits both.
        @objc func handleTap(_ gesture: NSGestureRecognizer) {
            guard let scnView = scnView else { return }
            selectBody(at: gesture.location(in: scnView))
        }

        /// Double click / tap: reset camera to the overview.
        @objc func handleDoubleTap(_ gesture: NSGestureRecognizer) {
            onDoubleTap()
        }
        #endif

        // MARK: - Shared gesture maths

        /// Translate `cameraTarget` in the camera's local screen plane, given
        /// a per-frame pixel delta. Used by both iOS one-finger pan and
        /// macOS left-drag pan. The sign convention is "drag right → move
        /// the scene right under the cursor".
        private func applyPan(dx: Float, dy: Float, cameraNode: SCNNode) {
            let speed = cameraDistance * 0.002
            let right = cameraNode.worldRight
            let up = cameraNode.worldUp
            // Compute the deltas in Double so the subtract works regardless
            // of whether SCNVector3 components are Float (iOS) or CGFloat (macOS).
            let dX = Double(Float(right.x) * dx * speed - Float(up.x) * dy * speed)
            let dY = Double(Float(right.y) * dx * speed - Float(up.y) * dy * speed)
            let dZ = Double(Float(right.z) * dx * speed - Float(up.z) * dy * speed)
            cameraTarget = cameraTarget.adding(-dX, -dY, -dZ)
            updateCamera()
        }

        /// Adjust azimuth + elevation from a screen-pixel delta. 0.005 rad
        /// per pixel feels natural on both touch and mouse.
        private func applyOrbit(dx: Float, dy: Float) {
            orbitAngleX -= dx * 0.005
            orbitAngleY += dy * 0.005
            updateCamera()
        }

        /// Apply a multiplicative scale to `cameraDistance`. Both UIPinch's
        /// `scale` and the magnify/scroll conversions above feed this path
        /// with a scale where >1 zooms in, <1 zooms out.
        private func applyPinchZoom(scaleDelta: Float) {
            cameraDistance = max(0.5, min(250.0, cameraDistance / scaleDelta))
            updateCamera()
        }
    }
}

// MARK: - macOS SCNView subclass for scroll-wheel zoom

#if !canImport(UIKit)
/// `SCNView` subclass that captures scroll-wheel NSEvents and forwards them
/// to the coordinator as zoom deltas. Needed because NSGestureRecognizer
/// doesn't cover scroll-wheel input directly — it's a view-level event.
private final class ScrollZoomSCNView: SCNView {
    weak var coordinator: SolarSystemSceneView.Coordinator?

    override func scrollWheel(with event: NSEvent) {
        coordinator?.handleScrollWheel(deltaY: event.scrollingDeltaY)
    }

    // Accept keyboard focus so the scroll event reaches us even when the
    // user hasn't explicitly clicked the view. The alternative is to make
    // the hosting NSWindow forward events, which is more fragile.
    override var acceptsFirstResponder: Bool { true }
}
#endif
