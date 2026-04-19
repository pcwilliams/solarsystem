// MissionUITests.swift
// SolarSystemTests
//
// Verifies formatting helpers consumed by the Phase 4 mission UI overlay.
// Kept in a separate file from MissionTests so SwiftUI-adjacent logic stays
// independent from the mission-manager behaviour tests.

import Foundation
import Testing
@testable import SolarSystem

struct MissionUITests {

    // MARK: - MET formatting

    @Test func metUnderADayShowsHoursMinutesSeconds() {
        // 3h 7m 30s = 3.125h
        #expect(formatMET(3.125) == "T+03:07:30")
    }

    @Test func metAboveADayShowsDays() {
        // 2d 14h 32m 8s = 224,000 + 50,400 + 1,920 + 8 = 224,000 + 52,328 secs
        let daysSec: Double = 172800   // 2 * 86400
        let hoursSec: Double = 50400    // 14 * 3600
        let minSec: Double = 1920       // 32 * 60
        let sec: Double = 8
        let hours = (daysSec + hoursSec + minSec + sec) / 3600
        #expect(formatMET(hours) == "T+2d 14:32:08")
    }

    @Test func metZeroFormatsAsAllZeros() {
        #expect(formatMET(0) == "T+00:00:00")
    }

    // MARK: - Distance formatting

    @Test func distanceFormatsHeliocentricAsAU() {
        let tel = MissionTelemetry(
            missionName: "Cassini", metHours: 0,
            distanceKm: 0, distanceAU: 1.234, speedKmS: 0,
            isHeliocentric: true)
        #expect(formatDistance(tel) == "1.234 AU")
    }

    @Test func distanceFormatsGeocentricUnderAThousandInKm() {
        let tel = MissionTelemetry(
            missionName: "Apollo 11", metHours: 0,
            distanceKm: 450, distanceAU: nil, speedKmS: 0,
            isHeliocentric: false)
        #expect(formatDistance(tel) == "450 km")
    }

    @Test func distanceFormatsGeocentricAboveAThousandInThousandsOfKm() {
        let tel = MissionTelemetry(
            missionName: "Apollo 11", metHours: 0,
            distanceKm: 245_500, distanceAU: nil, speedKmS: 0,
            isHeliocentric: false)
        #expect(formatDistance(tel) == "246k km")
    }

    // MARK: - Speed formatting

    @Test func speedFormatsUnderAHundredWithTwoDecimals() {
        #expect(formatSpeed(1.02) == "1.02 km/s")
        #expect(formatSpeed(11.0) == "11.00 km/s")
    }

    @Test func speedFormatsAboveAHundredWithNoDecimals() {
        #expect(formatSpeed(137.8) == "138 km/s")
    }
}
