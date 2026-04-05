// SolarSystemData.swift
// SolarSystem
//
// Static catalogue of all celestial bodies in the simulation. Contains JPL
// J2000.0 Keplerian orbital elements for all eight planets plus Pluto,
// physical properties (radius, colour, ring parameters), IAU rotation
// models, and orbital data for major moons (Earth's Moon, Mars's Phobos
// and Deimos, Jupiter's Galilean moons, and Saturn's seven largest moons).

import Foundation
import SceneKit

enum SolarSystemData {

    // MARK: - Planet Orbital Elements (JPL J2000.0)
    // Source: "Keplerian Elements for Approximate Positions of the Major Planets"
    // Standish, E.M. (1992), JPL Solar System Dynamics

    static let mercury = CelestialBody(
        name: "Mercury",
        type: .planet,
        orbitalElements: OrbitalElements(
            a0: 0.38709927, e0: 0.20563593, I0: 7.00497902,
            L0: 252.25032350, wBar0: 77.45779628, omega0: 48.33076593,
            aRate: 0.00000037, eRate: 0.00001906, IRate: -0.00594749,
            LRate: 149472.67411175, wBarRate: 0.16047689, omegaRate: -0.12534081
        ),
        physical: PhysicalProperties(
            radiusKm: 2439.7,
            color: SCNVector3(0.7, 0.65, 0.6)
        ),
        rotation: RotationProperties(periodHours: 1407.6, obliquity: 0.034, w0: 329.548)
    )

    static let venus = CelestialBody(
        name: "Venus",
        type: .planet,
        orbitalElements: OrbitalElements(
            a0: 0.72333566, e0: 0.00677672, I0: 3.39467605,
            L0: 181.97909950, wBar0: 131.60246718, omega0: 76.67984255,
            aRate: 0.00000390, eRate: -0.00004107, IRate: -0.00078890,
            LRate: 58517.81538729, wBarRate: 0.00268329, omegaRate: -0.27769418
        ),
        physical: PhysicalProperties(
            radiusKm: 6051.8,
            color: SCNVector3(0.9, 0.85, 0.7)
        ),
        // Negative period = retrograde rotation (Venus rotates backwards)
        rotation: RotationProperties(periodHours: -5832.5, obliquity: 177.36, w0: 160.20)
    )

    static let earth = CelestialBody(
        name: "Earth",
        type: .planet,
        orbitalElements: OrbitalElements(
            a0: 1.00000261, e0: 0.01671123, I0: -0.00001531,
            L0: 100.46457166, wBar0: 102.93768193, omega0: 0.0,
            aRate: 0.00000562, eRate: -0.00004392, IRate: -0.01294668,
            LRate: 35999.37244981, wBarRate: 0.32327364, omegaRate: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 6371.0,
            color: SCNVector3(0.2, 0.5, 0.9)
        ),
        rotation: RotationProperties(periodHours: 23.9345, obliquity: 23.44, w0: 190.147),
        moons: [earthMoon]
    )

    static let mars = CelestialBody(
        name: "Mars",
        type: .planet,
        orbitalElements: OrbitalElements(
            a0: 1.52371034, e0: 0.09339410, I0: 1.84969142,
            L0: -4.55343205, wBar0: -23.94362959, omega0: 49.55953891,
            aRate: 0.00001847, eRate: 0.00007882, IRate: -0.00813131,
            LRate: 19140.30268499, wBarRate: 0.44441088, omegaRate: -0.29257343
        ),
        physical: PhysicalProperties(
            radiusKm: 3389.5,
            color: SCNVector3(0.8, 0.35, 0.15)
        ),
        rotation: RotationProperties(periodHours: 24.6229, obliquity: 25.19, w0: 176.630),
        moons: [phobos, deimos]
    )

    static let jupiter = CelestialBody(
        name: "Jupiter",
        type: .planet,
        orbitalElements: OrbitalElements(
            a0: 5.20288700, e0: 0.04838624, I0: 1.30439695,
            L0: 34.39644051, wBar0: 14.72847983, omega0: 100.47390909,
            aRate: -0.00011607, eRate: -0.00013253, IRate: -0.00183714,
            LRate: 3034.74612775, wBarRate: 0.21252668, omegaRate: 0.20469106
        ),
        physical: PhysicalProperties(
            radiusKm: 69911.0,
            color: SCNVector3(0.85, 0.75, 0.55)
        ),
        rotation: RotationProperties(periodHours: 9.9250, obliquity: 3.13, w0: 284.95),
        moons: [io, europa, ganymede, callisto]
    )

    static let saturn = CelestialBody(
        name: "Saturn",
        type: .planet,
        orbitalElements: OrbitalElements(
            a0: 9.53667594, e0: 0.05386179, I0: 2.48599187,
            L0: 49.95424423, wBar0: 92.59887831, omega0: 113.66242448,
            aRate: -0.00125060, eRate: -0.00050991, IRate: 0.00193609,
            LRate: 1222.49362201, wBarRate: -0.41897216, omegaRate: -0.28867794
        ),
        physical: PhysicalProperties(
            radiusKm: 58232.0,
            color: SCNVector3(0.9, 0.82, 0.6),
            hasRings: true,
            ringInnerRadiusKm: 74500,
            ringOuterRadiusKm: 140220
        ),
        rotation: RotationProperties(periodHours: 10.656, obliquity: 26.73, w0: 38.90),
        moons: [titan, rhea, iapetus, dione, tethys, enceladus, mimas]
    )

    static let uranus = CelestialBody(
        name: "Uranus",
        type: .planet,
        orbitalElements: OrbitalElements(
            a0: 19.18916464, e0: 0.04725744, I0: 0.77263783,
            L0: 313.23810451, wBar0: 170.95427630, omega0: 74.01692503,
            aRate: -0.00196176, eRate: -0.00004397, IRate: -0.00242939,
            LRate: 428.48202785, wBarRate: 0.40805281, omegaRate: 0.04240589
        ),
        physical: PhysicalProperties(
            radiusKm: 25362.0,
            color: SCNVector3(0.6, 0.85, 0.9)
        ),
        // Negative period = retrograde; 97.77 degree tilt means Uranus rolls on its side
        rotation: RotationProperties(periodHours: -17.24, obliquity: 97.77, w0: 203.81)
    )

    static let neptune = CelestialBody(
        name: "Neptune",
        type: .planet,
        orbitalElements: OrbitalElements(
            a0: 30.06992276, e0: 0.00859048, I0: 1.77004347,
            L0: -55.12002969, wBar0: 44.96476227, omega0: 131.78422574,
            aRate: 0.00026291, eRate: 0.00005105, IRate: 0.00035372,
            LRate: 218.45945325, wBarRate: -0.32241464, omegaRate: -0.00508664
        ),
        physical: PhysicalProperties(
            radiusKm: 24622.0,
            color: SCNVector3(0.25, 0.4, 0.9)
        ),
        rotation: RotationProperties(periodHours: 16.11, obliquity: 28.32, w0: 253.18)
    )

    static let pluto = CelestialBody(
        name: "Pluto",
        type: .dwarfPlanet,
        orbitalElements: OrbitalElements(
            a0: 39.48211675, e0: 0.24882730, I0: 17.14001206,
            L0: 238.92903833, wBar0: 224.06891629, omega0: 110.30393684,
            aRate: -0.00031596, eRate: 0.00005170, IRate: 0.00004818,
            LRate: 145.20780515, wBarRate: -0.04062942, omegaRate: -0.01183482
        ),
        physical: PhysicalProperties(
            radiusKm: 1188.3,
            color: SCNVector3(0.75, 0.7, 0.6)
        ),
        // Negative period = retrograde rotation
        rotation: RotationProperties(periodHours: -153.2928, obliquity: 122.53, w0: 302.695)
    )

    // MARK: - Earth's Moon

    static let earthMoon = CelestialBody(
        name: "Moon",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 384400,
            period: 27.321661,
            eccentricity: 0.0549,
            inclination: 5.145,
            longitudeAtEpoch: 218.32
        ),
        physical: PhysicalProperties(
            radiusKm: 1737.4,
            color: SCNVector3(0.7, 0.7, 0.7)
        ),
        rotation: RotationProperties(periodHours: 27.321661 * 24, obliquity: 6.687, w0: 38.321, tidallyLocked: true)
    )

    // MARK: - Mars's Moons

    static let phobos = CelestialBody(
        name: "Phobos",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 9376,
            period: 0.31891,
            eccentricity: 0.0151,
            inclination: 1.093,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 11.267,
            color: SCNVector3(0.5, 0.45, 0.4)
        ),
        rotation: RotationProperties(periodHours: 0.31891 * 24, obliquity: 0, tidallyLocked: true)
    )

    static let deimos = CelestialBody(
        name: "Deimos",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 23463,
            period: 1.26244,
            eccentricity: 0.00033,
            inclination: 0.93,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 6.2,
            color: SCNVector3(0.55, 0.5, 0.45)
        ),
        rotation: RotationProperties(periodHours: 1.26244 * 24, obliquity: 0, tidallyLocked: true)
    )

    // MARK: - Jupiter's Galilean Moons (all tidally locked)

    static let io = CelestialBody(
        name: "Io",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 421700,
            period: 1.769138,
            eccentricity: 0.0041,
            inclination: 0.036,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 1821.6,
            color: SCNVector3(0.9, 0.85, 0.4)
        ),
        rotation: RotationProperties(periodHours: 1.769138 * 24, obliquity: 0.05, w0: 200.39, tidallyLocked: true)
    )

    static let europa = CelestialBody(
        name: "Europa",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 671034,
            period: 3.551181,
            eccentricity: 0.0094,
            inclination: 0.466,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 1560.8,
            color: SCNVector3(0.8, 0.75, 0.65)
        ),
        rotation: RotationProperties(periodHours: 3.551181 * 24, obliquity: 0.1, w0: 36.022, tidallyLocked: true)
    )

    static let ganymede = CelestialBody(
        name: "Ganymede",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 1070412,
            period: 7.154553,
            eccentricity: 0.0013,
            inclination: 0.177,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 2634.1,
            color: SCNVector3(0.65, 0.6, 0.55)
        ),
        rotation: RotationProperties(periodHours: 7.154553 * 24, obliquity: 0.33, w0: 44.064, tidallyLocked: true)
    )

    static let callisto = CelestialBody(
        name: "Callisto",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 1882709,
            period: 16.689018,
            eccentricity: 0.0074,
            inclination: 0.192,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 2410.3,
            color: SCNVector3(0.45, 0.42, 0.38)
        ),
        rotation: RotationProperties(periodHours: 16.689018 * 24, obliquity: 0, w0: 259.51, tidallyLocked: true)
    )

    // MARK: - Saturn's Major Moons (all tidally locked)

    static let titan = CelestialBody(
        name: "Titan",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 1221870,
            period: 15.945,
            eccentricity: 0.0288,
            inclination: 0.34,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 2574.7,
            color: SCNVector3(0.85, 0.7, 0.35)
        ),
        rotation: RotationProperties(periodHours: 15.945 * 24, obliquity: 0, tidallyLocked: true)
    )

    static let rhea = CelestialBody(
        name: "Rhea",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 527108,
            period: 4.518,
            eccentricity: 0.0012,
            inclination: 0.345,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 763.8,
            color: SCNVector3(0.75, 0.75, 0.75)
        ),
        rotation: RotationProperties(periodHours: 4.518 * 24, obliquity: 0, tidallyLocked: true)
    )

    static let iapetus = CelestialBody(
        name: "Iapetus",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 3560820,
            period: 79.322,
            eccentricity: 0.0286,
            inclination: 15.47,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 734.5,
            color: SCNVector3(0.5, 0.45, 0.4)
        ),
        rotation: RotationProperties(periodHours: 79.322 * 24, obliquity: 0, tidallyLocked: true)
    )

    static let dione = CelestialBody(
        name: "Dione",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 377396,
            period: 2.737,
            eccentricity: 0.0022,
            inclination: 0.019,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 561.4,
            color: SCNVector3(0.8, 0.8, 0.8)
        ),
        rotation: RotationProperties(periodHours: 2.737 * 24, obliquity: 0, tidallyLocked: true)
    )

    static let tethys = CelestialBody(
        name: "Tethys",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 294619,
            period: 1.888,
            eccentricity: 0.0001,
            inclination: 1.12,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 531.1,
            color: SCNVector3(0.82, 0.82, 0.82)
        ),
        rotation: RotationProperties(periodHours: 1.888 * 24, obliquity: 0, tidallyLocked: true)
    )

    static let enceladus = CelestialBody(
        name: "Enceladus",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 237948,
            period: 1.370,
            eccentricity: 0.0047,
            inclination: 0.019,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 252.1,
            color: SCNVector3(0.95, 0.95, 0.95)
        ),
        rotation: RotationProperties(periodHours: 1.370 * 24, obliquity: 0, tidallyLocked: true)
    )

    static let mimas = CelestialBody(
        name: "Mimas",
        type: .moon,
        moonElements: MoonOrbitalElements(
            semiMajorAxisKm: 185539,
            period: 0.942,
            eccentricity: 0.0196,
            inclination: 1.574,
            longitudeAtEpoch: 0.0
        ),
        physical: PhysicalProperties(
            radiusKm: 198.2,
            color: SCNVector3(0.75, 0.73, 0.7)
        ),
        rotation: RotationProperties(periodHours: 0.942 * 24, obliquity: 0, tidallyLocked: true)
    )

    // MARK: - Sun

    static let sun = CelestialBody(
        name: "Sun",
        type: .star,
        physical: PhysicalProperties(
            radiusKm: 695700,
            color: SCNVector3(1.0, 0.95, 0.8),
            emissive: true
        ),
        rotation: RotationProperties(periodHours: 25.05 * 24, obliquity: 7.25, w0: 84.176)
    )

    // MARK: - All Bodies

    /// Ordered list of all planets (including Pluto) for iteration and UI display.
    static var allPlanets: [CelestialBody] {
        [mercury, venus, earth, mars, jupiter, saturn, uranus, neptune, pluto]
    }
}
