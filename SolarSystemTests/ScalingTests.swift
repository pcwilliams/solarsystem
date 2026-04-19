// ScalingTests.swift
// SolarSystemTests
//
// Verifies the centralised scaling formulae: heliocentric log distance,
// body sqrt radius, and moon-distance compression (pow(realRatio, 0.6) * 1.5).
// These constants are shared between moon positioning and mission trajectory
// rendering, so they must stay consistent.

import Foundation
import Testing
@testable import SolarSystem

struct ScalingTests {

    // MARK: - Distance compression (heliocentric)

    @Test func sceneDistanceIsMonotonic() {
        let mercury = SceneBuilder.sceneDistance(au: 0.387)
        let earth = SceneBuilder.sceneDistance(au: 1.0)
        let jupiter = SceneBuilder.sceneDistance(au: 5.203)
        let neptune = SceneBuilder.sceneDistance(au: 30.07)

        #expect(mercury < earth)
        #expect(earth < jupiter)
        #expect(jupiter < neptune)
    }

    @Test func sceneDistanceIsCompressedLogarithmically() {
        // Neptune is 30x farther than Earth but should compress to < 4x.
        let earth = SceneBuilder.sceneDistance(au: 1.0)
        let neptune = SceneBuilder.sceneDistance(au: 30.07)
        #expect(neptune / earth < 4.0)
        #expect(neptune / earth > 3.0)
    }

    // MARK: - Moon distance compression

    @Test func moonDistExponentIsSixTenths() {
        // Web app uses 0.6; the iOS app must match so moon proportions and
        // mission trajectory compression behave identically across ports.
        #expect(SceneBuilder.moonDistExponent == 0.6)
        #expect(SceneBuilder.moonDistScale == 1.5)
    }

    @Test func moonSceneDistanceAppliesCompressionFormula() {
        // Earth's Moon: 384,400 km / 6,371 km = ~60.3 real ratios.
        // pow(60.3, 0.6) * 1.5 ~= 17.6x parent radius.
        let parentSceneRadius = 1.0
        let dist = SceneBuilder.moonSceneDistance(
            parentSceneRadius: parentSceneRadius,
            moonSemiMajorKm: 384_400,
            parentRadiusKm: 6_371)
        #expect(dist > 17.0 && dist < 18.5)
    }

    @Test func moonSceneDistanceIsMonotonicInSemiMajor() {
        // Within a system, farther moons should always be compressed to a larger scene distance.
        let io = SceneBuilder.moonSceneDistance(parentSceneRadius: 1.0, moonSemiMajorKm: 421_700, parentRadiusKm: 69_911)
        let europa = SceneBuilder.moonSceneDistance(parentSceneRadius: 1.0, moonSemiMajorKm: 671_034, parentRadiusKm: 69_911)
        let ganymede = SceneBuilder.moonSceneDistance(parentSceneRadius: 1.0, moonSemiMajorKm: 1_070_412, parentRadiusKm: 69_911)
        let callisto = SceneBuilder.moonSceneDistance(parentSceneRadius: 1.0, moonSemiMajorKm: 1_882_709, parentRadiusKm: 69_911)
        #expect(io < europa)
        #expect(europa < ganymede)
        #expect(ganymede < callisto)
    }

    @Test func moonSceneDistanceHandlesZeroParentRadius() {
        let dist = SceneBuilder.moonSceneDistance(
            parentSceneRadius: 1.0,
            moonSemiMajorKm: 384_400,
            parentRadiusKm: 0)
        #expect(dist == 0)
    }

    // MARK: - Scene radius

    @Test func sceneRadiusPlanetIsClampedAndSqrtScaled() {
        // Jupiter (69,911 km) hits the 0.35 upper clamp; Mercury (2,440 km) stays below.
        let jupiter = SceneBuilder.sceneRadius(km: 69_911, type: .planet)
        let mercury = SceneBuilder.sceneRadius(km: 2_440, type: .planet)
        #expect(jupiter > mercury)
        #expect(jupiter <= 0.35)
        #expect(mercury >= 0.03)
    }

    @Test func sceneRadiusMoonFloorIsRespected() {
        // Deimos (6 km) would sqrt-scale to ~0.003 — the moon floor (0.012) should apply.
        let deimos = SceneBuilder.sceneRadius(km: 6, type: .moon)
        #expect(deimos == SceneBuilder.minimumBodyRadius)
    }

    // MARK: - ISS orbital parameters

    @Test func issIsRegisteredAsEarthMoon() {
        // The Satellites menu relies on the ISS being present in Earth's moon
        // array with a stable id — these are the fields the UI and label
        // projection read.
        let earth = SolarSystemData.allPlanets.first { $0.id == "earth" }
        let iss = earth?.moons.first { $0.id == "iss" }
        #expect(iss != nil, "ISS must be registered as a child of Earth")
        #expect(iss?.name == "ISS")
        #expect(iss?.type == .moon)
    }

    @Test func issOrbitalElementsMatchRealValues() {
        let iss = SolarSystemData.iss
        let el = iss.moonElements!
        // 6,779 km = 6,371 Earth radius + 408 km ISS altitude.
        #expect(el.semiMajorAxisKm == 6779)
        // Real ISS orbital period is ~92.7 minutes = 0.06436 days.
        #expect(abs(el.period - 0.06436) < 1e-4)
        // 51.6° inclination ≈ Baikonur-launchable orbit.
        #expect(el.inclination == 51.6)
    }
}
