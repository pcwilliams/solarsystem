// SolarSystemViewModel.swift
// SolarSystem
//
// Central view model driving the solar system simulation. Owns the SceneKit
// scene, advances simulated time via CADisplayLink, computes heliocentric
// positions for all bodies each frame, and projects 3D positions to screen
// coordinates for the SwiftUI label overlay.

import Foundation
import SceneKit
import UIKit

// MARK: - Screen Label

/// A celestial body label projected to 2D screen coordinates for the SwiftUI overlay.
struct ScreenLabel: Identifiable {
    let id: String
    let name: String
    let screenPoint: CGPoint
    let isMoon: Bool
    let isStar: Bool
    /// Higher = more important (planets > moons; larger bodies rank higher)
    let priority: Int

    init(id: String, name: String, screenPoint: CGPoint, isMoon: Bool,
         priority: Int, isStar: Bool = false) {
        self.id = id
        self.name = name
        self.screenPoint = screenPoint
        self.isMoon = isMoon
        self.isStar = isStar
        self.priority = priority
    }
}

// MARK: - View Model

@MainActor
final class SolarSystemViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedBody: CelestialBody?
    @Published var showOrbits: Bool = UserDefaults.standard.object(forKey: "showOrbits") == nil ? true : UserDefaults.standard.bool(forKey: "showOrbits") {
        didSet { UserDefaults.standard.set(showOrbits, forKey: "showOrbits") }
    }
    @Published var showPlanetLabels: Bool = UserDefaults.standard.object(forKey: "showPlanetLabels") == nil ? true : UserDefaults.standard.bool(forKey: "showPlanetLabels") {
        didSet { UserDefaults.standard.set(showPlanetLabels, forKey: "showPlanetLabels") }
    }
    @Published var showMoonLabels: Bool = UserDefaults.standard.object(forKey: "showMoonLabels") == nil ? true : UserDefaults.standard.bool(forKey: "showMoonLabels") {
        didSet { UserDefaults.standard.set(showMoonLabels, forKey: "showMoonLabels") }
    }
    @Published var showStarLabels: Bool = UserDefaults.standard.object(forKey: "showStarLabels") == nil ? true : UserDefaults.standard.bool(forKey: "showStarLabels") {
        didSet { UserDefaults.standard.set(showStarLabels, forKey: "showStarLabels") }
    }
    @Published var timeScale: Double = 1.0
    @Published var isPaused: Bool = false
    @Published var currentDate: Date = Date()
    @Published var screenLabels: [ScreenLabel] = []
    @Published var zoomLevel: Double = 0.5

    // MARK: - Scene

    let scene: SCNScene
    private let sceneBuilder = SceneBuilder()
    weak var scnView: SCNView?

    /// Reference to the scene view coordinator for camera control.
    /// When set, applies any deferred focus from launch arguments.
    var cameraCoordinator: SolarSystemSceneView.Coordinator? {
        didSet {
            if let focus = pendingFocus, cameraCoordinator != nil {
                pendingFocus = nil
                focusOnBody(named: focus)
            }
        }
    }
    private var pendingFocus: String?

    // MARK: - Body Tracking

    private var bodies: [CelestialBody] = []
    private var bodyNodes: [String: SCNNode] = [:]
    private var moonNodes: [String: SCNNode] = [:]
    private var orbitNodes: [String: SCNNode] = [:]
    private var frameCount: Int = 0

    // MARK: - Animation Timer

    private var displayLink: CADisplayLink?
    private var lastUpdateTime: CFTimeInterval = 0
    private var simulatedDate: Date

    // MARK: - Launch Arguments

    private var overrideDate: Date?
    private var initialFocus: String?
    private var logPositions: Bool = false
    private var innerOnly: Bool = false

    // MARK: - Init

    init() {
        self.simulatedDate = Date()
        self.scene = sceneBuilder.buildScene()
        parseLaunchArguments()
        setupBodies()
        setupScene()

        if let date = overrideDate {
            simulatedDate = date
        }
    }

    // MARK: - Launch Arguments

    /// Parse CLI launch arguments for testing and debugging.
    /// Supports: -timeScale, -date, -focus, -showOrbits/-hideOrbits,
    /// -showLabels/-hideLabels, -logPositions, -innerOnly
    private func parseLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments

        if let idx = args.firstIndex(of: "-timeScale"), idx + 1 < args.count,
           let scale = Double(args[idx + 1]) {
            timeScale = scale
        }

        if let idx = args.firstIndex(of: "-date"), idx + 1 < args.count {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            if let date = formatter.date(from: args[idx + 1]) {
                overrideDate = date
            }
        }

        if let idx = args.firstIndex(of: "-focus"), idx + 1 < args.count {
            initialFocus = args[idx + 1].lowercased()
        }

        if args.contains("-showOrbits") { showOrbits = true }
        if args.contains("-hideOrbits") { showOrbits = false }
        if args.contains("-showLabels") { showPlanetLabels = true; showMoonLabels = true; showStarLabels = true }
        if args.contains("-hideLabels") { showPlanetLabels = false; showMoonLabels = false; showStarLabels = false }
        if args.contains("-logPositions") { logPositions = true }
        if args.contains("-innerOnly") { innerOnly = true }
    }

    // MARK: - Scene Setup

    /// Create the body list, optionally filtering to inner planets only.
    private func setupBodies() {
        var allBodies = SolarSystemData.allPlanets
        if innerOnly {
            allBodies = allBodies.filter { ["mercury", "venus", "earth", "mars"].contains($0.id) }
        }
        bodies = allBodies
    }

    /// Populate the SceneKit scene with body nodes, orbit paths, and moon nodes.
    private func setupScene() {
        // Sun at the origin
        let sunNode = sceneBuilder.createBodyNode(for: SolarSystemData.sun)
        sunNode.position = SCNVector3Zero
        scene.rootNode.addChildNode(sunNode)
        bodyNodes["sun"] = sunNode

        // Planets with their orbit paths and moons
        for body in bodies {
            let node = sceneBuilder.createBodyNode(for: body)
            scene.rootNode.addChildNode(node)
            bodyNodes[body.id] = node

            if let orbitNode = sceneBuilder.createOrbitNode(for: body, at: simulatedDate) {
                orbitNode.isHidden = !showOrbits
                scene.rootNode.addChildNode(orbitNode)
                orbitNodes[body.id] = orbitNode
            }

            for moon in body.moons {
                let moonNode = sceneBuilder.createBodyNode(for: moon)
                scene.rootNode.addChildNode(moonNode)
                moonNodes[moon.id] = moonNode
            }
        }

        // Apply bundled NASA texture maps to planets and moons
        applyTextures()

        // Set initial positions from current date
        updatePositions()

        // Defer camera focus until the coordinator is connected
        if let focus = initialFocus {
            pendingFocus = focus
        }
    }

    /// Load and apply bundled JPG texture maps to planet and moon sphere geometries.
    private func applyTextures() {
        let planetTextures: [(id: String, file: String)] = [
            ("mercury", "mercury_2k"),
            ("venus", "venus_2k"),
            ("earth", "earth_2k"),
            ("mars", "mars_2k"),
            ("jupiter", "jupiter_2k"),
            ("saturn", "saturn_2k"),
            ("uranus", "uranus_2k"),
            ("neptune", "neptune_2k"),
            ("pluto", "pluto_2k"),
        ]
        for entry in planetTextures {
            guard let node = bodyNodes[entry.id],
                  let geometry = node.geometry as? SCNSphere,
                  let path = Bundle.main.path(forResource: entry.file, ofType: "jpg"),
                  let image = UIImage(contentsOfFile: path) else { continue }
            geometry.firstMaterial?.diffuse.contents = image
        }

        let moonTextures: [(id: String, file: String)] = [
            ("moon", "moon_2k"),
            ("io", "io_2k"),
            ("europa", "europa_2k"),
            ("ganymede", "ganymede_2k"),
            ("callisto", "callisto_2k"),
        ]
        for entry in moonTextures {
            guard let node = moonNodes[entry.id],
                  let geometry = node.geometry as? SCNSphere,
                  let path = Bundle.main.path(forResource: entry.file, ofType: "jpg"),
                  let image = UIImage(contentsOfFile: path) else { continue }
            geometry.firstMaterial?.diffuse.contents = image
        }
    }

    // MARK: - Animation Loop

    /// Start the CADisplayLink render loop at 30-60 fps.
    func startAnimation() {
        let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
        lastUpdateTime = CACurrentMediaTime()
    }

    func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Called each frame by CADisplayLink. Advances simulation time and updates positions.
    @objc private func displayLinkFired(_ link: CADisplayLink) {
        guard !isPaused else { return }

        let now = CACurrentMediaTime()
        let dt = now - lastUpdateTime
        lastUpdateTime = now
        frameCount += 1

        // Advance simulated date by wall-clock delta scaled by the time multiplier
        let scaledSeconds = dt * timeScale
        simulatedDate = simulatedDate.addingTimeInterval(scaledSeconds)

        // Throttle @Published updates to every 3rd frame to reduce SwiftUI re-render overhead
        let updateUI = (frameCount % 3 == 0)
        if updateUI { currentDate = simulatedDate }

        updatePositions(projectLabels: updateUI)

        if updateUI { syncZoomFromCamera() }
    }

    // MARK: - Position Updates

    /// Set to true during zoom slider drag to suppress label rendering.
    var isZooming = false

    /// Recompute all body positions from orbital mechanics for the current simulated date.
    /// Optionally projects 3D positions to screen coordinates for the SwiftUI label overlay.
    private func updatePositions(projectLabels: Bool = true) {
        let cameraNode = scene.rootNode.childNode(withName: "camera", recursively: false)
        let daysSinceJ2000 = OrbitalMechanics.julianDate(from: simulatedDate) - OrbitalMechanics.j2000

        // Rotate the Sun on its axis
        if let sunNode = bodyNodes["sun"] {
            applyRotation(to: sunNode, body: SolarSystemData.sun, daysSinceJ2000: daysSinceJ2000)
        }

        let shouldProjectLabels = projectLabels && !isZooming
        var newLabels: [ScreenLabel] = []

        for i in 0..<bodies.count {
            let body = bodies[i]
            guard let elements = body.orbitalElements,
                  let node = bodyNodes[body.id] else { continue }

            // Solve Kepler's equation to get heliocentric position
            let position = OrbitalMechanics.heliocentricPosition(elements: elements, at: simulatedDate)
            bodies[i].position = position
            sceneBuilder.updateNodePosition(node, position: position)
            applyRotation(to: node, body: body, daysSinceJ2000: daysSinceJ2000)

            // Project planet label (priority based on physical radius)
            if shouldProjectLabels && showPlanetLabels {
                let planetPriority = 100 + Int(body.physical.radiusKm / 100)
                if let label = projectLabel(name: body.name, id: body.id, node: node,
                                             isMoon: false, priority: planetPriority) {
                    newLabels.append(label)
                }
            }

            // Update each moon's position relative to its parent planet
            for moon in body.moons {
                guard let moonElements = moon.moonElements,
                      let moonNode = moonNodes[moon.id] else { continue }

                let moonOffset = OrbitalMechanics.moonPosition(moonElements: moonElements, at: simulatedDate)
                sceneBuilder.updateMoonNodePosition(moonNode, moonOffset: moonOffset,
                                                     parentPosition: position,
                                                     parentRadiusKm: body.physical.radiusKm,
                                                     moonSemiMajorKm: moonElements.semiMajorAxisKm)
                applyRotation(to: moonNode, body: moon, daysSinceJ2000: daysSinceJ2000)

                if shouldProjectLabels && showMoonLabels {
                    let moonPriority = Int(moon.physical.radiusKm / 100)
                    if let label = projectLabel(name: moon.name, id: moon.id, node: moonNode,
                                                 isMoon: true, priority: moonPriority) {
                        newLabels.append(label)
                    }
                }
            }

            // Debug: print heliocentric coordinates each frame when -logPositions is set
            if logPositions {
                let dist = simd_length(position)
                print("[\(body.name)] x=\(String(format: "%.4f", position.x)) y=\(String(format: "%.4f", position.y)) z=\(String(format: "%.4f", position.z)) r=\(String(format: "%.4f", dist)) AU")
            }
        }

        // Project named star labels, culling those occluded by planet discs
        if shouldProjectLabels, showStarLabels, let view = scnView {
            // Build a list of body screen positions and approximate screen radii for occlusion
            var bodyScreenPositions: [(point: CGPoint, screenRadius: CGFloat)] = []
            for (_, node) in bodyNodes {
                let sp = view.projectPoint(node.position)
                guard sp.z < 1.0 else { continue }
                let radius = (node.geometry as? SCNSphere)?.radius ?? 0.1
                let screenR = max(CGFloat(Float(radius) / max(sp.z, 0.001) * 300), 15)
                bodyScreenPositions.append((CGPoint(x: CGFloat(sp.x), y: CGFloat(sp.y)), screenR))
            }

            for star in sceneBuilder.namedStars {
                let starPriority = Int(star.magnitude * -10 + 40)
                guard let label = projectLabel(name: star.name, id: "star_\(star.name)",
                                                node: nil, isMoon: true, priority: starPriority,
                                                worldPosition: star.position, isStar: true) else { continue }

                // Skip star labels that overlap a planet's on-screen disc
                let occluded = bodyScreenPositions.contains { body in
                    let dx = label.screenPoint.x - body.point.x
                    let dy = label.screenPoint.y - body.point.y
                    return sqrt(dx * dx + dy * dy) < body.screenRadius
                }
                if !occluded {
                    newLabels.append(label)
                }
            }
        }

        if shouldProjectLabels {
            screenLabels = deconflictLabels(newLabels)
        } else if isZooming && !screenLabels.isEmpty {
            screenLabels = []
        }
    }

    // MARK: - Rotation

    /// Apply IAU axial tilt and spin to a body node.
    /// Apply axial tilt and spin using quaternions so the tilt axis stays fixed
    /// in space while spin occurs around the tilted pole. Euler angles can't do
    /// this correctly because SceneKit applies them in Y-X-Z order, causing wobble.
    private func applyRotation(to node: SCNNode, body: CelestialBody, daysSinceJ2000: Double) {
        guard let rot = body.rotation else { return }
        let tilt = Float(rot.obliquity.degreesToRadians)
        let spin = rot.rotationAngle(daysSinceJ2000: daysSinceJ2000)

        // Compose: first tilt around X (fixed in space), then spin around tilted Y (pole axis)
        let tiltQuat = simd_quatf(angle: tilt, axis: simd_float3(1, 0, 0))
        let spinQuat = simd_quatf(angle: spin, axis: simd_float3(0, 1, 0))
        node.simdOrientation = tiltQuat * spinQuat

        // Saturn's rings: cancel spin in local frame, keeping only the inherited tilt
        if body.physical.hasRings,
           let ringNode = node.childNode(withName: "saturn_rings", recursively: false) {
            let cancelSpin = simd_quatf(angle: -spin, axis: simd_float3(0, 1, 0))
            ringNode.simdOrientation = cancelSpin
        }
    }

    // MARK: - Label Projection

    /// Project a 3D world position to 2D screen coordinates for the SwiftUI label overlay.
    /// Returns nil if the position is behind the camera or off-screen.
    private func projectLabel(name: String, id: String, node: SCNNode?,
                               isMoon: Bool, priority: Int,
                               worldPosition: SCNVector3? = nil,
                               isStar: Bool = false) -> ScreenLabel? {
        guard let view = scnView else { return nil }
        let pos = worldPosition ?? node?.position ?? SCNVector3Zero
        let screenPos = view.projectPoint(pos)
        // z >= 1.0 means the point is behind the camera
        guard screenPos.z < 1.0 else { return nil }
        let point = CGPoint(x: CGFloat(screenPos.x), y: CGFloat(screenPos.y))
        let bounds = view.bounds
        // Allow 50pt bleed outside visible bounds so labels don't pop in/out abruptly
        guard point.x > -50 && point.x < bounds.width + 50 &&
              point.y > -50 && point.y < bounds.height + 50 else { return nil }
        return ScreenLabel(id: id, name: name, screenPoint: point, isMoon: isMoon,
                           priority: priority, isStar: isStar)
    }

    /// Remove overlapping labels by priority. Planet labels are always shown;
    /// moons and stars are placed only if they don't overlap higher-priority labels.
    private func deconflictLabels(_ labels: [ScreenLabel]) -> [ScreenLabel] {
        let planets = labels.filter { !$0.isMoon }
        let others = labels.filter { $0.isMoon }.sorted { $0.priority > $1.priority }

        var placed = planets

        for label in others {
            let minDist: CGFloat = 35
            let tooClose = placed.contains { existing in
                let dx = label.screenPoint.x - existing.screenPoint.x
                let dy = label.screenPoint.y - existing.screenPoint.y
                return sqrt(dx * dx + dy * dy) < minDist
            }
            if !tooClose {
                placed.append(label)
            }
        }

        return placed
    }

    // MARK: - Orbit & Label Visibility

    /// Toggle orbital path line visibility for all planets.
    func toggleOrbits() {
        showOrbits.toggle()
        for (_, node) in orbitNodes {
            node.isHidden = !showOrbits
        }
    }

    // MARK: - Time Control

    /// Reset simulation to the current real-world date/time.
    func resetToNow() {
        simulatedDate = Date()
        currentDate = simulatedDate
        timeScale = 1.0
        isPaused = false
    }

    // MARK: - Zoom

    // Logarithmic zoom mapping: slider 0..1 maps to camera distance 0.15..250 AU-scale units
    private static let zoomMinDist: Double = 0.5
    private static let zoomMaxDist: Double = 250.0

    /// Convert camera distance to zoom slider fraction (0 = closest, 1 = farthest).
    private func distanceToZoom(_ dist: Float) -> Double {
        let logMin = log(Self.zoomMinDist)
        let logMax = log(Self.zoomMaxDist)
        let logDist = log(max(Double(dist), Self.zoomMinDist))
        return (logDist - logMin) / (logMax - logMin)
    }

    /// Convert zoom slider fraction to camera distance.
    private func zoomToDistance(_ zoom: Double) -> Float {
        let logMin = log(Self.zoomMinDist)
        let logMax = log(Self.zoomMaxDist)
        return Float(exp(logMin + zoom * (logMax - logMin)))
    }

    /// Sync the zoom slider position from the coordinator's current camera distance.
    func syncZoomFromCamera() {
        guard let coord = cameraCoordinator else { return }
        let newZoom = distanceToZoom(coord.currentDistance)
        if abs(newZoom - zoomLevel) > 0.001 {
            zoomLevel = newZoom
        }
    }

    /// Apply a zoom slider change to the camera distance.
    func applyZoom(_ level: Double) {
        zoomLevel = level
        let dist = zoomToDistance(level)
        cameraCoordinator?.setDistance(dist)
    }

    // MARK: - Camera

    /// Calculate the scene-space extent of a body's moon system for framing.
    private func moonSystemRadius(for body: CelestialBody) -> Float {
        guard !body.moons.isEmpty else { return 0 }

        let parentRadius = SceneBuilder.sceneRadius(km: body.physical.radiusKm, type: body.type)
        var maxDist: Float = 0

        for moon in body.moons {
            guard let me = moon.moonElements else { continue }
            let realRatio = me.semiMajorAxisKm / body.physical.radiusKm
            let compressedRatio = pow(realRatio, 0.4) * 1.5
            let moonSceneDist = Float(Double(parentRadius) * compressedRatio)
            let moonRadius = SceneBuilder.sceneRadius(km: moon.physical.radiusKm, type: .moon)
            maxDist = max(maxDist, moonSceneDist + moonRadius)
        }

        return maxDist
    }

    /// Move the camera to frame a specific scene node, accounting for its moon system extent.
    func focusCamera(on node: SCNNode) {
        let systemExtent = focusedSystemExtent()
        let cameraDistance = max(systemExtent * 3.7, 0.5)
        cameraCoordinator?.setCamera(target: node.position, distance: cameraDistance)
    }

    /// Returns the visual extent (radius) of the currently selected body's system.
    private func focusedSystemExtent() -> Float {
        guard let body = selectedBody ?? bodies.first else { return 0.5 }
        let planetRadius = SceneBuilder.sceneRadius(km: body.physical.radiusKm, type: body.type)
        let moonExtent = moonSystemRadius(for: body)
        return max(planetRadius, moonExtent)
    }

    /// Focus the camera on a body by name. Searches planets, the Sun, then moons.
    func focusOnBody(named name: String) {
        let id = name.lowercased().replacingOccurrences(of: " ", with: "_")

        if let body = bodies.first(where: { $0.id == id }) {
            selectedBody = body
            if let node = bodyNodes[id] {
                focusCamera(on: node)
            }
            return
        }

        if id == "sun" {
            selectedBody = SolarSystemData.sun
            if let node = bodyNodes["sun"] {
                focusCamera(on: node)
            }
            return
        }

        if let node = moonNodes[id] {
            focusCamera(on: node)
        }
    }

    /// Reset to the default overview showing the full solar system.
    func resetCamera() {
        let earthDist = Float(SceneBuilder.sceneDistance(au: 1.0))
        cameraCoordinator?.resetToOverview(earthDist: earthDist)
        selectedBody = nil
    }
}
