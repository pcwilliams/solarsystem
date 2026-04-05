// CelestialBody.swift
// SolarSystem
//
// Core data model for all celestial bodies: stars, planets, dwarf planets,
// and moons. Each body carries its physical properties (radius, colour,
// ring parameters), rotation model (IAU axial tilt and spin), and
// references to its orbital elements and child moons.

import Foundation
import SceneKit

// MARK: - Body Type

/// Classification of celestial bodies, used for rendering and scaling decisions.
enum BodyType: String, CaseIterable {
    case star
    case planet
    case dwarfPlanet
    case moon
}

// MARK: - Physical Properties

/// Observable physical characteristics used for rendering.
struct PhysicalProperties {
    let radiusKm: Double
    let color: SCNVector3        // RGB 0-1 base colour (fallback when no texture)
    let emissive: Bool           // True for the Sun (self-illuminating)
    let hasRings: Bool           // True for Saturn
    let ringInnerRadiusKm: Double
    let ringOuterRadiusKm: Double

    init(radiusKm: Double, color: SCNVector3, emissive: Bool = false,
         hasRings: Bool = false, ringInnerRadiusKm: Double = 0, ringOuterRadiusKm: Double = 0) {
        self.radiusKm = radiusKm
        self.color = color
        self.emissive = emissive
        self.hasRings = hasRings
        self.ringInnerRadiusKm = ringInnerRadiusKm
        self.ringOuterRadiusKm = ringOuterRadiusKm
    }
}

// MARK: - Rotation Properties

/// IAU rotation model: axial tilt (obliquity), sidereal period, and prime meridian at epoch.
struct RotationProperties {
    let periodHours: Double      // Sidereal rotation period (hours, negative = retrograde)
    let obliquity: Double        // Axial tilt to orbital plane (degrees)
    let w0: Double               // Prime meridian angle at J2000.0 (degrees)
    let tidallyLocked: Bool      // If true, rotation period matches orbital period

    init(periodHours: Double, obliquity: Double, w0: Double = 0, tidallyLocked: Bool = false) {
        self.periodHours = periodHours
        self.obliquity = obliquity
        self.w0 = w0
        self.tidallyLocked = tidallyLocked
    }

    /// Compute the current rotation angle (radians) at a given time since J2000.0.
    /// Accounts for retrograde rotation (negative period).
    func rotationAngle(daysSinceJ2000: Double) -> Float {
        let periodDays = abs(periodHours) / 24.0
        guard periodDays > 0 else { return 0 }
        let rotations = daysSinceJ2000 / periodDays
        let sign = periodHours < 0 ? -1.0 : 1.0
        return Float((w0.degreesToRadians + sign * rotations * 2.0 * .pi)
            .truncatingRemainder(dividingBy: 2.0 * .pi))
    }
}

// MARK: - Celestial Body

/// A single celestial body with all data needed for simulation and display.
struct CelestialBody: Identifiable {
    let id: String
    let name: String
    let type: BodyType
    let orbitalElements: OrbitalElements?       // Heliocentric orbit (planets)
    let moonElements: MoonOrbitalElements?      // Parent-relative orbit (moons)
    let physical: PhysicalProperties
    let rotation: RotationProperties?
    var moons: [CelestialBody]
    var position: SIMD3<Double> = .zero          // Current heliocentric ecliptic position (AU)

    init(name: String, type: BodyType, orbitalElements: OrbitalElements? = nil,
         moonElements: MoonOrbitalElements? = nil, physical: PhysicalProperties,
         rotation: RotationProperties? = nil, moons: [CelestialBody] = []) {
        self.id = name.lowercased().replacingOccurrences(of: " ", with: "_")
        self.name = name
        self.type = type
        self.orbitalElements = orbitalElements
        self.moonElements = moonElements
        self.physical = physical
        self.rotation = rotation
        self.moons = moons
    }
}
