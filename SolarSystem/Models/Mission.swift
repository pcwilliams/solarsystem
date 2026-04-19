// Mission.swift
// SolarSystem
//
// Data model for space missions: trajectory waypoints, timed events, and
// multiple independently-rendered vehicles per mission. Geocentric missions
// (Artemis, Apollo) use a Moon-aligned waypoint frame. Heliocentric missions
// (Voyager, Cassini) use AU-scale ecliptic coordinates with optional anchor
// snapping to real planet positions at initialisation.
//
// Ported from js/missions.js in the companion web app. See MISSIONS.md in
// ../solarsystem-web for the reference specification.

import Foundation
import simd

// MARK: - Reference Frame

/// Which coordinate system a mission's raw waypoints are expressed in.
///
/// - `geocentric`: km, Earth-centred, rotated into a Moon-aligned frame at
///   init. Used by lunar missions (Apollo, Artemis). The mission group rides
///   on Earth's scene position every frame.
/// - `heliocentric`: AU, Sun-centred ecliptic. Used by interplanetary missions
///   (Voyager, Cassini, New Horizons, …). The mission group sits at the origin.
enum MissionReferenceFrame {
    case geocentric
    case heliocentric
}

// MARK: - Waypoint

/// A single position sample along a vehicle's trajectory.
///
/// For geocentric missions: x/y/z are km in a Moon-aligned frame (X toward Moon
/// at flyby time, Y perpendicular in ecliptic plane, Z out of ecliptic). At
/// initialisation the waypoint is rotated to align with the Moon's actual
/// direction at flyby time.
///
/// For heliocentric missions: x/y/z are AU in ecliptic coordinates.
///
/// `anchorMoon` (geocentric only) snaps this waypoint to the Moon's actual
/// ecliptic position at time `t`, so the trajectory line meets the rendered
/// Moon regardless of date precision.
///
/// `anchorBody` (heliocentric only) snaps this waypoint to the named planet's
/// heliocentric position at time `t`. Used for gravity-assist flybys.
struct Waypoint {
    let t: Double            // Hours from mission launch
    var x: Double            // km (geocentric) or AU (heliocentric)
    var y: Double
    var z: Double
    let anchorMoon: Bool
    let anchorBody: String?

    init(t: Double, x: Double, y: Double, z: Double,
         anchorMoon: Bool = false, anchorBody: String? = nil) {
        self.t = t
        self.x = x
        self.y = y
        self.z = z
        self.anchorMoon = anchorMoon
        self.anchorBody = anchorBody
    }
}

// MARK: - Moon Orbit / Landing Phases

/// Runtime-computed circular lunar orbit phase for a vehicle.
///
/// During the active time window, the vehicle's marker is placed on a circle
/// around the Moon's *actual* scene position at the current moment, with the
/// orbit plane perpendicular to the Earth-Moon line. This is used instead of
/// waypoint interpolation so the vehicle stays glued to the rendered Moon mesh
/// even as the Moon drifts along its ecliptic orbit.
///
/// `periodHours` is typically ~2× the real orbital period (e.g. 4 h vs the
/// real ~2 h) for visual comfort at high replay speeds — a real orbit would
/// blur at 10,000×. `radiusKm` is the real altitude above the Moon's centre;
/// the renderer compresses this using the same formula as moon positioning
/// so the scene orbit shrinks proportionally.
struct MoonOrbitPhase {
    /// Start of the orbit window (hours from mission launch).
    let startTime: Double
    /// End of the orbit window (hours from mission launch).
    let endTime: Double
    /// Orbital period in hours, used to compute the cos/sin phase each frame.
    let periodHours: Double
    /// Orbital radius above the Moon's centre, in real kilometres. Compressed
    /// into scene units via `SceneBuilder.moonDistExponent`/`moonDistScale`.
    let radiusKm: Double
}

/// Runtime lunar-landing phase.
///
/// During `[startTime, endTime]` the vehicle's marker snaps to the Moon's
/// current scene position — representing touchdown, surface EVA, and liftoff
/// all at once. At trajectory scale the real 45 km descent is invisible, so
/// modelling the descent via snap-to-Moon rather than waypoint interpolation
/// is the only way to get a visually sensible result.
struct MoonLandingPhase {
    /// Start of the landing window (hours from mission launch).
    let startTime: Double
    /// End of the landing window — liftoff time.
    let endTime: Double
}

// MARK: - Vehicle

/// A single tracked spacecraft (or stage) within a mission. Each vehicle has
/// its own trajectory line, marker, and lifecycle — vehicles appear and
/// disappear at their first and last waypoint times.
struct Vehicle {
    let id: String
    let name: String
    let color: SIMD3<Float>      // RGB 0–1, used for line gradient and marker
    let primary: Bool             // true → camera tracks this vehicle, telemetry reads from it
    let waypoints: [Waypoint]
    let autoTrajectory: String?   // "transfer" → expand anchor waypoints into an elliptical arc
    let moonOrbit: MoonOrbitPhase?
    let moonLanding: MoonLandingPhase?
    let moonOrbitReturn: MoonOrbitPhase?

    init(id: String, name: String, color: SIMD3<Float>, primary: Bool,
         waypoints: [Waypoint],
         autoTrajectory: String? = nil,
         moonOrbit: MoonOrbitPhase? = nil,
         moonLanding: MoonLandingPhase? = nil,
         moonOrbitReturn: MoonOrbitPhase? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.primary = primary
        self.waypoints = waypoints
        self.autoTrajectory = autoTrajectory
        self.moonOrbit = moonOrbit
        self.moonLanding = moonLanding
        self.moonOrbitReturn = moonOrbitReturn
    }
}

// MARK: - Event

/// A timed mission event. Drives the event banner, the 3D event label, and
/// the optional event marker along the trajectory.
struct MissionEvent {
    let t: Double            // hours from launch
    let name: String
    let detail: String
    let showLabel: Bool       // false for events that pile up on Earth (Launch, MECO, etc.)

    init(t: Double, name: String, detail: String, showLabel: Bool = true) {
        self.t = t
        self.name = name
        self.detail = detail
        self.showLabel = showLabel
    }
}

// MARK: - Mission

/// A space mission: metadata, reference frame, timed events, and one or more
/// vehicles. See APOLLO_11 / VOYAGER_1 / CASSINI in `../solarsystem-web/js/missions.js`
/// for reference examples of each combination of features.
struct Mission {
    /// Short identifier used by `-mission <id>` and JSON lookup (e.g. "apollo11").
    let id: String
    /// Human-readable name shown in the menu and telemetry HUD ("Apollo 11").
    let name: String
    /// One-line tag used under the name in the menu (e.g. "First Moon landing").
    let subtitle: String
    /// Real calendar instant of T+0.
    let launchDate: Date
    /// Total mission duration in hours. Drives the timeline slider upper bound
    /// and the end-of-mission auto-speed reset.
    let durationHours: Double
    /// Hours from launch to the defining flyby / closest approach. Used by
    /// geocentric missions to compute the Moon-aligned waypoint rotation at
    /// init; ignored for heliocentric missions.
    let flybyTimeHours: Double?
    /// Reference frame the waypoints are defined in.
    let referenceFrame: MissionReferenceFrame
    /// Timed events (Launch, TLI, Lunar Flyby, …) that trigger banners and labels.
    let events: [MissionEvent]
    /// One or more vehicles, each with its own trajectory line and marker.
    let vehicles: [Vehicle]

    /// Convenience: true when the reference frame is geocentric. Used by the
    /// manager / view model to branch between Earth-relative and Sun-relative
    /// rendering paths.
    var isGeocentric: Bool { referenceFrame == .geocentric }

    /// Compute the auto-replay speed for this mission, targeting ~45 seconds
    /// of screen time from launch to end. Snapped to the nearest preset in
    /// `{100, 1k, 10k, 100k, 1M, 10M}` (in log-distance) so the speed menu
    /// stays readable and the user can manually nudge up or down by powers of
    /// ten.
    ///
    /// Rationale for the 45-second target: the user just picked the mission
    /// from the menu; they want to *see* what happens, not wait ten minutes
    /// through a coasting phase. A 200-hour Apollo 11 plays through in ~45 s
    /// at 10,000×; a 28,000-hour Voyager 1 at 1,000,000×; both feel the same.
    func autoTimeScale() -> Double {
        let ideal = durationHours * 80.0   // × 80 → ~45 s at 3,600-s-per-hour
        let presets: [Double] = [100, 1000, 10_000, 100_000, 1_000_000, 10_000_000]
        var best = presets[0]
        var bestDelta = abs(log10(ideal) - log10(best))
        for p in presets.dropFirst() {
            let delta = abs(log10(ideal) - log10(p))
            if delta < bestDelta {
                best = p
                bestDelta = delta
            }
        }
        return best
    }
}
