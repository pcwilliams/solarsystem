// MissionManager.swift
// SolarSystem
//
// Owns the SceneKit nodes for all space-mission trajectories, vehicle markers,
// telemetry computation, and timed event detection. Ported from the
// MissionManager class in ../solarsystem-web/js/missions.js.
//
// Pipeline:
//   initialize()         — build per-mission SCNNode groups, resolve anchors,
//                          sample CatmullRom curves, create trajectory line +
//                          marker geometry.
//   update(date:...)     — each frame, reposition the mission group at Earth
//                          (geocentric) or origin (heliocentric), interpolate
//                          each vehicle, compute moonOrbit/moonLanding poses,
//                          scale markers to camera distance.
//   getTelemetry(...)     — MET / distance / speed for the primary vehicle.
//   checkEventTrigger()   — returns one event when simulation time first
//                          crosses its timestamp; resets on time-reversal.

import Foundation
import SceneKit
import simd

// MARK: - Telemetry

/// A single telemetry snapshot for the currently active mission. Re-computed
/// each UI update tick from the primary vehicle's waypoints + a finite-difference
/// speed estimate. Consumed by the telemetry HUD; the manager itself only
/// produces the numerics — formatting belongs in the view layer.
struct MissionTelemetry {
    /// Mission display name (e.g. "Apollo 11"). Used as the panel heading.
    let missionName: String
    /// Mission Elapsed Time in hours since launch. Always ≥ 0 for active missions.
    let metHours: Double
    /// Distance from the reference body (Earth for geocentric, Sun for
    /// heliocentric) in kilometres. The UI may reformat into thousands-of-km.
    let distanceKm: Double
    /// Heliocentric distance in AU. Nil for geocentric missions — the UI uses
    /// this as the switch between km and AU display formats.
    let distanceAU: Double?
    /// Instantaneous speed in km/s, computed by finite difference across a
    /// small time step (0.01 h geocentric, 1 h heliocentric).
    let speedKmS: Double
    /// True for interplanetary missions; flips the distance formatter to AU.
    let isHeliocentric: Bool
}

// MARK: - Mission Manager

@MainActor
final class MissionManager {

    // MARK: Constants

    /// Event-banner hold window (hours): once an event triggers, it won't
    /// re-trigger while simulation time is still within this many hours of it.
    /// Sized so a slow rewind doesn't replay the same banner, and a fast
    /// forward doesn't miss an event because the display-link skipped past.
    private static let eventWindowHours: Double = 2.0

    // MARK: Public state

    /// Toggle all mission trajectories on/off (preserves selected mission).
    var visible: Bool = true {
        didSet { updateVisibility() }
    }

    /// Only the selected mission's group is shown. Setting this nils resets
    /// event triggers for the newly selected mission so banners replay from
    /// launch.
    var selectedMissionId: String? {
        didSet {
            if let id = selectedMissionId { resetEventTriggers(missionId: id) }
            updateVisibility()
        }
    }

    /// All missions known to the manager — read-only external access.
    let missions: [Mission]

    // MARK: Private state

    private weak var scene: SCNScene?

    /// Per-mission scene graph root. Mission trajectories and markers hang off this group.
    private var missionGroups: [String: SCNNode] = [:]

    /// Per-vehicle rendering and runtime data, keyed by `"<missionId>/<vehicleId>"`.
    private var vehicleData: [String: VehicleRuntime] = [:]

    /// Cached bounds for camera framing — invalidated on selection change.
    private var boundsCache: [String: MissionBounds] = [:]

    /// Most-recently fired event index per mission (so each event fires once).
    private var lastTriggeredEvent: [String: Int] = [:]

    // MARK: - Init

    init(missions: [Mission] = MissionData.all) {
        self.missions = missions
    }

    // MARK: - Scene Construction

    /// Build the scene graph for every mission in the bundle. Called once from
    /// the view model after `SceneBuilder.buildScene()` completes. Each mission
    /// gets its own `SCNNode` child of the root, visibility-gated so only the
    /// selected mission renders at any time.
    ///
    /// Safe to call from the main actor only — the SceneKit API it drives
    /// (adding child nodes, constructing geometries) is main-actor-bound.
    func initialize(in scene: SCNScene) {
        self.scene = scene
        for mission in missions {
            buildMission(mission)
        }
        updateVisibility()
    }

    /// Create the root `SCNNode` group for one mission and build each of its
    /// vehicles beneath it. Geocentric missions also precompute the Moon-aligned
    /// rotation matrix once up-front — all vehicles share it.
    private func buildMission(_ mission: Mission) {
        guard let scene = scene else { return }
        let group = SCNNode()
        group.name = "mission_\(mission.id)"
        scene.rootNode.addChildNode(group)
        missionGroups[mission.id] = group

        // For geocentric missions, waypoints are defined in a Moon-aligned
        // frame (X toward the Moon at flyby time). Compute that direction once
        // from `OrbitalMechanics.moonPosition` and cache `(cosA, sinA)` so
        // every waypoint rotates into true ecliptic coordinates with a single
        // 2×2 matrix-vector product. Heliocentric missions skip this — their
        // waypoints are already in ecliptic AU — and leave the matrix at identity.
        var cosA = 1.0, sinA = 0.0
        if mission.isGeocentric, let flyby = mission.flybyTimeHours {
            let flybyDate = mission.launchDate.addingTimeInterval(flyby * 3600)
            let moonPos = OrbitalMechanics.moonPosition(moonElements: SolarSystemData.earthMoon.moonElements!,
                                                         at: flybyDate)
            let angle = atan2(moonPos.y, moonPos.x)
            cosA = cos(angle); sinA = sin(angle)
        }

        for vehicle in mission.vehicles {
            buildVehicle(mission: mission, vehicle: vehicle, group: group, cosA: cosA, sinA: sinA)
        }

        // Initialise the event-trigger cursor so the first event (usually Launch)
        // is eligible to fire once playback reaches its timestamp.
        lastTriggeredEvent[mission.id] = -1
    }

    /// Build the trajectory line and marker geometry for one vehicle, resolve
    /// anchored waypoints against real planet/Moon positions, and stash runtime
    /// state in `vehicleData` for the per-frame update to consume.
    ///
    /// The stages are:
    /// 1. Resolve anchor waypoints (anchorMoon / anchorBody) to real positions.
    /// 2. Rotate geocentric waypoints from Moon-aligned to ecliptic frame.
    /// 3. Optionally expand autoTrajectory="transfer" anchors into a Hohmann arc.
    /// 4. Sample the CatmullRom curve at uniform *time* steps (not arc length).
    /// 5. Convert samples to SceneKit-space points and build the line geometry.
    /// 6. Build the vehicle marker (emissive sphere + additive halo).
    private func buildVehicle(mission: Mission, vehicle: Vehicle, group: SCNNode,
                               cosA: Double, sinA: Double) {
        // Stage 1–2: Resolve anchors and apply the Moon-alignment rotation
        // (heliocentric missions leave the input x/y/z alone).
        var rotated = resolveAndRotateWaypoints(vehicle.waypoints,
                                                 mission: mission,
                                                 cosA: cosA, sinA: sinA)

        // Stage 3: Auto-generate a Hohmann-style transfer arc for e.g.
        // Perseverance, whose raw data is just two anchor points (Earth launch,
        // Mars arrival). Without this, the trajectory would be a straight line.
        if vehicle.autoTrajectory == "transfer", mission.referenceFrame == .heliocentric {
            rotated = MissionManager.generateTransferArc(rotated)
        }

        // Stage 4: Sample the curve at uniform *time* steps. Primary vehicles
        // get 400 samples for a smooth line; non-primary vehicles use a
        // proportional count (`≥40`, `15×N`) since they're typically short-lived
        // stages (SRBs, Saturn V booster) with only 2–3 waypoints anyway.
        let sampleCount = vehicle.primary ? 400 : max(40, rotated.count * 15)
        let samples = sampleTrajectory(waypoints: rotated, count: sampleCount)

        // Stage 5: Convert each sample to scene coords. Geocentric trajectories
        // are Earth-relative (the mission group rides on Earth each frame);
        // heliocentric trajectories use the same log compression as planet
        // positions so they sit correctly inside the solar system overview.
        let scenePoints: [SCNVector3] = samples.map { pt in
            mission.isGeocentric
                ? toLocalGeocentricScene(pt)
                : toHeliocentricScene(pt)
        }

        let line = buildTrajectoryLine(scenePoints: scenePoints, color: vehicle.color, primary: vehicle.primary)
        group.addChildNode(line)

        let marker = buildVehicleMarker(color: vehicle.color, primary: vehicle.primary)
        marker.isHidden = true  // only visible while the vehicle is actually moving
        group.addChildNode(marker)

        // The per-frame update needs the interpolation arrays and lifecycle
        // window. Store both the pre-split times and waypoint points so the
        // interpolator can run without re-extracting fields from `Waypoint`.
        let startTime = vehicle.waypoints.first?.t ?? 0
        let endTime = vehicle.waypoints.last?.t ?? 0
        let times = rotated.map(\.t)
        let points = rotated.map { SIMD3<Double>($0.x, $0.y, $0.z) }

        let runtime = VehicleRuntime(
            waypointPoints: points,
            waypointTimes: times,
            marker: marker,
            line: line,
            startTime: startTime,
            endTime: endTime
        )
        vehicleData["\(mission.id)/\(vehicle.id)"] = runtime
    }

    // MARK: - Per-frame update

    /// Per-frame driver: reposition mission groups, advance vehicle markers,
    /// and scale markers relative to the camera so they stay visible at every
    /// zoom level. Called from `SolarSystemViewModel.updatePositions` every
    /// display-link tick (no throttle — the work is cheap: one trig lookup
    /// per active vehicle plus SCNNode mutations).
    ///
    /// - Parameters:
    ///   - simulatedDate: the current simulated moment. Drives waypoint
    ///     interpolation and moon-phase timing.
    ///   - earthHelioPos: Earth's heliocentric position in AU for this instant.
    ///     Used to reposition geocentric mission groups onto Earth's scene
    ///     location each frame.
    ///   - cameraNode: the active SCNView camera, used for distance-based
    ///     marker scaling. Nil during offscreen tests — marker scaling is skipped.
    func update(simulatedDate: Date, earthHelioPos: SIMD3<Double>, cameraNode: SCNNode?) {
        let earthScenePos = sceneBuilderHeliocentricScene(earthHelioPos)

        for mission in missions {
            guard let group = missionGroups[mission.id] else { continue }

            // Only one mission is visible at a time — the selected one. Hidden
            // missions skip all per-frame work entirely (cheap early-out).
            let isSelected = visible && mission.id == selectedMissionId
            group.isHidden = !isSelected
            if !isSelected { continue }

            // Geocentric missions ride with Earth; heliocentric ones are
            // anchored at the scene origin (the Sun).
            group.position = mission.isGeocentric
                ? earthScenePos
                : SCNVector3Zero

            let elapsedHours = simulatedDate.timeIntervalSince(mission.launchDate) / 3600.0
            let missionActive = elapsedHours >= 0 && elapsedHours <= mission.durationHours

            for vehicle in mission.vehicles {
                let key = "\(mission.id)/\(vehicle.id)"
                guard let data = vehicleData[key] else { continue }

                // Marker is visible only while the vehicle is actively "moving"
                // (between its first and last waypoint); trail is visible for
                // the entire mission duration so the user can see the full path.
                let moving = elapsedHours >= data.startTime && elapsedHours < data.endTime
                data.marker.isHidden = !moving
                data.line.isHidden = !missionActive
                if !moving { continue }

                let markerPos = computeMarkerPosition(mission: mission, vehicle: vehicle,
                                                       data: data, elapsedHours: elapsedHours,
                                                       simulatedDate: simulatedDate)
                data.marker.position = markerPos

                // Keep the marker visible at every zoom level by scaling it
                // proportional to camera distance. Without this, zooming out to
                // overview turns the marker into a sub-pixel dot. Formula
                // mirrors the companion web app: max(0.04, camDist * 0.012).
                if let cameraNode = cameraNode {
                    let worldMarker = SCNVector3(markerPos.x + group.position.x,
                                                  markerPos.y + group.position.y,
                                                  markerPos.z + group.position.z)
                    let camPos = cameraNode.position
                    let dx = camPos.x - worldMarker.x
                    let dy = camPos.y - worldMarker.y
                    let dz = camPos.z - worldMarker.z
                    let camDist = sqrt(dx * dx + dy * dy + dz * dz)
                    let markerScale = max(0.04, camDist * 0.012)
                    data.marker.scale = SCNVector3(markerScale, markerScale, markerScale)
                }
            }
        }
    }

    // MARK: - Trajectory bounds

    /// Axis-aligned bounding box of a geocentric mission's full trajectory,
    /// in Earth-relative scene coordinates (the local frame the trajectory
    /// line is drawn in). The lazy-follow camera uses the returned centre
    /// and radius to frame the trajectory tightly without chasing Earth's
    /// heliocentric drift.
    ///
    /// Returns nil for heliocentric missions — those bypass framing entirely
    /// in favour of the overview camera, because their trajectories span AU
    /// and don't benefit from tight framing.
    func missionBounds(missionId: String) -> MissionBounds? {
        if let cached = boundsCache[missionId] { return cached }
        guard let mission = missions.first(where: { $0.id == missionId }),
              mission.isGeocentric else { return nil }

        var minPt = SIMD3<Double>(.infinity, .infinity, .infinity)
        var maxPt = SIMD3<Double>(-.infinity, -.infinity, -.infinity)
        for (key, data) in vehicleData where key.hasPrefix("\(missionId)/") {
            for pt in data.waypointPoints {
                // Each rotated waypoint → local scene space used by the trajectory line.
                let scene = toLocalGeocentricScene(pt)
                let v = SIMD3<Double>(Double(scene.x), Double(scene.y), Double(scene.z))
                minPt = SIMD3(min(minPt.x, v.x), min(minPt.y, v.y), min(minPt.z, v.z))
                maxPt = SIMD3(max(maxPt.x, v.x), max(maxPt.y, v.y), max(maxPt.z, v.z))
            }
        }
        guard minPt.x.isFinite else { return nil }

        let center = (minPt + maxPt) * 0.5
        let halfSize = (maxPt - minPt) * 0.5
        let bounds = MissionBounds(
            localCenter: SCNVector3(Float(center.x), Float(center.y), Float(center.z)),
            localRadius: Float(simd_length(halfSize))
        )
        boundsCache[missionId] = bounds
        return bounds
    }

    /// Pre-computed world positions of event labels along the primary
    /// vehicle's trajectory. Nil where an event has `showLabel == false`.
    /// Positions are local to the mission group (Earth-relative for geocentric
    /// missions); callers add the group origin each frame for the world position.
    func eventLabelLocalPositions(missionId: String) -> [SCNVector3?]? {
        guard let mission = missions.first(where: { $0.id == missionId }) else { return nil }
        guard let primary = mission.vehicles.first(where: { $0.primary }),
              let data = vehicleData["\(missionId)/\(primary.id)"] else { return nil }
        return mission.events.map { event -> SCNVector3? in
            guard event.showLabel else { return nil }
            let pt = CatmullRom.sampleAtTime(points: data.waypointPoints,
                                               times: data.waypointTimes,
                                               time: event.t)
            return mission.isGeocentric ? toLocalGeocentricScene(pt) : toHeliocentricScene(pt)
        }
    }

    // MARK: - Public Queries

    /// Compute MET / distance / speed for the primary vehicle. Returns nil if
    /// no primary vehicle is defined or the mission is outside its duration.
    func telemetry(missionId: String, simulatedDate: Date) -> MissionTelemetry? {
        guard let mission = missions.first(where: { $0.id == missionId }) else { return nil }
        let elapsed = simulatedDate.timeIntervalSince(mission.launchDate) / 3600.0
        guard elapsed >= 0, elapsed <= mission.durationHours else { return nil }
        guard let primary = mission.vehicles.first(where: { $0.primary }) else { return nil }
        guard let data = vehicleData["\(missionId)/\(primary.id)"] else { return nil }

        let pos = CatmullRom.sampleAtTime(points: data.waypointPoints, times: data.waypointTimes, time: elapsed)
        let isHelio = mission.referenceFrame == .heliocentric
        let distKm = isHelio ? simd_length(pos) * OrbitalMechanics.kmPerAU : simd_length(pos)
        let distAU: Double? = isHelio ? simd_length(pos) : nil

        // Finite-difference speed — larger time step for AU-scale trajectories.
        let dt = isHelio ? 1.0 : 0.01
        let pos2 = CatmullRom.sampleAtTime(points: data.waypointPoints, times: data.waypointTimes,
                                             time: elapsed + dt)
        let deltaKm = isHelio
            ? simd_length(pos2 - pos) * OrbitalMechanics.kmPerAU
            : simd_length(pos2 - pos)
        let speedKmS = deltaKm / (dt * 3600)

        return MissionTelemetry(missionName: mission.name, metHours: elapsed,
                                  distanceKm: distKm, distanceAU: distAU,
                                  speedKmS: speedKmS, isHeliocentric: isHelio)
    }

    /// Return the next mission event to fire at the given simulation time, or
    /// nil. Each event fires exactly once per forward time crossing; a large
    /// time reversal (user scrub) resets the fired-event cursor.
    func checkEventTrigger(simulatedDate: Date) -> (mission: Mission, event: MissionEvent)? {
        for mission in missions {
            let elapsed = simulatedDate.timeIntervalSince(mission.launchDate) / 3600.0

            // Time rewound past the last-fired event → allow replay on next forward crossing.
            // Evaluated unconditionally so jumps far before launch still reset the cursor.
            let lastIdx = lastTriggeredEvent[mission.id] ?? -1
            if lastIdx >= 0, elapsed < mission.events[lastIdx].t - 1 {
                lastTriggeredEvent[mission.id] = -1
            }

            if elapsed < -1 || elapsed > mission.durationHours + 1 { continue }

            let cursor = lastTriggeredEvent[mission.id] ?? -1
            for (idx, event) in mission.events.enumerated() {
                if idx <= cursor { continue }
                if elapsed >= event.t && elapsed < event.t + Self.eventWindowHours {
                    lastTriggeredEvent[mission.id] = idx
                    return (mission, event)
                }
            }
        }
        return nil
    }

    func resetEventTriggers(missionId: String) {
        lastTriggeredEvent[missionId] = -1
    }

    // MARK: - Transfer arc generation

    /// Expand heliocentric anchor waypoints into a smooth elliptical arc between
    /// consecutive anchor points. Prograde (counter-clockwise) with a small
    /// outward bulge so the trajectory looks like a Hohmann transfer instead of
    /// a straight line. Matches the `_generateTransferArc` helper in
    /// `../solarsystem-web/js/missions.js`.
    nonisolated static func generateTransferArc(_ anchors: [Waypoint]) -> [Waypoint] {
        guard anchors.count >= 2 else { return anchors }
        var result: [Waypoint] = []
        let segmentSamples = 12

        for seg in 0..<(anchors.count - 1) {
            let wp0 = anchors[seg]
            let wp1 = anchors[seg + 1]

            let r0 = sqrt(wp0.x * wp0.x + wp0.y * wp0.y)
            let r1 = sqrt(wp1.x * wp1.x + wp1.y * wp1.y)
            let a0 = atan2(wp0.y, wp0.x)
            let a1 = atan2(wp1.y, wp1.x)

            // Prograde sweep — ensure positive rotation. `> 1.5π` catches the
            // case where atan2 wrapped to a nearly-full retrograde loop.
            var sweep = a1 - a0
            if sweep <= 0 { sweep += 2 * .pi }
            if sweep > .pi * 1.5 { sweep -= 2 * .pi }

            // Elliptical transfer: linear radius with a sine-bump so the mid
            // point bulges outward (outward transfer) or slightly inward (inward).
            let bulge = r1 > r0 ? 0.05 : -0.03

            for i in 0...segmentSamples {
                if i == segmentSamples && seg < anchors.count - 2 { continue }  // avoid dupes
                let frac = Double(i) / Double(segmentSamples)
                let t = wp0.t + (wp1.t - wp0.t) * frac
                let angle = a0 + sweep * frac
                let r = r0 + (r1 - r0) * frac + bulge * (r0 + r1) * sin(.pi * frac)
                let z = wp0.z + (wp1.z - wp0.z) * frac
                result.append(Waypoint(t: t, x: r * cos(angle), y: r * sin(angle), z: z))
            }
        }
        return result
    }

    // MARK: - Waypoint Resolution

    /// Resolve `anchorBody` / `anchorMoon` waypoints and rotate geocentric
    /// Moon-aligned coordinates into ecliptic frame. Public for tests.
    nonisolated static func resolveAndRotateWaypointsForTesting(_ waypoints: [Waypoint],
                                                                  mission: Mission,
                                                                  cosA: Double, sinA: Double) -> [Waypoint] {
        return resolve(waypoints, mission: mission, cosA: cosA, sinA: sinA)
    }

    nonisolated private func resolveAndRotateWaypoints(_ waypoints: [Waypoint],
                                                         mission: Mission,
                                                         cosA: Double, sinA: Double) -> [Waypoint] {
        return MissionManager.resolve(waypoints, mission: mission, cosA: cosA, sinA: sinA)
    }

    nonisolated private static func resolve(_ waypoints: [Waypoint], mission: Mission,
                                              cosA: Double, sinA: Double) -> [Waypoint] {
        let isHelio = mission.referenceFrame == .heliocentric

        return waypoints.map { wp -> Waypoint in
            if isHelio {
                // Heliocentric: anchorBody snaps to a planet's ecliptic position at time t.
                if let anchor = wp.anchorBody,
                   let planet = SolarSystemData.allPlanets.first(where: { $0.id == anchor }),
                   let elements = planet.orbitalElements {
                    let date = mission.launchDate.addingTimeInterval(wp.t * 3600)
                    let pos = OrbitalMechanics.heliocentricPosition(elements: elements, at: date)
                    return Waypoint(t: wp.t, x: pos.x, y: pos.y, z: pos.z,
                                     anchorMoon: wp.anchorMoon, anchorBody: wp.anchorBody)
                }
                return wp
            }

            // Geocentric: rotate from Moon-aligned to ecliptic frame.
            let rx = wp.x * cosA - wp.y * sinA
            let ry = wp.x * sinA + wp.y * cosA
            var out = Waypoint(t: wp.t, x: rx, y: ry, z: wp.z,
                                anchorMoon: wp.anchorMoon, anchorBody: wp.anchorBody)

            // anchorMoon: resolve to the Moon's actual ecliptic position at time t.
            // Use the Moon's semi-major axis distance (not the varying actual distance)
            // to match how the Moon mesh is rendered.
            if wp.anchorMoon, let moonElements = SolarSystemData.earthMoon.moonElements {
                let date = mission.launchDate.addingTimeInterval(wp.t * 3600)
                let mp = OrbitalMechanics.moonPosition(moonElements: moonElements, at: date)
                let distAU = simd_length(mp)
                if distAU > 0 {
                    let smaScale = moonElements.semiMajorAxisKm / (distAU * OrbitalMechanics.kmPerAU)
                    out.x = mp.x * OrbitalMechanics.kmPerAU * smaScale
                    out.y = mp.y * OrbitalMechanics.kmPerAU * smaScale
                    out.z = mp.z * OrbitalMechanics.kmPerAU * smaScale
                }
            }
            return out
        }
    }

    // MARK: - Trajectory Sampling

    /// Uniform-time sampling of a CatmullRom curve through the given waypoints,
    /// producing `count + 1` points spanning the first and last waypoint timestamps.
    private func sampleTrajectory(waypoints: [Waypoint], count: Int) -> [SIMD3<Double>] {
        guard !waypoints.isEmpty else { return [] }
        let points = waypoints.map { SIMD3<Double>($0.x, $0.y, $0.z) }
        let times = waypoints.map(\.t)
        let startT = times.first!
        let endT = times.last!

        var result: [SIMD3<Double>] = []
        result.reserveCapacity(count + 1)
        for i in 0...count {
            let t = startT + (endT - startT) * Double(i) / Double(count)
            result.append(CatmullRom.sampleAtTime(points: points, times: times, time: t))
        }
        return result
    }

    // MARK: - Marker position (runtime phases)

    /// Compute the scene-space position for a vehicle marker at the given
    /// moment. Priority order:
    ///
    /// 1. **Moon-relative phase** (geocentric vehicles with `moonOrbit`,
    ///    `moonLanding`, or `moonOrbitReturn`): handled by
    ///    `moonRelativeMarkerPosition` which keeps the marker glued to the
    ///    rendered Moon mesh. This avoids the real 45 km LEM descent being
    ///    invisible after distance compression.
    /// 2. **Default**: interpolate the CatmullRom trajectory at `elapsedHours`
    ///    and convert to scene coords using the mission's reference frame.
    private func computeMarkerPosition(mission: Mission, vehicle: Vehicle,
                                         data: VehicleRuntime, elapsedHours: Double,
                                         simulatedDate: Date) -> SCNVector3 {
        if mission.isGeocentric,
           (vehicle.moonOrbit != nil || vehicle.moonLanding != nil || vehicle.moonOrbitReturn != nil) {
            if let pos = moonRelativeMarkerPosition(vehicle: vehicle, elapsedHours: elapsedHours,
                                                     simulatedDate: simulatedDate) {
                return pos
            }
            // Fall through if the vehicle's moon-phase windows don't cover
            // `elapsedHours` (e.g. coasting between TLI and LOI).
        }

        let eclipticPt = CatmullRom.sampleAtTime(points: data.waypointPoints,
                                                   times: data.waypointTimes,
                                                   time: elapsedHours)
        return mission.isGeocentric
            ? toLocalGeocentricScene(eclipticPt)
            : toHeliocentricScene(eclipticPt)
    }

    /// Compute a vehicle's position when it's in a moonOrbit / moonLanding /
    /// moonOrbitReturn phase. Returns nil if none of those windows apply.
    private func moonRelativeMarkerPosition(vehicle: Vehicle, elapsedHours: Double,
                                              simulatedDate: Date) -> SCNVector3? {
        guard let moonElements = SolarSystemData.earthMoon.moonElements else { return nil }

        // Moon's actual ecliptic direction at this instant, scaled to semi-major axis
        // (so the lunar-orbit marker lands on the rendered Moon sphere, not its
        // eccentricity-shifted true position).
        let mp = OrbitalMechanics.moonPosition(moonElements: moonElements, at: simulatedDate)
        let len = simd_length(mp)
        let moonDir = len > 0 ? mp / len : SIMD3<Double>(1, 0, 0)
        let smaOffsetKm = moonDir * moonElements.semiMajorAxisKm
        let moonScenePos = toLocalGeocentricScene(smaOffsetKm)

        let mo = vehicle.moonOrbit
        let ml = vehicle.moonLanding
        let mr = vehicle.moonOrbitReturn

        // Primary moonOrbit window (Columbia orbit, or Eagle pre-undock).
        if let phase = mo, elapsedHours >= phase.startTime, elapsedHours <= phase.endTime {
            // If a landing follows immediately, snap to Moon centre in the last millisecond
            // so the lerp to landing starts from the correct position.
            if ml != nil, elapsedHours > phase.endTime - 0.001 {
                return moonScenePos
            }
            return orbitAroundMoon(phase: phase, tHours: elapsedHours,
                                    moonDir: moonDir, moonScenePos: moonScenePos,
                                    moonElements: moonElements)
        }

        // Landing window: snap to Moon scene position for the duration.
        if let landing = ml, elapsedHours >= landing.startTime, elapsedHours <= landing.endTime {
            return moonScenePos
        }

        // Post-landing return orbit window (Eagle ascent stage).
        if let phase = mr, elapsedHours >= phase.startTime, elapsedHours <= phase.endTime {
            if elapsedHours < phase.startTime + 0.001 {
                return moonScenePos
            }
            return orbitAroundMoon(phase: phase, tHours: elapsedHours,
                                    moonDir: moonDir, moonScenePos: moonScenePos,
                                    moonElements: moonElements)
        }

        return nil
    }

    /// Compute a vehicle's position on a circular orbit around the Moon's
    /// actual scene position. The orbit plane is perpendicular to the
    /// Earth-Moon line (tangent × moonDir), so the vehicle visually circles
    /// the Moon from the camera's vantage point.
    ///
    /// Extracted from `moonRelativeMarkerPosition` as a standalone method —
    /// as an inline closure the macOS Swift compiler fails to type-check
    /// within its timeout.
    private func orbitAroundMoon(phase: MoonOrbitPhase,
                                   tHours: Double,
                                   moonDir: SIMD3<Double>,
                                   moonScenePos: SCNVector3,
                                   moonElements: MoonOrbitalElements) -> SCNVector3 {
        let angle = (tHours - phase.startTime) / phase.periodHours * 2.0 * .pi

        // Compressed orbit radius: take the scene distance of (sma + altitude)
        // and subtract the scene distance of sma, so radius shrinks
        // proportionally with the pow(0.6) compression.
        let outerOffset = moonDir * (moonElements.semiMajorAxisKm + phase.radiusKm)
        let outerScene = toLocalGeocentricScene(outerOffset)
        let outerVec = SIMD3<Double>(Double(outerScene.x), Double(outerScene.y), Double(outerScene.z))
        let moonVec = SIMD3<Double>(Double(moonScenePos.x), Double(moonScenePos.y), Double(moonScenePos.z))
        let orbitRadius = simd_length(outerVec) - simd_length(moonVec)

        // Tangent and normal vectors define the orbit plane.
        let up = SIMD3<Double>(0, 1, 0)
        var tangent = simd_cross(moonDir, up)
        let tLen = simd_length(tangent)
        if tLen < 1e-6 {
            tangent = SIMD3<Double>(1, 0, 0)
        } else {
            tangent /= tLen
        }
        let normal = simd_normalize(simd_cross(tangent, moonDir))

        let cosA = cos(angle) * orbitRadius
        let sinA = sin(angle) * orbitRadius
        let offset = tangent * cosA + normal * sinA
        return moonScenePos.adding(offset.x, offset.y, offset.z)
    }

    // MARK: - Coordinate transforms

    /// Convert an Earth-centred km offset into local mission-group scene coordinates.
    /// Uses the same compression constants as moon positioning so trajectory lines
    /// stay proportional to the moons they pass. The result is an offset from the
    /// mission group (which is positioned at Earth's scene location each frame).
    ///
    /// Returns zero for offsets under 10 km — at those scales the compression
    /// collapses to effectively zero anyway, and skipping the `pow` avoids any
    /// `log(0)`-adjacent weirdness for launch-pad waypoints.
    private func toLocalGeocentricScene(_ eclipticKm: SIMD3<Double>) -> SCNVector3 {
        let dist = simd_length(eclipticKm)
        if dist < 10 { return SCNVector3Zero }

        // Reference Earth's real radius from the bodies database so we only keep
        // the value in one place. Using the rendered scene radius as the base
        // means the compression agrees with how the Earth mesh itself sizes.
        let earthRadiusKm = SolarSystemData.earth.physical.radiusKm
        let earthSceneR = Double(SceneBuilder.sceneRadius(km: earthRadiusKm, type: .planet))
        let compressed = earthSceneR * pow(dist / earthRadiusKm,
                                             SceneBuilder.moonDistExponent)
            * SceneBuilder.moonDistScale

        let dir = eclipticKm / dist
        // Same ecliptic→scene axis swap as `SceneBuilder.updateNodePosition`:
        //   scene x = ecliptic x
        //   scene y = ecliptic z   (SceneKit uses Y-up; ecliptic uses Z-up)
        //   scene z = -ecliptic y  (right-handed to left-handed flip)
        return SCNVector3(Float(dir.x * compressed),
                          Float(dir.z * compressed),
                          Float(-dir.y * compressed))
    }

    /// Convert an AU ecliptic position into scene coordinates (same compression
    /// SceneBuilder uses for planets).
    private func toHeliocentricScene(_ au: SIMD3<Double>) -> SCNVector3 {
        return sceneBuilderHeliocentricScene(au)
    }

    /// Same as `SceneBuilder.updateNodePosition` but returns an SCNVector3 for an
    /// arbitrary heliocentric AU point. Inlined here to avoid a main-actor hop.
    private func sceneBuilderHeliocentricScene(_ au: SIMD3<Double>) -> SCNVector3 {
        let dist = simd_length(au)
        let sceneDist = SceneBuilder.sceneDistance(au: dist)
        let scale = dist > 0 ? sceneDist / dist : 0
        let scaled = au * scale
        return SCNVector3(Float(scaled.x), Float(scaled.z), Float(-scaled.y))
    }

    // MARK: - Scene node construction

    /// Construct the `SCNNode` holding one vehicle's trajectory line.
    ///
    /// The line is a connected polyline of `SCNGeometryElement` with
    /// `primitiveType == .line`, carrying per-vertex colours via the `.color`
    /// semantic. The material uses `.constant` lighting so the vertex colours
    /// pass through unaffected and `writesToDepthBuffer = false` so the
    /// trajectory doesn't occlude markers drawn on top of it.
    ///
    /// The per-vertex gradient emphasises progress:
    ///   - **0–5 %** fades from white into vehicle colour at launch
    ///   - **5–45 %** dim (0.9× brightness) during outbound coast
    ///   - **45–55 %** full brightness at the flyby / landing / arrival point
    ///   - **55–100 %** gradually dims to convey the return leg
    ///
    /// Non-primary vehicles (SRBs, Saturn V booster) use a uniform 0.85×
    /// brightness — no need for a progress gradient on a 2-waypoint stub.
    private func buildTrajectoryLine(scenePoints: [SCNVector3], color: SIMD3<Float>, primary: Bool) -> SCNNode {
        var positions: [SCNVector3] = []
        var colors: [SCNVector3] = []
        positions.reserveCapacity(scenePoints.count)
        colors.reserveCapacity(scenePoints.count)

        let n = scenePoints.count
        for (i, p) in scenePoints.enumerated() {
            positions.append(p)
            let frac = Float(i) / Float(max(n - 1, 1))
            let c: SIMD3<Float>
            if primary {
                if frac < 0.05 {
                    // Launch white-out: lerp from white (1,1,1) to vehicle colour.
                    let t = frac / 0.05
                    c = SIMD3<Float>(1.0 - t * (1.0 - color.x),
                                      1.0 - t * (1.0 - color.y),
                                      1.0 - t * (1.0 - color.z))
                } else if frac < 0.45 {
                    c = color * 0.9
                } else if frac < 0.55 {
                    c = color
                } else {
                    // Dim linearly from 0.9× to ~0.675× over the return leg.
                    c = color * (0.9 - (frac - 0.55) * 0.5)
                }
            } else {
                c = color * 0.85
            }
            colors.append(SCNVector3(c.x, c.y, c.z))
        }

        let vertexSource = SCNGeometrySource(vertices: positions)

        // SceneKit needs raw bytes for the `.color` semantic; `Data(bytes:count:)`
        // over the array's buffer pointer is the lowest-overhead way to do this.
        let colorData = colors.withUnsafeBufferPointer { buf in
            Data(bytes: buf.baseAddress!, count: buf.count * MemoryLayout<SCNVector3>.stride)
        }
        let colorSource = SCNGeometrySource(data: colorData,
                                              semantic: .color,
                                              vectorCount: colors.count,
                                              usesFloatComponents: true,
                                              componentsPerVector: 3,
                                              bytesPerComponent: MemoryLayout<Float>.size,
                                              dataOffset: 0,
                                              dataStride: MemoryLayout<SCNVector3>.stride)

        // The `.line` primitive type takes *pairs* of indices, not a line-strip
        // array, so we need `[0,1, 1,2, 2,3, …]` for a connected polyline.
        var indices: [Int32] = []
        indices.reserveCapacity(max(0, (n - 1) * 2))
        for i in 0..<max(0, n - 1) {
            indices.append(Int32(i))
            indices.append(Int32(i + 1))
        }
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: indexData, primitiveType: .line,
                                           primitiveCount: max(0, n - 1),
                                           bytesPerIndex: MemoryLayout<Int32>.size)

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = PlatformColor.white
        material.lightingModel = .constant
        material.isDoubleSided = true
        // Neither read nor write depth: the trajectory is a reference overlay,
        // not a physical object — the full arc should be visible even when
        // portions pass behind the Moon / planets. Without this the behind-Moon
        // section of a lunar flyby is occluded by the Moon mesh and the
        // trajectory visibly terminates at the lunar horizon.
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        material.transparency = CGFloat(primary ? 0.5 : 0.35)
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "trajectory_line"
        node.renderingOrder = 100   // render after planets so the line sits on top
        return node
    }

    private func buildVehicleMarker(color: SIMD3<Float>, primary: Bool) -> SCNNode {
        // Two nested emissive spheres: a small bright core and a larger faint
        // halo. Their scale is updated each frame so they stay visible from
        // overview to close zoom.
        let core = SCNSphere(radius: primary ? 0.5 : 0.3)
        core.segmentCount = 16
        let coreMat = SCNMaterial()
        coreMat.diffuse.contents = PlatformColor(red: CGFloat(color.x), green: CGFloat(color.y),
                                             blue: CGFloat(color.z), alpha: 1.0)
        coreMat.emission.contents = coreMat.diffuse.contents
        coreMat.lightingModel = .constant
        coreMat.writesToDepthBuffer = false
        coreMat.readsFromDepthBuffer = false
        core.materials = [coreMat]
        let coreNode = SCNNode(geometry: core)
        coreNode.renderingOrder = 200

        let halo = SCNSphere(radius: primary ? 1.2 : 0.7)
        halo.segmentCount = 16
        let haloMat = SCNMaterial()
        haloMat.diffuse.contents = PlatformColor.clear
        haloMat.emission.contents = PlatformColor(red: CGFloat(color.x), green: CGFloat(color.y),
                                              blue: CGFloat(color.z), alpha: 0.25)
        haloMat.lightingModel = .constant
        haloMat.writesToDepthBuffer = false
        haloMat.readsFromDepthBuffer = false
        haloMat.blendMode = .add
        halo.materials = [haloMat]
        let haloNode = SCNNode(geometry: halo)
        haloNode.renderingOrder = 199

        let group = SCNNode()
        group.addChildNode(haloNode)
        group.addChildNode(coreNode)

        // The per-frame camera-distance scaling targets a base marker size of
        // 0.04 (primary) or 0.025 (non-primary) world units; apply a base scale
        // here so the geometry resolves to that range.
        let base: Float = primary ? 0.04 : 0.025
        group.scale = SCNVector3(base, base, base)
        return group
    }

    // MARK: - Visibility

    private func updateVisibility() {
        for (id, group) in missionGroups {
            group.isHidden = !(visible && id == selectedMissionId)
        }
    }
}

// MARK: - Runtime vehicle state

/// Per-vehicle state kept alive for the lifetime of the mission manager.
///
/// The per-frame update reads the interpolation arrays and the two SCNNodes
/// from here; `Mission` and `Vehicle` aren't stored because the manager
/// receives them by parameter on every call — storing them would just duplicate
/// data already on the stack.
private struct VehicleRuntime {
    /// Resolved + rotated waypoint positions. Units are km (geocentric) or AU
    /// (heliocentric), matching the mission's reference frame.
    let waypointPoints: [SIMD3<Double>]
    /// Strictly-increasing timestamps aligned to `waypointPoints`, in hours
    /// since launch. Used for time-parameterised CatmullRom sampling.
    let waypointTimes: [Double]
    /// The marker (emissive sphere + halo) node shown at the current position
    /// while the vehicle is "moving". Hidden before first waypoint / after last.
    let marker: SCNNode
    /// The pre-computed trajectory polyline. Shown for the full mission
    /// duration regardless of whether the vehicle is currently moving.
    let line: SCNNode
    /// Time of the vehicle's first waypoint (its visual "birth" moment).
    let startTime: Double
    /// Time of the vehicle's last waypoint (its visual "death" moment).
    let endTime: Double
}

// MARK: - Bounds

/// Framing dimensions for a geocentric mission's trajectory in Earth-local
/// scene coordinates. Consumed by the lazy-follow mission camera to compute
/// the initial snap target and fit-to-viewport distance.
struct MissionBounds {
    /// Trajectory centre, relative to Earth's scene position.
    let localCenter: SCNVector3
    /// Bounding-sphere radius in scene units — drives the fit-to-viewport distance.
    let localRadius: Float
}
