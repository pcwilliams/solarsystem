// TextureGenerator.swift
// SolarSystem
//
// Procedural texture generation for the Sun and glow effects.
// Planet textures are bundled NASA/public-domain JPGs applied in the view model;
// only the Sun's surface and corona glow spheres use runtime-generated textures.

import UIKit

enum TextureGenerator {

    // MARK: - Sun Texture

    /// Generate a procedural Sun surface texture with granulation, supergranulation
    /// cells, and radial limb darkening. Produces a 1024x512 equirectangular map.
    static func generateSunTexture(size: Int = 1024) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size / 2))
        return renderer.image { context in
            let ctx = context.cgContext
            let width = CGFloat(size)
            let height = CGFloat(size / 2)

            // Base bright yellow-white fill
            ctx.setFillColor(UIColor(red: 1.0, green: 0.92, blue: 0.65, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Small bright/dark granulation spots simulating convection cells
            let granuleCount = 800
            for _ in 0..<granuleCount {
                let x = CGFloat.random(in: 0...width)
                let y = CGFloat.random(in: 0...height)
                let size = CGFloat.random(in: 3...12)
                let brightness = CGFloat.random(in: 0.85...1.0)
                let r = min(1.0, brightness + CGFloat.random(in: -0.05...0.05))
                let g = min(1.0, brightness * 0.92 + CGFloat.random(in: -0.05...0.05))
                let b = max(0.0, brightness * 0.55 + CGFloat.random(in: -0.1...0.1))

                ctx.setFillColor(UIColor(red: r, green: g, blue: b, alpha: 0.6).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - size/2, y: y - size/2,
                                            width: size, height: size))
            }

            // Larger darker patches simulating supergranulation
            let cellCount = 40
            for _ in 0..<cellCount {
                let x = CGFloat.random(in: 0...width)
                let y = CGFloat.random(in: 0...height)
                let size = CGFloat.random(in: 20...60)
                let darkness = CGFloat.random(in: 0.7...0.85)

                ctx.setFillColor(UIColor(red: darkness, green: darkness * 0.85,
                                          blue: darkness * 0.45, alpha: 0.3).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - size/2, y: y - size/2,
                                            width: size, height: size * CGFloat.random(in: 0.6...1.4)))
            }

            // Radial limb darkening gradient — edges of the Sun appear darker/redder
            let centerX = width / 2
            let centerY = height / 2
            let maxR = max(width, height)
            let limbColors: [CGColor] = [
                UIColor.clear.cgColor,
                UIColor.clear.cgColor,
                UIColor(red: 0.8, green: 0.5, blue: 0.15, alpha: 0.3).cgColor,
            ]
            let limbLocations: [CGFloat] = [0.0, 0.6, 1.0]

            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: limbColors as CFArray,
                                          locations: limbLocations) {
                ctx.drawRadialGradient(gradient,
                                       startCenter: CGPoint(x: centerX, y: centerY),
                                       startRadius: 0,
                                       endCenter: CGPoint(x: centerX, y: centerY),
                                       endRadius: maxR,
                                       options: [])
            }
        }
    }

    // MARK: - Glow Texture

    /// Generate a radial gradient texture for smooth corona glow falloff on spheres.
    /// Used by the Sun's layered glow system with additive blending.
    static func generateGlowTexture(color: UIColor, size: Int = 256) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { context in
            let ctx = context.cgContext
            let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
            let maxRadius = CGFloat(size) / 2

            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)

            // Four-stop gradient: full colour at centre fading to transparent at edge
            let colors: [CGColor] = [
                UIColor(red: r, green: g, blue: b, alpha: a).cgColor,
                UIColor(red: r, green: g, blue: b, alpha: a * 0.5).cgColor,
                UIColor(red: r, green: g, blue: b, alpha: a * 0.1).cgColor,
                UIColor(red: r, green: g, blue: b, alpha: 0).cgColor,
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
}
