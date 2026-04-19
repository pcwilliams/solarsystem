// CatmullRomTests.swift
// SolarSystemTests
//
// Verifies the centripetal Catmull-Rom implementation used for mission
// trajectory sampling. Endpoints must hit control points exactly; midpoint
// sampling should stay inside the control-point bounding box; time-based
// sampling must be monotonic and map to the correct segment.

import Foundation
import Testing
import simd
@testable import SolarSystem

struct CatmullRomTests {

    @Test func firstAndLastControlPointsAreHitExactly() {
        let points: [SIMD3<Double>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 2, 0),
            SIMD3(4, 3, 0),
            SIMD3(6, 0, 0),
        ]
        let start = CatmullRom.sample(points: points, u: 0)
        let end = CatmullRom.sample(points: points, u: 1)
        #expect(simd_distance(start, points[0]) < 1e-9)
        #expect(simd_distance(end, points.last!) < 1e-9)
    }

    @Test func interiorControlPointsAreHitAtUniformU() {
        let points: [SIMD3<Double>] = [
            SIMD3(0, 0, 0),
            SIMD3(10, 0, 0),
            SIMD3(20, 0, 0),
            SIMD3(30, 0, 0),
        ]
        // u = 1/3 should land on points[1], u = 2/3 on points[2].
        let mid1 = CatmullRom.sample(points: points, u: 1.0/3.0)
        let mid2 = CatmullRom.sample(points: points, u: 2.0/3.0)
        #expect(simd_distance(mid1, points[1]) < 1e-6)
        #expect(simd_distance(mid2, points[2]) < 1e-6)
    }

    @Test func twoPointInterpolationIsLinear() {
        let points: [SIMD3<Double>] = [SIMD3(0, 0, 0), SIMD3(10, 20, 0)]
        let mid = CatmullRom.sample(points: points, u: 0.5)
        #expect(abs(mid.x - 5) < 1e-9)
        #expect(abs(mid.y - 10) < 1e-9)
    }

    @Test func timeParameterisedSamplingMatchesTimeline() {
        // Four waypoints at non-uniform timestamps — the curve should pass
        // through each waypoint exactly when time equals its timestamp.
        let points: [SIMD3<Double>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 1, 0),
            SIMD3(3, 2, 0),
            SIMD3(6, 0, 0),
        ]
        let times: [Double] = [0, 5, 20, 100]

        for (i, t) in times.enumerated() {
            let p = CatmullRom.sampleAtTime(points: points, times: times, time: t)
            #expect(simd_distance(p, points[i]) < 1e-6,
                    "control point \(i) at t=\(t)")
        }

        // Time in the middle of a segment stays within that segment's bounding box.
        let midA = CatmullRom.sampleAtTime(points: points, times: times, time: 10)
        #expect(midA.x >= min(points[1].x, points[2].x) - 0.1)
        #expect(midA.x <= max(points[1].x, points[2].x) + 0.1)
    }

    @Test func timeSamplingClampsOutOfRange() {
        let points: [SIMD3<Double>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(2, 0, 0),
        ]
        let times: [Double] = [0, 10, 20]
        let before = CatmullRom.sampleAtTime(points: points, times: times, time: -5)
        let after = CatmullRom.sampleAtTime(points: points, times: times, time: 100)
        #expect(simd_distance(before, points[0]) < 1e-9)
        #expect(simd_distance(after, points.last!) < 1e-9)
    }

    @Test func degenerateCoincidentWaypointsDoNotCrash() {
        // If two adjacent control points are identical, the knot delta clamp
        // prevents division by zero. The curve should still return a finite value.
        let points: [SIMD3<Double>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(1, 0, 0),
            SIMD3(2, 0, 0),
        ]
        let p = CatmullRom.sample(points: points, u: 0.5)
        #expect(p.x.isFinite && p.y.isFinite && p.z.isFinite)
    }
}
