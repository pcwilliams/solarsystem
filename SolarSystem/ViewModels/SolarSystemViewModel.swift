// SolarSystemViewModel.swift
// SolarSystem
//
// Central view model driving the solar system simulation. Owns the SceneKit
// scene, advances simulated time via CADisplayLink, computes heliocentric
// positions for all bodies each frame, and projects 3D positions to screen
// coordinates for the SwiftUI label overlay.

import Foundation
import SceneKit

// MARK: - Screen Label

/// Fleeting event banner shown when the simulation crosses a mission event
/// timestamp. The view model publishes a new identity each time so SwiftUI
/// re-runs the slide-in animation even when the same event fires twice.
struct MissionEventBanner: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let missionName: String
    let missionColor: SIMD3<Float>
}

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
    /// ISS visibility — default off, because it's a tiny bright dot that
    /// distracts from overview rendering. Toggled via the Satellites menu.
    @Published var showISS: Bool = UserDefaults.standard.bool(forKey: "showISS") {
        didSet {
            UserDefaults.standard.set(showISS, forKey: "showISS")
            moonNodes["iss"]?.isHidden = !showISS
        }
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
            if let coord = cameraCoordinator {
                coord.userInteractionHandler = { [weak self] in
                    self?.userInteractedWithCamera()
                }
            }
            if let focus = pendingFocus, cameraCoordinator != nil {
                pendingFocus = nil
                // Run one position update so Earth/Moon/planets are at their
                // simulated-date positions before focus maths read them. Without
                // this, focus lands on the origin (default node position) and the
                // camera ends up looking at empty space near the Sun.
                updatePositions(projectLabels: false)
                focusOnBody(named: focus)
            }
            // Mission camera framing had to wait for the coordinator to come online.
            if let pending = pendingMissionFraming, cameraCoordinator != nil,
               let mission = missionManager.missions.first(where: { $0.id == pending }) {
                pendingMissionFraming = nil
                applyMissionCameraFraming(for: mission)
            }
            #if os(macOS)
            // Frame ticker needs the SCNView on macOS (NSView.displayLink).
            // If startAnimation ran before the view connected, kick it off now.
            if pendingAnimationStart, cameraCoordinator != nil {
                pendingAnimationStart = false
                startAnimation()
            }
            #endif
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

    // Cross-platform frame ticker — `CADisplayLink` on both platforms, just
    // constructed differently:
    //   - iOS: direct `CADisplayLink(target:selector:)` (exists since iOS 3).
    //   - macOS 14+: via `NSView.displayLink(target:selector:)`, which binds
    //     the link to the view's display so it syncs to that screen's VBlank.
    // Using a plain `Timer` on macOS looked equivalent in code but stuttered
    // every 1–2 seconds because the Timer's fire cadence drifts in and out of
    // phase with the 60 Hz VBlank. The display-link avoids that entirely.
    private var displayLink: CADisplayLink?
    private var lastUpdateTime: CFTimeInterval = 0
    private var simulatedDate: Date

    // MARK: - Launch Arguments

    private var overrideDate: Date?
    private var initialFocus: String?
    private var logPositions: Bool = false
    /// Per-frame timing diagnostic toggle (`-frameLog`). When enabled, prints
    /// any frame whose inter-tick interval exceeds 20 ms (dropped frame on a
    /// 60 Hz display) or whose work time exceeds 5 ms, plus a rolling summary
    /// once per second. Used for diagnosing UI stutters without drowning the
    /// console during normal runs.
    private var frameLogEnabled: Bool = false
    /// Accumulators for the rolling per-second frame-timing summary.
    private var frameLogTickCount: Int = 0
    private var frameLogWorstTick: Double = 0
    private var frameLogWorstWork: Double = 0
    private var frameLogSummaryTime: Double = 0
    private var innerOnly: Bool = false
    private var initialMissionId: String?

    // MARK: - Missions

    let missionManager = MissionManager()

    /// Currently selected mission id (or nil). Drives trajectory visibility
    /// and telemetry. Setting this also jumps simulation time to the mission's
    /// launch date and applies its auto-speed preset.
    @Published var activeMissionId: String? {
        didSet {
            missionManager.selectedMissionId = activeMissionId
            if let id = activeMissionId,
               let mission = missionManager.missions.first(where: { $0.id == id }) {
                simulatedDate = mission.launchDate
                currentDate = simulatedDate
                timeScale = mission.autoTimeScale()
                isPaused = false
                missionElapsedHours = 0
                missionEndSpeedResetArmed = true
                applyMissionCameraFraming(for: mission)
            } else {
                missionTelemetry = nil
                missionElapsedHours = 0
                lazyFollowActive = false
            }
        }
    }

    /// Drives per-frame lazy camera follow for geocentric missions. Cleared when
    /// the user drags / pinches (see `cameraCoordinator`'s gesture hooks) or when
    /// the mission is cancelled.
    @Published var lazyFollowActive: Bool = false

    /// Live telemetry (MET, distance, speed) for the active mission's primary vehicle.
    /// Nil when no mission is selected or the simulated date is outside the mission window.
    @Published var missionTelemetry: MissionTelemetry?

    /// Elapsed mission hours from launch. Drives the timeline slider and
    /// lets the UI show MET even while paused.
    @Published var missionElapsedHours: Double = 0

    /// Banner shown when an event fires. Cleared after 4 seconds.
    @Published var currentEventBanner: MissionEventBanner?

    /// True while the timeline slider is actively being dragged — suppresses
    /// the per-frame elapsed-hours sync so the UI doesn't fight the gesture.
    @Published var timelineScrubbing: Bool = false {
        didSet {
            // Pause playback while scrubbing so the display link doesn't advance simulation time.
            if timelineScrubbing { wasPausedBeforeScrub = isPaused; isPaused = true }
            else { isPaused = wasPausedBeforeScrub }
        }
    }
    private var wasPausedBeforeScrub = false

    /// Banner auto-dismiss work item — replaced on each new event to reset the 4s timer.
    private var eventBannerDismissWork: DispatchWorkItem?

    /// Whether to arm the end-of-mission speed-reset (prevents it firing repeatedly).
    private var missionEndSpeedResetArmed: Bool = false

    /// Apply a timeline slider position (0..durationHours) to the simulated date.
    func seekMission(toElapsedHours hours: Double) {
        guard let id = activeMissionId,
              let mission = missionManager.missions.first(where: { $0.id == id }) else { return }
        let clamped = max(0, min(mission.durationHours, hours))
        simulatedDate = mission.launchDate.addingTimeInterval(clamped * 3600)
        currentDate = simulatedDate
        missionElapsedHours = clamped
        missionManager.resetEventTriggers(missionId: id)
        // Re-run a single position update so the trajectory marker jumps with the slider
        // rather than waiting for the next frame (looks sluggish at high drag speeds).
        updatePositions(projectLabels: false)
    }

    /// Cancel the active mission, keep the current simulated date, reset speed to 1x.
    func cancelMission() {
        activeMissionId = nil
        timeScale = 1.0
    }

    /// Initial camera framing when a mission is selected.
    /// - Geocentric (lunar): snap to Earth + trajectory local centre, Sun-side azimuth,
    ///   elevation ≈17°, distance sized to fit the trajectory's local radius. Lazy-follow
    ///   then lerps each frame.
    /// - Heliocentric (interplanetary): reset to overview — the standard system view
    ///   already shows the full trajectory cleanly.
    private func applyMissionCameraFraming(for mission: Mission) {
        guard let coord = cameraCoordinator else {
            // Camera not connected yet — apply when it arrives via pendingFocus analog.
            pendingMissionFraming = mission.id
            return
        }
        if mission.referenceFrame == .heliocentric {
            let earthDist = Float(SceneBuilder.sceneDistance(au: 1.0))
            coord.resetToOverview(earthDist: earthDist)
            lazyFollowActive = false
            return
        }

        // Ensure Earth's scene position is up to date so the initial frame lands correctly.
        updatePositions(projectLabels: false)
        guard let bounds = missionManager.missionBounds(missionId: mission.id),
              let earthNode = bodyNodes["earth"] else {
            lazyFollowActive = false
            return
        }

        // Sun-side azimuth: camera sits between the Sun (origin) and Earth so
        // the Earth/Moon system is lit for the camera. `atan2(-x, -z)` gives
        // the direction *from Earth toward the Sun*, which is where we want
        // the camera. The 0.55 rad (~31°) offset puts the terminator on the
        // far side of the target for a dramatic two-thirds-illuminated view.
        // `Float(...)` coerces the SCNVector3 components so the result type
        // matches on both iOS (Float) and macOS (CGFloat).
        let earthPos = earthNode.position
        let sunsideAzimuth: Float = atan2(Float(-earthPos.x), Float(-earthPos.z))
        let azimuth = sunsideAzimuth + 0.55
        let elevation: Float = 0.3

        let target = SCNVector3(earthPos.x + bounds.localCenter.x,
                                earthPos.y + bounds.localCenter.y,
                                earthPos.z + bounds.localCenter.z)
        // Fit the trajectory's local radius into the viewport — SceneKit's default
        // FOV is ~60°, so distance ≈ radius / tan(30°) × 1.4 padding for phone portrait.
        let radius = max(bounds.localRadius, 0.5)
        let fovFactor: Float = 1.4 / tan(.pi / 6)
        let distance = max(radius * fovFactor, 1.5)
        coord.setCamera(target: target, distance: distance, azimuth: azimuth, elevation: elevation)
        missionLocalCenter = bounds.localCenter
        lazyFollowActive = true
        zoomLevel = distanceToZoom(distance)
    }

    /// Trajectory centre offset from Earth (geocentric missions only) — used by the
    /// lazy-follow lerp each frame.
    private var missionLocalCenter: SCNVector3?

    /// If a mission was selected before the camera coordinator came online,
    /// remember the id so framing can run once `cameraCoordinator.didSet` fires.
    private var pendingMissionFraming: String?

    /// Per-frame lerp that keeps the camera target glued to Earth + the
    /// trajectory centre, so the trajectory stays centred on screen even as
    /// Earth drifts through its heliocentric orbit. Clears if the user
    /// interacts with the camera.
    private func stepLazyFollowCamera() {
        guard lazyFollowActive,
              let id = activeMissionId,
              let mission = missionManager.missions.first(where: { $0.id == id }),
              mission.isGeocentric,
              let coord = cameraCoordinator,
              let earthNode = bodyNodes["earth"] else { return }

        let offset = missionLocalCenter ?? SCNVector3Zero
        let wantedTarget = SCNVector3(earthNode.position.x + offset.x,
                                       earthNode.position.y + offset.y,
                                       earthNode.position.z + offset.z)

        // Lerp factor 0.02 is the same value the web app uses for a smooth follow
        // without stutter. Higher = snappier, lower = more floaty.
        // Lerp the camera target toward the new position. Arithmetic is done
        // in Double to sidestep the Float/CGFloat mismatch between iOS and
        // macOS SCNVector3 component types, then fed through our cross-
        // platform `SCNVector3(Double, Double, Double)` helper.
        let current = coord.currentTarget
        let lerp: Double = 0.02
        let cx = Double(current.x) + (Double(wantedTarget.x) - Double(current.x)) * lerp
        let cy = Double(current.y) + (Double(wantedTarget.y) - Double(current.y)) * lerp
        let cz = Double(current.z) + (Double(wantedTarget.z) - Double(current.z)) * lerp
        coord.updateTarget(SCNVector3(cx, cy, cz))
    }

    /// Called by the scene view coordinator when the user initiates a pan /
    /// pinch / orbit gesture. Breaks the lazy-follow camera so the user has
    /// full control.
    func userInteractedWithCamera() {
        if lazyFollowActive { lazyFollowActive = false }
    }

    /// Project mission event labels (TLI, Lunar Flyby, Saturn Arrival, …) into
    /// the SwiftUI overlay. Each label is only visible within a ±3% window of
    /// the mission duration around its event timestamp (clamped 1–500 h), so
    /// the user sees each milestone for ~2 seconds of screen time at default
    /// auto-speed rather than having them clutter the view for the whole replay.
    private func projectEventLabels(into labels: inout [ScreenLabel],
                                      earthScenePosition: SCNVector3?) {
        guard let id = activeMissionId,
              let mission = missionManager.missions.first(where: { $0.id == id }),
              let positions = missionManager.eventLabelLocalPositions(missionId: id),
              let view = scnView else { return }

        let elapsed = simulatedDate.timeIntervalSince(mission.launchDate) / 3600.0
        // Visibility window — scales with mission duration, clamped to stay readable.
        let window = min(500.0, max(1.0, mission.durationHours * 0.03))

        let origin: SCNVector3 = mission.isGeocentric
            ? (earthScenePosition ?? SCNVector3Zero)
            : SCNVector3Zero

        for (idx, maybePos) in positions.enumerated() {
            guard let localPos = maybePos else { continue }
            let event = mission.events[idx]
            let dt = abs(elapsed - event.t)
            if dt > window { continue }

            // World position = mission group origin + local trajectory sample.
            let world = SCNVector3(origin.x + localPos.x,
                                    origin.y + localPos.y,
                                    origin.z + localPos.z)
            guard let point = projectToSwiftUIPoint(world, in: view) else { continue }

            labels.append(ScreenLabel(
                id: "mission_event_\(id)_\(idx)",
                name: event.name,
                screenPoint: point,
                isMoon: true,      // style as moon/secondary text for now
                priority: 150,     // below planets (100s), above stars (~40s)
                isStar: false
            ))
        }
    }

    // MARK: - Init

    init() {
        self.simulatedDate = Date()
        self.scene = sceneBuilder.buildScene()
        parseLaunchArguments()
        setupBodies()
        setupScene()
        missionManager.initialize(in: scene)

        if let date = overrideDate {
            simulatedDate = date
        }

        // Apply -mission launch arg synchronously so the simulated date, speed,
        // and trajectory visibility are correct before the first frame renders.
        if let missionId = initialMissionId,
           missionManager.missions.contains(where: { $0.id == missionId }) {
            activeMissionId = missionId
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
        if args.contains("-frameLog") {
            frameLogEnabled = true
            print("[frame] logging enabled via -frameLog")
            setbuf(stdout, nil)  // unbuffered so prints show up live
        }
        if args.contains("-innerOnly") { innerOnly = true }
        if args.contains("-showISS") { showISS = true }
        if args.contains("-hideISS") { showISS = false }

        if let idx = args.firstIndex(of: "-mission"), idx + 1 < args.count {
            initialMissionId = args[idx + 1]
        }
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
                // ISS visibility is user-toggled via UserDefaults; apply once here
                // so the node matches the persisted state on launch.
                if moon.id == "iss" { moonNode.isHidden = !showISS }
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
                  let image = PlatformImage(contentsOfFile: path) else { continue }
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
                  let image = PlatformImage(contentsOfFile: path) else { continue }
            geometry.firstMaterial?.diffuse.contents = image
        }
    }

    // MARK: - Animation Loop

    /// Start the frame-tick loop at 30–60 fps using `CADisplayLink` on both
    /// platforms. On macOS the link is acquired via the SCNView (an NSView
    /// subclass) so it syncs to the screen the window is currently on — this
    /// is what eliminates the Timer-based stutter and makes motion feel as
    /// smooth as it does on iPhone.
    func startAnimation() {
        lastUpdateTime = CACurrentMediaTime()
        #if os(iOS)
        let dl = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        dl.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        dl.add(to: .main, forMode: .common)
        self.displayLink = dl
        #else
        // macOS 14+: get the display link from the SCNView so it binds to the
        // display hosting the window. Without a view we can't create one, so
        // defer start until the view connects via `cameraCoordinator.didSet`.
        guard let view = scnView else {
            pendingAnimationStart = true
            return
        }
        let dl = view.displayLink(target: self, selector: #selector(displayLinkFired))
        dl.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        dl.add(to: .main, forMode: .common)
        self.displayLink = dl
        #endif
    }

    func stopAnimation() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Platform-neutral display-link tick. On iOS, called directly by the
    /// `CADisplayLink`; on macOS, called by the SCNView-bound display link
    /// acquired in `startAnimation()`. The underlying API signature happens
    /// to accept a selector that takes no arguments, so we can use the same
    /// neutral selector name on both platforms.
    @objc private func displayLinkFired() {
        advanceOneFrame()
    }

    #if os(macOS)
    /// True if `startAnimation()` was called before the SCNView was available
    /// (typical on macOS where the SwiftUI lifecycle can call onAppear before
    /// `makeNSView` returns). The camera-coordinator `didSet` re-runs start.
    private var pendingAnimationStart: Bool = false
    #endif

    /// Shared per-frame work: accumulate wall-clock delta, advance simulated
    /// time by the current speed multiplier, update node positions, throttle
    /// UI publishing to every third frame. Called by both the iOS display
    /// link and the macOS Timer.
    private func advanceOneFrame() {
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
        let publishT0 = frameLogEnabled ? CACurrentMediaTime() : 0
        if updateUI { currentDate = simulatedDate }
        let publishT1 = frameLogEnabled ? CACurrentMediaTime() : 0

        let positionsT0 = publishT1
        updatePositions(projectLabels: updateUI)
        let positionsT1 = frameLogEnabled ? CACurrentMediaTime() : 0

        if updateUI { syncZoomFromCamera() }

        if frameLogEnabled {
            recordFrameTiming(tickStart: now,
                               tickDelta: dt,
                               publishTime: publishT1 - publishT0,
                               positionsTime: positionsT1 - positionsT0,
                               didUpdateUI: updateUI)
        }
    }

    /// Diagnostic frame-timing recorder. Prints anything anomalous
    /// (dropped frames, fat work ticks) and a once-per-second rolling summary.
    /// Disabled unless `-frameLog` is passed on the command line.
    private func recordFrameTiming(tickStart: Double,
                                     tickDelta: Double,
                                     publishTime: Double,
                                     positionsTime: Double,
                                     didUpdateUI: Bool) {
        frameLogTickCount += 1
        let workTime = publishTime + positionsTime
        frameLogWorstTick = max(frameLogWorstTick, tickDelta)
        frameLogWorstWork = max(frameLogWorstWork, workTime)

        // Anomaly threshold: at 60 Hz a tick should be ~16.7 ms. Anything
        // over 20 ms is a visible drop; over 33 ms is "skipped a frame entirely".
        if tickDelta > 0.020 {
            print(String(format: "[frame] STUTTER t=%.3f  dt=%.1fms  pub=%.2fms  pos=%.2fms  (bodies=%.1f stars=%.1f decon=%.1f mm=%.1f mui=%.1f)%@",
                         tickStart, tickDelta * 1000, publishTime * 1000, positionsTime * 1000,
                         lastPhaseBodies * 1000, lastPhaseStars * 1000,
                         lastPhaseDeconflict * 1000,
                         lastPhaseMissionUpdate * 1000, lastPhaseMissionUI * 1000,
                         didUpdateUI ? "  ui=yes" : ""))
        }
        // Rolling per-second summary so we can see the "normal" baseline.
        if tickStart - frameLogSummaryTime >= 1.0 {
            print(String(format: "[frame] summary  fps~%d  worst-dt=%.1fms  worst-work=%.2fms",
                         frameLogTickCount, frameLogWorstTick * 1000, frameLogWorstWork * 1000))
            frameLogSummaryTime = tickStart
            frameLogTickCount = 0
            frameLogWorstTick = 0
            frameLogWorstWork = 0
        }
    }

    // MARK: - Position Updates

    /// Set to true during zoom slider drag to suppress label rendering.
    var isZooming = false

    /// Recompute all body positions from orbital mechanics for the current simulated date.
    /// Optionally projects 3D positions to screen coordinates for the SwiftUI label overlay.
    // Sub-phase timings captured inside the last `updatePositions` pass so
    // the frame-log summary can attribute slow frames to a specific stage.
    // Only written when `frameLogEnabled` is true; rest of the time these
    // stay at zero.
    private var lastPhaseBodies: Double = 0
    private var lastPhaseStars: Double = 0
    private var lastPhaseDeconflict: Double = 0
    private var lastPhaseMissionUpdate: Double = 0
    private var lastPhaseMissionUI: Double = 0

    private func updatePositions(projectLabels: Bool = true) {
        let cameraNode = scene.rootNode.childNode(withName: "camera", recursively: false)
        let daysSinceJ2000 = OrbitalMechanics.julianDate(from: simulatedDate) - OrbitalMechanics.j2000

        // Earth's heliocentric position (needed by MissionManager to anchor geocentric trajectories).
        var earthHelioPos = SIMD3<Double>.zero
        if let earth = bodies.first(where: { $0.id == "earth" }), let earthElements = earth.orbitalElements {
            earthHelioPos = OrbitalMechanics.heliocentricPosition(elements: earthElements, at: simulatedDate)
        }

        // Rotate the Sun on its axis
        if let sunNode = bodyNodes["sun"] {
            applyRotation(to: sunNode, body: SolarSystemData.sun, daysSinceJ2000: daysSinceJ2000)
        }

        let shouldProjectLabels = projectLabels && !isZooming
        if shouldProjectLabels { refreshProjectionCache() }
        var newLabels: [ScreenLabel] = []
        let t0 = frameLogEnabled ? CACurrentMediaTime() : 0

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
                    // Skip ISS label when the satellite toggle is off — otherwise
                    // we'd render "ISS" floating next to Earth with no mesh under it.
                    if moon.id == "iss" && !showISS { continue }
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

        let t1 = frameLogEnabled ? CACurrentMediaTime() : 0
        if frameLogEnabled { lastPhaseBodies = t1 - t0 }

        // Project named star labels, culling those occluded by planet discs
        if shouldProjectLabels, showStarLabels, let view = scnView {
            // Build a list of body screen positions and approximate screen radii for occlusion
            var bodyScreenPositions: [(point: CGPoint, screenRadius: CGFloat)] = []
            for (_, node) in bodyNodes {
                guard let planetPoint = projectToSwiftUIPoint(node.position, in: view) else { continue }
                let worldRadius = Float((node.geometry as? SCNSphere)?.radius ?? 0.1)
                // 15pt floor so stars right next to a tiny distant planet are
                // still culled — otherwise a far Mercury would let too many
                // star labels crowd around its disc.
                let screenR = max(screenRadius(forWorldRadius: worldRadius, worldPosition: node.position), 15)
                bodyScreenPositions.append((planetPoint, screenR))
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

        let t2 = frameLogEnabled ? CACurrentMediaTime() : 0
        if frameLogEnabled { lastPhaseStars = t2 - t1 }

        // Mission event labels go through the same deconfliction pass as planet / moon
        // labels, so they need to land in `newLabels` before the screenLabels assignment.
        if shouldProjectLabels {
            projectEventLabels(into: &newLabels, earthScenePosition: bodyNodes["earth"]?.position)
        }

        if shouldProjectLabels {
            screenLabels = deconflictLabels(newLabels)
        } else if isZooming && !screenLabels.isEmpty {
            screenLabels = []
        }

        let t3 = frameLogEnabled ? CACurrentMediaTime() : 0
        if frameLogEnabled { lastPhaseDeconflict = t3 - t2 }

        // Update mission manager (trajectories, markers, moonOrbit/moonLanding phases).
        missionManager.update(simulatedDate: simulatedDate,
                               earthHelioPos: earthHelioPos,
                               cameraNode: cameraNode)

        // Lazy-follow mission camera (geocentric only). Runs every frame so the
        // target tracks Earth's drift smoothly; skipped when the user has taken control.
        stepLazyFollowCamera()

        let t4 = frameLogEnabled ? CACurrentMediaTime() : 0
        if frameLogEnabled { lastPhaseMissionUpdate = t4 - t3 }

        // Mission UI state: telemetry, timeline slider, event banner, end-of-mission speed reset.
        if projectLabels {
            updateMissionUIState()
        }
        if frameLogEnabled { lastPhaseMissionUI = CACurrentMediaTime() - t4 }
    }

    // MARK: - Mission UI state

    /// Refresh telemetry, timeline elapsed hours, event banners, and end-of-mission
    /// auto-speed-reset. Throttled to every 3rd frame (same cadence as label projection)
    /// to avoid publishing unchanged values at 60 Hz.
    private func updateMissionUIState() {
        guard let id = activeMissionId,
              let mission = missionManager.missions.first(where: { $0.id == id }) else {
            if missionTelemetry != nil { missionTelemetry = nil }
            return
        }

        // Timeline elapsed hours — skip while user is scrubbing so the slider
        // doesn't jitter as the view model publishes an old value mid-drag.
        let elapsed = simulatedDate.timeIntervalSince(mission.launchDate) / 3600.0
        if !timelineScrubbing {
            missionElapsedHours = max(0, min(mission.durationHours, elapsed))
        }

        // Telemetry (MET, distance, speed) — nil after end-of-mission splashdown.
        missionTelemetry = missionManager.telemetry(missionId: id, simulatedDate: simulatedDate)

        // Fire event banners when the simulation first crosses an event timestamp.
        if let triggered = missionManager.checkEventTrigger(simulatedDate: simulatedDate) {
            let banner = MissionEventBanner(
                name: triggered.event.name,
                detail: triggered.event.detail,
                missionName: triggered.mission.name,
                missionColor: triggered.mission.vehicles.first(where: { $0.primary })?.color
                    ?? MissionData.defaultColor
            )
            currentEventBanner = banner
            scheduleBannerDismiss()
        }

        // End-of-mission speed reset: first time we cross durationHours with
        // timeScale > 1, snap back to real-time so the simulation stops racing
        // after splashdown / arrival.
        if missionEndSpeedResetArmed, elapsed > mission.durationHours, timeScale > 1 {
            timeScale = 1
            missionEndSpeedResetArmed = false
        }
        if elapsed < mission.durationHours {
            missionEndSpeedResetArmed = true
        }
    }

    /// Cancel the previous banner-dismiss timer and schedule a fresh one so the
    /// 4-second window resets whenever a new event fires.
    private func scheduleBannerDismiss() {
        eventBannerDismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.currentEventBanner = nil
        }
        eventBannerDismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
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
        let t0 = frameLogEnabled ? CACurrentMediaTime() : 0
        guard let point = projectToSwiftUIPoint(pos, in: view) else { return nil }
        if frameLogEnabled {
            let dt = CACurrentMediaTime() - t0
            if dt > 0.005 {  // slower than 5ms — log it
                print(String(format: "[frame]  slow projectLabel %@ (%.1fms)", name, dt * 1000))
            }
        }

        // Offset the label upward so it sits above the body rather than
        // overlapping the sphere. Jupiter / the Sun are much larger than a
        // fixed 16 pt margin at close zoom, so the offset has to scale with
        // the body's on-screen radius — otherwise the label disappears into
        // the middle of the disc whenever you fly in.
        let worldRadius = Float((node?.geometry as? SCNSphere)?.radius ?? 0)
        let screenR = screenRadius(forWorldRadius: worldRadius, worldPosition: pos)
        // Minimum 8 pt covers the stars-and-ISS case where the node has no
        // SCNSphere geometry (zero radius) but we still want a readable gap.
        let offsetY = max(8, screenR + 4)
        let placed = CGPoint(x: point.x, y: point.y - offsetY)

        let bounds = view.bounds
        // Allow 50pt bleed outside visible bounds so labels don't pop in/out abruptly
        guard placed.x > -50 && placed.x < bounds.width + 50 &&
              placed.y > -50 && placed.y < bounds.height + 50 else { return nil }
        return ScreenLabel(id: id, name: name, screenPoint: placed, isMoon: isMoon,
                           priority: priority, isStar: isStar)
    }

    /// On-screen radius (points) of a sphere of given world radius at a
    /// given world position, using the cached view × projection matrix.
    /// Correctly accounts for the camera's FOV and the current viewport
    /// size — a sphere of world radius `r` at post-projection depth `w`
    /// spans `2 * r * pixelsPerUnit / w` points vertically on screen.
    private func screenRadius(forWorldRadius r: Float, worldPosition: SCNVector3) -> CGFloat {
        guard r > 0 else { return 0 }
        let world = simd_float4(Float(worldPosition.x), Float(worldPosition.y), Float(worldPosition.z), 1)
        let clip = cachedViewProjection * world
        let w = max(abs(clip.w), 0.001)
        return CGFloat(r * cachedPixelsPerUnit / w)
    }

    /// View × projection matrix captured once per frame and reused for every
    /// label projection. Computed from the camera's world transform and
    /// projection transform via SIMD; avoids the per-call overhead of
    /// `SCNView.projectPoint`. See `projectToSwiftUIPoint(...)` for why.
    private var cachedViewProjection: simd_float4x4 = matrix_identity_float4x4
    private var cachedViewportSize: CGSize = .zero

    /// Pixels-per-world-unit scaling factor at `clip.w == 1`. A world-space
    /// sphere of radius `r` at post-projection depth `w` has an on-screen
    /// radius of `r * cachedPixelsPerUnit / w` points. Derived from the
    /// projection matrix's vertical scale × (viewport height / 2) — the same
    /// formula a correct `projectPoint` implementation would use internally.
    private var cachedPixelsPerUnit: Float = 100

    /// Refresh the cached view × projection matrix + viewport size. Call once
    /// at the top of each frame before projecting labels. Matrix capture is
    /// free in SIMD — the cost of `SCNView.projectPoint` on the per-label
    /// call path was *render-thread synchronisation*, not the maths itself.
    ///
    /// Builds the projection matrix from camera FOV + current viewport aspect
    /// rather than reading `camera.projectionTransform` directly. On macOS the
    /// latter was producing a matrix whose [0][0] aspect term didn't match the
    /// live window size, causing labels to drift horizontally (especially
    /// noticeable on widescreen displays). Constructing from first principles
    /// is a handful of lines, matches SceneKit's output on iOS, and guarantees
    /// the aspect always tracks the current view bounds.
    private func refreshProjectionCache() {
        guard let view = scnView,
              let cameraNode = view.pointOfView,
              let camera = cameraNode.camera else { return }
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        // `simdWorldTransform` returns `simd_float4x4` on both iOS and macOS.
        let viewMatrix = simd_inverse(cameraNode.simdWorldTransform)

        // Build the perspective projection matrix. SCNCamera's `fieldOfView`
        // is in degrees; its `projectionDirection` determines whether that
        // angle is measured horizontally or vertically across the viewport.
        // `.automatic` — the default — uses the longer viewport dimension.
        let fovRad = Float(camera.fieldOfView) * .pi / 180
        let aspect = Float(size.width / size.height)
        let zNear = Float(camera.zNear)
        let zFar = Float(camera.zFar)
        let f = 1 / tan(fovRad / 2)

        // `SCNCameraProjectionDirection` only has `.horizontal` and
        // `.vertical` — no `.automatic` case. Defaults vary by platform:
        // macOS defaults to `.horizontal`, iOS to `.vertical`.
        let fovIsHorizontal = (camera.projectionDirection == .horizontal)

        // Column-major matrix: [column0, column1, column2, column3].
        // For horizontal fov:  [0][0] = f,         [1][1] = f * aspect
        // For vertical fov:    [0][0] = f / aspect, [1][1] = f
        let xScale = fovIsHorizontal ? f : (f / aspect)
        let yScale = fovIsHorizontal ? (f * aspect) : f
        let zRange = zFar - zNear
        let projection = simd_float4x4(
            simd_float4(xScale, 0, 0, 0),
            simd_float4(0, yScale, 0, 0),
            simd_float4(0, 0, -(zFar + zNear) / zRange, -1),
            simd_float4(0, 0, -2 * zFar * zNear / zRange, 0)
        )

        cachedViewProjection = projection * viewMatrix
        cachedViewportSize = size
        // `yScale * (height / 2)` is the "pixels per world unit at depth 1"
        // factor. For horizontal FOV: yScale = f * aspect, so yScale * height
        // / 2 = f * width / 2. For vertical FOV: yScale = f, giving f * height
        // / 2. Both yield the same pixels-per-unit at a given camera distance,
        // as they must for the sphere to render as a circle on screen.
        cachedPixelsPerUnit = yScale * Float(size.height) * 0.5
    }

    /// Project a 3D world point to a SwiftUI-space CGPoint (top-left origin)
    /// using the cached view × projection matrix, with no SceneKit sync.
    ///
    /// Why bypass `SCNView.projectPoint`? On macOS during heavy scene activity
    /// (e.g. 10,000× playback with the ISS orbiting Earth rapidly), each
    /// `projectPoint` call blocks on the render thread for a full 16.7 ms
    /// frame while SceneKit flushes pending transform updates. With 26 bodies
    /// to project that's ~400 ms of work crammed into one frame, visible as
    /// the ~1 Hz stutter the user reported. Manual matrix projection is pure
    /// CPU maths — about 100 ns per point, no sync.
    private func projectToSwiftUIPoint(_ worldPoint: SCNVector3, in view: SCNView) -> CGPoint? {
        let world = simd_float4(Float(worldPoint.x), Float(worldPoint.y), Float(worldPoint.z), 1)
        let clip = cachedViewProjection * world
        // Behind camera (Metal convention: clip.w ≤ 0 is behind; we also
        // guard z ∉ [-w, w] which would place the point outside the frustum).
        guard clip.w > 0 else { return nil }
        let ndcX = clip.x / clip.w
        let ndcY = clip.y / clip.w
        let ndcZ = clip.z / clip.w
        guard ndcZ < 1 else { return nil }
        // Map NDC (-1…1) to view coordinates with SwiftUI top-left-origin Y.
        // NDC Y is up, screen Y is down — so `(1 - ndcY) * 0.5` puts y=0 at
        // the top of the view on both iOS and macOS. No per-platform flip
        // needed since we're computing the coord ourselves.
        let x = (Float(ndcX) + 1) * 0.5 * Float(cachedViewportSize.width)
        let y = (1 - Float(ndcY)) * 0.5 * Float(cachedViewportSize.height)
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    /// Widen an SCNMatrix4 to `simd_float4x4`. `SCNMatrix4` component type is
    /// Float on iOS and CGFloat on macOS; `Float(...)` handles both.
    private static func toSimd4x4(_ m: SCNMatrix4) -> simd_float4x4 {
        return simd_float4x4(
            simd_float4(Float(m.m11), Float(m.m12), Float(m.m13), Float(m.m14)),
            simd_float4(Float(m.m21), Float(m.m22), Float(m.m23), Float(m.m24)),
            simd_float4(Float(m.m31), Float(m.m32), Float(m.m33), Float(m.m34)),
            simd_float4(Float(m.m41), Float(m.m42), Float(m.m43), Float(m.m44))
        )
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
            let moonSceneDist = Float(SceneBuilder.moonSceneDistance(
                parentSceneRadius: Double(parentRadius),
                moonSemiMajorKm: me.semiMajorAxisKm,
                parentRadiusKm: body.physical.radiusKm))
            let moonRadius = SceneBuilder.sceneRadius(km: moon.physical.radiusKm, type: .moon)
            maxDist = max(maxDist, moonSceneDist + moonRadius)
        }

        return maxDist
    }

    /// Move the camera to frame a specific scene node, accounting for its moon
    /// system extent and the current viewport aspect ratio, and angle the
    /// camera ~31° off the Sun direction for a two-thirds-lit view.
    ///
    /// Multipliers match the web version: moon-hosting planets use a tight
    /// 0.8× base (the moon system extent is already large under the 0.6
    /// compression, so a small multiplier gives a frame-filling shot); moonless
    /// bodies use 6.0× so Mercury / Venus / the Sun don't appear as dots.
    /// Portrait viewports scale the multiplier by the aspect ratio so the
    /// constraining dimension (width) doesn't cut off the system.
    func focusCamera(on node: SCNNode) {
        guard let body = selectedBody ?? bodies.first(where: { bodyNodes[$0.id] === node }) else {
            return
        }
        let planetRadius = SceneBuilder.sceneRadius(km: body.physical.radiusKm, type: body.type)
        let moonExtent = moonSystemRadius(for: body)
        let extent = max(planetRadius, moonExtent)

        let hasMoons = !body.moons.isEmpty
        let aspect = viewportAspectRatio()
        let portraitFactor = Float(min(aspect, 1.0))
        let baseMultiplier: Float = hasMoons ? 0.8 : 6.0
        let multiplier = baseMultiplier * (0.5 + 0.5 * portraitFactor)
        let cameraDistance = max(extent * multiplier, 0.5)

        // Sun-side azimuth: camera sits between the Sun (at the scene origin)
        // and the target, offset by 0.55 rad (~31°) so the terminator is on
        // the far side of the target and we see the lit two-thirds. Earth's
        // scene x/z is used because SceneKit's y axis is ecliptic z.
        let pos = node.position
        // Cast through Float so the arithmetic matches the `azimuth: Float`
        // parameter on both iOS (where `.x` is already Float) and macOS
        // (where it's CGFloat).
        let sunsideAzimuth: Float = atan2(Float(-pos.x), Float(-pos.z)) + 0.55
        cameraCoordinator?.setCamera(target: pos, distance: cameraDistance,
                                       azimuth: sunsideAzimuth, elevation: 0.3)
    }

    /// Current SCNView aspect ratio, or 1.0 during tests / before the view connects.
    private func viewportAspectRatio() -> Double {
        guard let view = scnView, view.bounds.width > 0, view.bounds.height > 0 else {
            return 1.0
        }
        return Double(view.bounds.width / view.bounds.height)
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
