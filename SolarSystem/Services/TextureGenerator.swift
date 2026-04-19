// TextureGenerator.swift
// SolarSystem
//
// Procedural texture generation for the Sun and its corona glow.
// Planet textures are bundled NASA/public-domain JPGs applied in the view model;
// only the Sun's surface and glow sprites use runtime-generated textures.
//
// Cross-platform: draws via raw `CGContext` + a bitmap backing so the same
// code path runs on iOS (UIKit) and macOS (AppKit). The output is wrapped in
// a `PlatformImage` so SceneKit's `material.diffuse.contents` accepts it on
// either platform without further unwrapping. See `Extensions/Platform.swift`
// for the typealiases.

import CoreGraphics
import Foundation

enum TextureGenerator {

    // MARK: - Sun Texture

    /// Generate a procedural Sun surface texture with granulation,
    /// supergranulation patches, and radial limb darkening. Produces an
    /// equirectangular map of size `width × (width/2)` so it wraps cleanly
    /// around an `SCNSphere`.
    static func generateSunTexture(size: Int = 1024) -> PlatformImage {
        let width = size
        let height = size / 2
        return drawIntoBitmap(width: width, height: height) { ctx in
            let w = CGFloat(width), h = CGFloat(height)

            // Base bright yellow-white fill.
            ctx.setFillColor(PlatformColor(red: 1.0, green: 0.92, blue: 0.65, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // 800 small granulation cells simulating convection tops.
            for _ in 0..<800 {
                let x = CGFloat.random(in: 0...w)
                let y = CGFloat.random(in: 0...h)
                let s = CGFloat.random(in: 3...12)
                let brightness = CGFloat.random(in: 0.85...1.0)
                let r = min(1.0, brightness + CGFloat.random(in: -0.05...0.05))
                let g = min(1.0, brightness * 0.92 + CGFloat.random(in: -0.05...0.05))
                let b = max(0.0, brightness * 0.55 + CGFloat.random(in: -0.1...0.1))

                ctx.setFillColor(PlatformColor(red: r, green: g, blue: b, alpha: 0.6).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - s/2, y: y - s/2, width: s, height: s))
            }

            // 40 larger supergranulation patches for macro texture variation.
            for _ in 0..<40 {
                let x = CGFloat.random(in: 0...w)
                let y = CGFloat.random(in: 0...h)
                let s = CGFloat.random(in: 20...60)
                let darkness = CGFloat.random(in: 0.7...0.85)

                ctx.setFillColor(PlatformColor(red: darkness,
                                                 green: darkness * 0.85,
                                                 blue: darkness * 0.45,
                                                 alpha: 0.3).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - s/2, y: y - s/2,
                                            width: s, height: s * CGFloat.random(in: 0.6...1.4)))
            }

            // Radial limb-darkening gradient so edges of the Sun appear
            // darker/redder than the centre.
            let cx = w / 2, cy = h / 2
            let maxR = max(w, h)
            let limbColors: [CGColor] = [
                PlatformColor.clear.cgColor,
                PlatformColor.clear.cgColor,
                PlatformColor(red: 0.8, green: 0.5, blue: 0.15, alpha: 0.3).cgColor,
            ]
            let limbLocations: [CGFloat] = [0.0, 0.6, 1.0]

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: limbColors as CFArray,
                                          locations: limbLocations) {
                ctx.drawRadialGradient(gradient,
                                       startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                       endCenter: CGPoint(x: cx, y: cy), endRadius: maxR,
                                       options: [])
            }
        }
    }

    // MARK: - Glow Texture

    /// Generate a radial gradient texture for smooth corona glow falloff on
    /// spheres. Used by the Sun's 4-layer glow system with additive blending.
    /// The gradient has four stops: full colour at the centre fading to
    /// transparent at the edge, with intermediate 0.5× and 0.1× alpha stops
    /// for a soft, non-linear falloff.
    static func generateGlowTexture(color: PlatformColor, size: Int = 256) -> PlatformImage {
        drawIntoBitmap(width: size, height: size) { ctx in
            let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
            let maxRadius = CGFloat(size) / 2

            // Pull the RGBA components back out of the input colour so we can
            // build a four-stop gradient at matching hue with decreasing alpha.
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #if canImport(UIKit)
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            #else
            let rgb = color.usingColorSpace(.deviceRGB) ?? color
            rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
            #endif

            let colors: [CGColor] = [
                PlatformColor(red: r, green: g, blue: b, alpha: a).cgColor,
                PlatformColor(red: r, green: g, blue: b, alpha: a * 0.5).cgColor,
                PlatformColor(red: r, green: g, blue: b, alpha: a * 0.1).cgColor,
                PlatformColor(red: r, green: g, blue: b, alpha: 0).cgColor,
            ]
            let locations: [CGFloat] = [0.0, 0.3, 0.65, 1.0]

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: colors as CFArray,
                                          locations: locations) {
                ctx.drawRadialGradient(gradient,
                                       startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: maxRadius,
                                       options: [])
            }
        }
    }

    // MARK: - Private

    /// Draw into a freshly-created 32-bit RGBA bitmap context and return the
    /// result as a `PlatformImage`. Replaces `UIGraphicsImageRenderer` (which
    /// is iOS-only) with a direct Core Graphics path that's identical on both
    /// platforms.
    ///
    /// The image is flipped vertically (origin at top-left, matching UIKit's
    /// coordinate convention) so the drawing code inside the closure can use
    /// UIKit-style coordinates regardless of which platform runs it.
    private static func drawIntoBitmap(width: Int, height: Int,
                                         draw: (CGContext) -> Void) -> PlatformImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil,
                                   width: width, height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: 0,
                                   space: colorSpace,
                                   bitmapInfo: bitmapInfo) else {
            return PlatformImage()
        }

        // Flip so (0,0) is top-left to match UIKit's convention — the macOS
        // default origin is bottom-left and would render the drawing upside
        // down.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        draw(ctx)

        guard let cgImage = ctx.makeImage() else { return PlatformImage() }
        return makePlatformImage(cgImage: cgImage,
                                  size: CGSize(width: width, height: height))
    }
}
