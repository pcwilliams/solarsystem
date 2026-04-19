// MissionData.swift
// SolarSystem
//
// Loads the bundled `Missions.json` resource (exported from the companion web
// app via tools/export-missions.mjs) and converts the JSON-shaped DTO layer
// into the domain `Mission` / `Vehicle` / `Waypoint` structs the rest of the
// app consumes. Keeping the DTO separate from the domain type means the domain
// type stays ergonomic (custom initialisers, convenience computed properties)
// while the on-disk JSON remains the single source of truth for waypoint data.

import Foundation
import simd

enum MissionData {

    /// All missions bundled with the app. Loaded lazily on first access from
    /// `Missions.json`; a crash here is a resource-bundling bug, not a data bug.
    static let all: [Mission] = loadAll()

    /// Faint orange used by most mission trails — matches the web app default
    /// (RGB 1.0, 0.6, 0.3). Exposed for tests and any future in-code data.
    static let defaultColor = SIMD3<Float>(1.0, 0.6, 0.3)

    // MARK: - Loading

    private static func loadAll() -> [Mission] {
        guard let url = Bundle.main.url(forResource: "Missions", withExtension: "json") else {
            assertionFailure("Missions.json not in app bundle — check pbxproj resource phase")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { dec in
                let container = try dec.singleValueContainer()
                let s = try container.decode(String.self)
                if let date = iso.date(from: s) { return date }
                // Fallback for entries without fractional seconds.
                let plain = ISO8601DateFormatter()
                plain.formatOptions = [.withInternetDateTime]
                if let date = plain.date(from: s) { return date }
                throw DecodingError.dataCorruptedError(in: container,
                    debugDescription: "Unrecognised ISO8601 date: \(s)")
            }
            let dtos = try decoder.decode([MissionJSON].self, from: data)
            return dtos.map { $0.toDomain() }
        } catch {
            assertionFailure("Failed to decode Missions.json: \(error)")
            return []
        }
    }
}

// MARK: - DTO layer

/// JSON-shaped mission record. Only exists for `Decodable` conformance — all
/// app code deals with the domain `Mission` type after `toDomain()` conversion.
private struct MissionJSON: Decodable {
    let id: String
    let name: String
    let subtitle: String
    let launchDate: Date
    let durationHours: Double
    let flybyTimeHours: Double?
    let referenceFrame: String
    let autoTrajectory: String?
    let events: [EventJSON]
    let vehicles: [VehicleJSON]

    func toDomain() -> Mission {
        let frame: MissionReferenceFrame = (referenceFrame == "heliocentric") ? .heliocentric : .geocentric
        return Mission(
            id: id,
            name: name,
            subtitle: subtitle,
            launchDate: launchDate,
            durationHours: durationHours,
            flybyTimeHours: flybyTimeHours,
            referenceFrame: frame,
            events: events.map { $0.toDomain() },
            vehicles: vehicles.map { $0.toDomain(missionAutoTrajectory: autoTrajectory) }
        )
    }
}

private struct EventJSON: Decodable {
    let t: Double
    let name: String
    let detail: String
    let showLabel: Bool

    func toDomain() -> MissionEvent {
        MissionEvent(t: t, name: name, detail: detail, showLabel: showLabel)
    }
}

private struct VehicleJSON: Decodable {
    let id: String
    let name: String
    let color: [Float]
    let primary: Bool
    let autoTrajectory: String?
    let moonOrbit: MoonOrbitJSON?
    let moonLanding: MoonLandingJSON?
    let moonOrbitReturn: MoonOrbitJSON?
    let waypoints: [WaypointJSON]

    func toDomain(missionAutoTrajectory: String?) -> Vehicle {
        let rgb = color.count >= 3
            ? SIMD3<Float>(color[0], color[1], color[2])
            : MissionData.defaultColor
        return Vehicle(
            id: id,
            name: name,
            color: rgb,
            primary: primary,
            waypoints: waypoints.map { $0.toDomain() },
            autoTrajectory: autoTrajectory ?? missionAutoTrajectory,
            moonOrbit: moonOrbit?.toDomain(),
            moonLanding: moonLanding?.toDomain(),
            moonOrbitReturn: moonOrbitReturn?.toDomain()
        )
    }
}

private struct MoonOrbitJSON: Decodable {
    let startTime: Double
    let endTime: Double
    let periodHours: Double
    let radiusKm: Double

    func toDomain() -> MoonOrbitPhase {
        MoonOrbitPhase(startTime: startTime, endTime: endTime,
                        periodHours: periodHours, radiusKm: radiusKm)
    }
}

private struct MoonLandingJSON: Decodable {
    let startTime: Double
    let endTime: Double

    func toDomain() -> MoonLandingPhase {
        MoonLandingPhase(startTime: startTime, endTime: endTime)
    }
}

private struct WaypointJSON: Decodable {
    let t: Double
    let x: Double
    let y: Double
    let z: Double
    let anchorMoon: Bool
    let anchorBody: String?

    func toDomain() -> Waypoint {
        Waypoint(t: t, x: x, y: y, z: z,
                  anchorMoon: anchorMoon, anchorBody: anchorBody)
    }
}
