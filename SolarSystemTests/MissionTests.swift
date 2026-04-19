// MissionTests.swift
// SolarSystemTests
//
// Verifies MissionManager behaviours that are independent of SceneKit:
// Moon-aligned waypoint rotation, anchorMoon snapping, auto-speed preset
// selection, and mission data integrity for Apollo 11.

import Foundation
import Testing
import simd
@testable import SolarSystem

struct MissionTests {

    // MARK: - Waypoint rotation

    @Test func geocentricWaypointsRotateByFlybyAngle() {
        // Rotation with a 90° Moon angle swaps +X into +Y and +Y into -X.
        let mission = Mission(
            id: "test", name: "Test", subtitle: "",
            launchDate: Date(), durationHours: 24, flybyTimeHours: 10,
            referenceFrame: .geocentric, events: [],
            vehicles: []
        )
        let wps: [Waypoint] = [
            Waypoint(t: 0, x: 100, y: 0, z: 0),
            Waypoint(t: 10, x: 0, y: 100, z: 0),
        ]
        let rotated = MissionManager.resolveAndRotateWaypointsForTesting(wps, mission: mission,
                                                                          cosA: 0, sinA: 1)
        // (100, 0) rotated by +90° -> (0, 100)
        #expect(abs(rotated[0].x - 0) < 1e-6)
        #expect(abs(rotated[0].y - 100) < 1e-6)
        // (0, 100) rotated by +90° -> (-100, 0)
        #expect(abs(rotated[1].x - (-100)) < 1e-6)
        #expect(abs(rotated[1].y - 0) < 1e-6)
        #expect(rotated[0].z == 0)
    }

    @Test func heliocentricWaypointsAreNotRotated() {
        let mission = Mission(
            id: "test", name: "Test", subtitle: "",
            launchDate: Date(), durationHours: 24, flybyTimeHours: nil,
            referenceFrame: .heliocentric, events: [],
            vehicles: []
        )
        let wps = [Waypoint(t: 0, x: 1.5, y: -2.0, z: 0.1)]
        let rotated = MissionManager.resolveAndRotateWaypointsForTesting(wps, mission: mission,
                                                                          cosA: 0, sinA: 1)
        #expect(rotated[0].x == 1.5)
        #expect(rotated[0].y == -2.0)
        #expect(rotated[0].z == 0.1)
    }

    @Test func anchorMoonResolvesToMoonSemiMajorAxisDistance() {
        // An anchorMoon waypoint should snap to a distance equal to the Moon's
        // semi-major axis (in km) regardless of its input x/y/z values.
        let launch = Date(timeIntervalSince1970: 0)  // stable reference date
        let mission = Mission(
            id: "test", name: "Test", subtitle: "",
            launchDate: launch, durationHours: 200, flybyTimeHours: 76,
            referenceFrame: .geocentric, events: [],
            vehicles: []
        )
        let wps = [Waypoint(t: 50, x: 999, y: 999, z: 999, anchorMoon: true)]
        let rotated = MissionManager.resolveAndRotateWaypointsForTesting(wps, mission: mission,
                                                                          cosA: 1, sinA: 0)
        let dist = sqrt(rotated[0].x * rotated[0].x + rotated[0].y * rotated[0].y + rotated[0].z * rotated[0].z)
        let sma = SolarSystemData.earthMoon.moonElements!.semiMajorAxisKm
        #expect(abs(dist - sma) / sma < 0.01, "expected ~\(sma) km, got \(dist) km")
    }

    // MARK: - Auto time scale

    @Test func autoTimeScaleSnapsToNearestPreset() {
        let short = Mission(id: "s", name: "", subtitle: "",
                            launchDate: Date(), durationHours: 200, flybyTimeHours: 100,
                            referenceFrame: .geocentric, events: [], vehicles: [])
        // 200h * 80 = 16,000 → nearest preset is 10,000.
        #expect(short.autoTimeScale() == 10_000)

        let long = Mission(id: "l", name: "", subtitle: "",
                           launchDate: Date(), durationHours: 28_200, flybyTimeHours: nil,
                           referenceFrame: .heliocentric, events: [], vehicles: [])
        // 28,200 * 80 = 2,256,000 → nearest preset is 1,000,000.
        #expect(long.autoTimeScale() == 1_000_000)
    }

    // MARK: - Bundled JSON

    @Test func allElevenMissionsLoadFromBundle() {
        // Exercises the full JSON → DTO → domain pipeline for every mission.
        let all = MissionData.all
        #expect(all.count == 11, "expected 11 bundled missions, got \(all.count)")

        // Known mission ids must all be present — guards against regressions in
        // the export script or JSON trimming.
        let expected: Set<String> = [
            "artemis2", "apollo8", "apollo11", "apollo13",
            "cassini", "voyager1", "voyager2",
            "perseverance", "newhorizons", "parker", "bepicolombo",
        ]
        #expect(Set(all.map(\.id)) == expected)

        // Every mission should have at least one vehicle, one event, and a
        // positive duration. Primary vehicle must exist.
        for m in all {
            #expect(m.durationHours > 0, "\(m.id) has zero duration")
            #expect(!m.vehicles.isEmpty, "\(m.id) has no vehicles")
            #expect(!m.events.isEmpty, "\(m.id) has no events")
            #expect(m.vehicles.contains(where: { $0.primary }), "\(m.id) has no primary vehicle")
        }
    }

    @Test func heliocentricMissionsUseHeliocentricFrame() {
        // Cassini, Voyagers, Perseverance, New Horizons, Parker, BepiColombo
        // all operate in the heliocentric frame.
        let helio: Set<String> = [
            "cassini", "voyager1", "voyager2",
            "perseverance", "newhorizons", "parker", "bepicolombo",
        ]
        for m in MissionData.all where helio.contains(m.id) {
            #expect(m.referenceFrame == .heliocentric, "\(m.id) should be heliocentric")
        }
    }

    @Test func perseveranceHasTransferAutoTrajectory() {
        // Perseverance uses the Hohmann-transfer generator to expand its
        // anchor points into a full arc.
        let m = MissionData.all.first { $0.id == "perseverance" }!
        let primary = m.vehicles.first { $0.primary }!
        #expect(primary.autoTrajectory == "transfer")
    }

    @Test func generateTransferArcProducesMonotonicTimeline() {
        // Two anchor points at t=0 and t=100 should expand into a 13-point
        // segment with timestamps increasing from 0 to 100.
        let anchors = [
            Waypoint(t: 0,   x: 1.0, y: 0.0, z: 0.0),
            Waypoint(t: 100, x: 0.0, y: 1.5, z: 0.0),
        ]
        let arc = MissionManager.generateTransferArc(anchors)
        #expect(arc.count == 13)
        for i in 1..<arc.count {
            #expect(arc[i].t >= arc[i - 1].t)
        }
        #expect(arc.first!.t == 0)
        #expect(arc.last!.t == 100)
    }

    // MARK: - Apollo 11 data integrity

    @Test func apollo11MissionDataIsWellFormed() {
        let m = MissionData.all.first { $0.id == "apollo11" }!
        #expect(m.id == "apollo11")
        #expect(m.referenceFrame == .geocentric)
        #expect(m.vehicles.count == 3)

        // Columbia is primary and carries the moonOrbit phase.
        let columbia = m.vehicles.first { $0.id == "csm_columbia" }!
        #expect(columbia.primary == true)
        #expect(columbia.moonOrbit?.startTime == 75.8)
        #expect(columbia.moonOrbit?.endTime == 135.6)

        // Eagle has all three phases (moonOrbit, moonLanding, moonOrbitReturn).
        let eagle = m.vehicles.first { $0.id == "lm_eagle" }!
        #expect(eagle.moonOrbit != nil)
        #expect(eagle.moonLanding != nil)
        #expect(eagle.moonOrbitReturn != nil)

        // Waypoint timestamps must be strictly increasing within each vehicle
        // — a prerequisite for time-parameterised CatmullRom sampling.
        for v in m.vehicles {
            for i in 1..<v.waypoints.count {
                #expect(v.waypoints[i].t > v.waypoints[i - 1].t,
                        "\(v.id) waypoint \(i) timestamp is not increasing")
            }
        }
    }

    // MARK: - Event lifecycle (via MissionManager)

    @Test @MainActor func eventFiresOnceAndResetsOnTimeReversal() {
        let manager = MissionManager()
        let mission = manager.missions.first!

        // Before launch: nothing should fire.
        let before = manager.checkEventTrigger(
            simulatedDate: mission.launchDate.addingTimeInterval(-10 * 3600))
        #expect(before == nil)

        // At launch: fires the first event.
        let first = manager.checkEventTrigger(simulatedDate: mission.launchDate)
        #expect(first?.event.name == "Launch")

        // Immediately after: no re-fire of the same event.
        let second = manager.checkEventTrigger(
            simulatedDate: mission.launchDate.addingTimeInterval(60))
        #expect(second == nil || second?.event.name != "Launch")

        // Jump backwards: reset allows Launch to fire again.
        _ = manager.checkEventTrigger(
            simulatedDate: mission.launchDate.addingTimeInterval(-2 * 3600))
        let replay = manager.checkEventTrigger(simulatedDate: mission.launchDate)
        #expect(replay?.event.name == "Launch")
    }
}
