// CatmullRom.swift
// SolarSystem
//
// Centripetal Catmull-Rom spline in SIMD3<Double> space, matching the default
// Three.js CatmullRomCurve3 behaviour (type: "centripetal", tension: 0.5) used
// by the web mission system. Parameterised 0..1 across all control points.
// Pure math — `nonisolated` so tests can call these without a main actor hop.

import Foundation
import simd

enum CatmullRom {

    /// Sample the centripetal Catmull-Rom curve through `points` at parameter `u ∈ [0, 1]`.
    /// For a curve with N control points, `u = i/(N-1)` lands exactly on control point i.
    static func sample(points: [SIMD3<Double>], u: Double) -> SIMD3<Double> {
        let n = points.count
        guard n >= 2 else { return points.first ?? .zero }
        if n == 2 {
            return mix(points[0], points[1], t: u)
        }

        let clampedU = max(0.0, min(1.0, u))
        let segmentFloat = clampedU * Double(n - 1)
        var i = Int(floor(segmentFloat))
        if i >= n - 1 { i = n - 2 }
        let t = segmentFloat - Double(i)

        // Control points P0..P3 for segment between points[i] and points[i+1].
        // Clamp at ends — duplicate the endpoint instead of wrapping.
        let p0 = points[max(0, i - 1)]
        let p1 = points[i]
        let p2 = points[i + 1]
        let p3 = points[min(n - 1, i + 2)]

        return centripetal(p0: p0, p1: p1, p2: p2, p3: p3, t: t)
    }

    /// Sample a time-parameterised trajectory: waypoints have strictly increasing
    /// timestamps, and this interpolates spatially along a Catmull-Rom curve but
    /// progresses linearly with time. Matches the `rotatedWaypoints` path-sample
    /// loop in js/missions.js.
    ///
    /// - Parameters:
    ///   - points: control points in 3D space (length N, N ≥ 2).
    ///   - times: strictly increasing timestamps aligned to `points` (length N).
    ///   - time: the instant to evaluate; clamped to the first/last timestamp.
    static func sampleAtTime(points: [SIMD3<Double>], times: [Double], time: Double) -> SIMD3<Double> {
        let n = points.count
        precondition(n == times.count, "points and times must have the same length")
        guard n >= 2 else { return points.first ?? .zero }

        let t = max(times[0], min(times[n - 1], time))

        // Find the bracketing waypoint index.
        var wi = 0
        while wi < n - 1 && times[wi + 1] <= t { wi += 1 }
        if wi >= n - 1 { wi = n - 2 }

        let denom = times[wi + 1] - times[wi]
        let frac = denom > 0 ? (t - times[wi]) / denom : 0
        let u = (Double(wi) + frac) / Double(n - 1)
        return sample(points: points, u: u)
    }

    // MARK: - Private

    /// Evaluate a centripetal Catmull-Rom curve on the middle segment
    /// P1 → P2, using P0 and P3 as "phantom" tangent guides.
    ///
    /// The centripetal variant (alpha = 0.5) uses `sqrt(chord_length)` as the
    /// knot spacing, which produces loop-free splines even when control points
    /// are irregularly spaced — the default "uniform" variant overshoots badly
    /// on near-vertical waypoint transitions (common in mission trajectories
    /// near launch / splashdown). Implemented via Barry-Goldman / De Boor
    /// recursion: three linear interpolations on the first level, two on the
    /// second, one on the third.
    private static func centripetal(p0: SIMD3<Double>, p1: SIMD3<Double>,
                                     p2: SIMD3<Double>, p3: SIMD3<Double>,
                                     t: Double) -> SIMD3<Double> {
        // Knot parameters t0..t3: cumulative sqrt-of-chord-length along P0→P1→P2→P3.
        let t0 = 0.0
        let t1 = t0 + knotDelta(p0, p1)
        let t2 = t1 + knotDelta(p1, p2)
        let t3 = t2 + knotDelta(p2, p3)

        // Map input t ∈ [0,1] to a position between t1 and t2 (the P1..P2 segment).
        let u = t1 + (t2 - t1) * t

        // First level: three weighted interpolations across overlapping triples.
        let a1 = lerp(p0, p1, a: (t1 - u) / (t1 - t0), b: (u - t0) / (t1 - t0))
        let a2 = lerp(p1, p2, a: (t2 - u) / (t2 - t1), b: (u - t1) / (t2 - t1))
        let a3 = lerp(p2, p3, a: (t3 - u) / (t3 - t2), b: (u - t2) / (t3 - t2))

        // Second level: two interpolations across wider spans.
        let b1 = lerp(a1, a2, a: (t2 - u) / (t2 - t0), b: (u - t0) / (t2 - t0))
        let b2 = lerp(a2, a3, a: (t3 - u) / (t3 - t1), b: (u - t1) / (t3 - t1))

        // Final level: a single interpolation over the segment [t1, t2].
        return lerp(b1, b2, a: (t2 - u) / (t2 - t1), b: (u - t1) / (t2 - t1))
    }

    /// Centripetal knot delta: `sqrt(distance(a, b))`. The minimum clamp keeps
    /// the formulation well-defined when two control points are coincident
    /// (can happen with duplicated anchor waypoints in a mission trajectory).
    private static func knotDelta(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        return max(sqrt(simd_length(b - a)), 1e-8)
    }

    /// Weighted linear combination used by the Barry-Goldman recursion.
    /// Degenerate weights (both near zero) collapse to `a` rather than
    /// propagating NaN — this matters when the input `t` hits an exact knot
    /// boundary and one weight is `0/0`.
    private static func lerp(_ a: SIMD3<Double>, _ b: SIMD3<Double>,
                              a weightA: Double, b weightB: Double) -> SIMD3<Double> {
        let sum = weightA + weightB
        if abs(sum) < 1e-12 { return a }
        return a * weightA + b * weightB
    }

    /// Two-point linear interpolation, clamped to t ∈ [0, 1]. Used as the
    /// fast path when there are only two control points (the centripetal
    /// recursion needs P0..P3 so can't run on two points).
    private static func mix(_ a: SIMD3<Double>, _ b: SIMD3<Double>, t: Double) -> SIMD3<Double> {
        return a + (b - a) * max(0.0, min(1.0, t))
    }
}
