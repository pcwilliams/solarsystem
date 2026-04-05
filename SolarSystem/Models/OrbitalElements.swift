// OrbitalElements.swift
// SolarSystem
//
// Keplerian orbital element data structures for planets and moons.
// OrbitalElements stores the six classical elements at J2000.0 epoch
// plus their rates of change per Julian century, allowing computation
// of osculating elements at any date. MoonOrbitalElements stores
// simplified circular/elliptical orbit parameters for natural satellites.

import Foundation

// MARK: - Planetary Orbital Elements

/// Keplerian orbital elements at J2000.0 with linear rates of change.
/// Source: JPL "Keplerian Elements for Approximate Positions of the Major Planets".
struct OrbitalElements {
    // Base values at J2000.0 epoch
    let a0: Double      // Semi-major axis (AU)
    let e0: Double      // Eccentricity
    let I0: Double      // Inclination (degrees)
    let L0: Double      // Mean longitude (degrees)
    let wBar0: Double   // Longitude of perihelion (degrees)
    let omega0: Double  // Longitude of ascending node (degrees)

    // Rates of change per Julian century
    let aRate: Double
    let eRate: Double
    let IRate: Double
    let LRate: Double
    let wBarRate: Double
    let omegaRate: Double

    /// Compute osculating elements at a given number of Julian centuries since J2000.0.
    func elements(at julianCenturies: Double) -> CurrentElements {
        let T = julianCenturies
        return CurrentElements(
            a: a0 + aRate * T,
            e: e0 + eRate * T,
            I: (I0 + IRate * T).degreesToRadians,
            L: (L0 + LRate * T).degreesToRadians,
            wBar: (wBar0 + wBarRate * T).degreesToRadians,
            omega: (omega0 + omegaRate * T).degreesToRadians
        )
    }
}

// MARK: - Current (Osculating) Elements

/// Osculating elements at a specific epoch, with angles in radians.
struct CurrentElements {
    let a: Double       // Semi-major axis (AU)
    let e: Double       // Eccentricity
    let I: Double       // Inclination (radians)
    let L: Double       // Mean longitude (radians)
    let wBar: Double    // Longitude of perihelion (radians)
    let omega: Double   // Longitude of ascending node (radians)

    /// Mean anomaly M = L - wBar, normalised to [0, 2pi).
    var meanAnomaly: Double {
        let M = L - wBar
        return M.normalizedAngle
    }

    /// Argument of perihelion w = wBar - Omega, normalised to [0, 2pi).
    var argumentOfPerihelion: Double {
        let w = wBar - omega
        return w.normalizedAngle
    }
}

// MARK: - Moon Orbital Elements

/// Simplified orbital parameters for a natural satellite orbiting a planet.
struct MoonOrbitalElements {
    let semiMajorAxisKm: Double  // Distance from parent centre (km)
    let period: Double           // Orbital period (days)
    let eccentricity: Double
    let inclination: Double      // Degrees, relative to parent's equator
    let longitudeAtEpoch: Double // Mean longitude at J2000.0 (degrees)
}

// MARK: - Angle Utilities

extension Double {
    /// Convert degrees to radians.
    var degreesToRadians: Double { self * .pi / 180.0 }

    /// Normalise an angle to the range [0, 2pi).
    var normalizedAngle: Double {
        var angle = self.truncatingRemainder(dividingBy: 2.0 * .pi)
        if angle < 0 { angle += 2.0 * .pi }
        return angle
    }
}
