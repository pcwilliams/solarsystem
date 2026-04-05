// OrbitalMechanics.swift
// SolarSystem
//
// Core orbital mechanics engine. Converts dates to Julian dates, solves
// Kepler's equation via Newton-Raphson iteration, and computes heliocentric
// ecliptic positions for planets and parent-relative positions for moons.
// Also generates full orbit paths for drawing orbital lines.

import Foundation
import simd

enum OrbitalMechanics {

    // MARK: - Julian Date

    /// J2000.0 epoch expressed as a Julian Date Number.
    static let j2000: Double = 2451545.0

    /// Convert a Foundation Date to Julian Date Number.
    /// Uses the algorithm from Meeus, "Astronomical Algorithms" (Chapter 7).
    static func julianDate(from date: Date) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!,
                                                  from: date)
        let year = Double(components.year!)
        let month = Double(components.month!)
        let day = Double(components.day!)
        let hour = Double(components.hour ?? 0)
        let minute = Double(components.minute ?? 0)
        let second = Double(components.second ?? 0)

        let dayFraction = (hour + minute / 60.0 + second / 3600.0) / 24.0

        // Adjust year/month so January and February are months 13/14 of the previous year
        var y = year
        var m = month
        if m <= 2 {
            y -= 1
            m += 12
        }

        // Gregorian calendar correction
        let A = floor(y / 100.0)
        let B = 2.0 - A + floor(A / 4.0)

        let JD = floor(365.25 * (y + 4716.0)) +
                 floor(30.6001 * (m + 1.0)) +
                 day + dayFraction + B - 1524.5

        return JD
    }

    /// Julian centuries (36525 days each) elapsed since J2000.0.
    static func julianCenturies(from date: Date) -> Double {
        let JD = julianDate(from: date)
        return (JD - j2000) / 36525.0
    }

    // MARK: - Kepler's Equation

    /// Solve Kepler's equation  E - e*sin(E) = M  using Newton-Raphson iteration.
    /// Converges to the eccentric anomaly E for a given mean anomaly M and eccentricity e.
    /// Typically converges in 3-5 iterations for planetary eccentricities.
    static func solveKepler(M: Double, e: Double, tolerance: Double = 1e-8) -> Double {
        // Initial guess: M + e*sin(M) is a good first approximation for small e
        var E = M + e * sin(M)

        for _ in 0..<50 {
            // Newton-Raphson: f(E) = E - e*sin(E) - M, f'(E) = 1 - e*cos(E)
            let dE = (E - e * sin(E) - M) / (1.0 - e * cos(E))
            E -= dE
            if abs(dE) < tolerance { break }
        }

        return E
    }

    /// Convert eccentric anomaly E to true anomaly nu using the half-angle formula.
    static func trueAnomaly(E: Double, e: Double) -> Double {
        return 2.0 * atan2(
            sqrt(1.0 + e) * sin(E / 2.0),
            sqrt(1.0 - e) * cos(E / 2.0)
        )
    }

    // MARK: - Heliocentric Position

    /// Compute heliocentric ecliptic (x, y, z) position in AU from orbital elements at a date.
    /// Pipeline: elements at epoch -> mean anomaly -> Kepler solve -> true anomaly -> 3D position.
    static func heliocentricPosition(elements: OrbitalElements, at date: Date) -> SIMD3<Double> {
        let T = julianCenturies(from: date)
        let current = elements.elements(at: T)

        let M = current.meanAnomaly
        let E = solveKepler(M: M, e: current.e)
        let nu = trueAnomaly(E: E, e: current.e)

        // Heliocentric distance from the orbit equation
        let r = current.a * (1.0 - current.e * cos(E))

        // Transform from orbital plane to ecliptic coordinates
        let w = current.argumentOfPerihelion
        let cosOmega = cos(current.omega)
        let sinOmega = sin(current.omega)
        let cosI = cos(current.I)
        let sinI = sin(current.I)
        let cosWNu = cos(w + nu)
        let sinWNu = sin(w + nu)

        let x = r * (cosOmega * cosWNu - sinOmega * sinWNu * cosI)
        let y = r * (sinOmega * cosWNu + cosOmega * sinWNu * cosI)
        let z = r * (sinWNu * sinI)

        return SIMD3<Double>(x, y, z)
    }

    // MARK: - Moon Position

    /// Compute a moon's position relative to its parent planet.
    /// Returns an offset vector in AU from the parent body's centre.
    static func moonPosition(moonElements: MoonOrbitalElements, at date: Date) -> SIMD3<Double> {
        let JD = julianDate(from: date)
        let daysSinceEpoch = JD - j2000

        // Mean anomaly from mean motion (radians/day) and elapsed time
        let meanMotion = 2.0 * .pi / moonElements.period
        let M = (moonElements.longitudeAtEpoch.degreesToRadians + meanMotion * daysSinceEpoch)
            .normalizedAngle

        let e = moonElements.eccentricity
        let E = solveKepler(M: M, e: e)
        let nu = trueAnomaly(E: E, e: e)

        // Distance in km, then convert to AU
        let r = moonElements.semiMajorAxisKm * (1.0 - e * cos(E))
        let rAU = r / 149597870.7

        // Simple inclined orbit (no node precession)
        let incl = moonElements.inclination.degreesToRadians
        let cosNu = cos(nu)
        let sinNu = sin(nu)

        let x = rAU * cosNu
        let y = rAU * sinNu * cos(incl)
        let z = rAU * sinNu * sin(incl)

        return SIMD3<Double>(x, y, z)
    }

    // MARK: - Orbit Path

    /// Generate evenly-spaced points around a full orbit for drawing orbital path lines.
    /// Uses the polar form of the orbit equation r = a(1-e^2)/(1+e*cos(nu)).
    static func orbitPath(elements: OrbitalElements, at date: Date, points: Int = 360) -> [SIMD3<Double>] {
        let T = julianCenturies(from: date)
        let current = elements.elements(at: T)
        let w = current.argumentOfPerihelion

        // Pre-compute trig values for the coordinate rotation
        let cosOmega = cos(current.omega)
        let sinOmega = sin(current.omega)
        let cosI = cos(current.I)
        let sinI = sin(current.I)

        var path: [SIMD3<Double>] = []
        path.reserveCapacity(points + 1)

        for i in 0...points {
            let nu = Double(i) / Double(points) * 2.0 * .pi
            let r = current.a * (1.0 - current.e * current.e) / (1.0 + current.e * cos(nu))

            let cosWNu = cos(w + nu)
            let sinWNu = sin(w + nu)

            let x = r * (cosOmega * cosWNu - sinOmega * sinWNu * cosI)
            let y = r * (sinOmega * cosWNu + cosOmega * sinWNu * cosI)
            let z = r * (sinWNu * sinI)

            path.append(SIMD3<Double>(x, y, z))
        }

        return path
    }
}
