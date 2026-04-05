// SceneBuilder.swift
// SolarSystem
//
// Constructs and configures the SceneKit scene graph. Creates sphere nodes
// for celestial bodies, orbital path line geometry, Saturn's ring disc,
// the Sun's multi-layered glow corona, a real starfield from the HYG
// catalogue (with per-vertex B-V colour), and the scene's lighting and camera.
//
// Also provides position update methods that convert heliocentric AU
// coordinates to logarithmically-scaled SceneKit positions.

import Foundation
import SceneKit
import simd

// MARK: - Named Star

/// A star from the HYG catalogue with a common name, used for label projection.
struct NamedStar {
    let name: String
    let position: SCNVector3
    let magnitude: Float
}

// MARK: - Scene Builder

@MainActor
final class SceneBuilder {

    /// Named stars loaded from catalogue — available for label projection
    var namedStars: [NamedStar] = []

    // MARK: - Scale Constants

    /// Logarithmic distance scale: maps AU to scene units.
    /// Mercury ~7.5, Earth ~16.5, Jupiter ~36.5, Neptune ~63.
    static let distanceScaleBase: Double = 0.5
    static let distanceScaleFactor: Double = 15.0

    /// Convert real AU distance to scene units using logarithmic compression.
    static func sceneDistance(au: Double) -> Double {
        return log(1.0 + au / distanceScaleBase) * distanceScaleFactor
    }

    /// Convert real radius in km to scene units.
    /// Planets use sqrt scaling for a visible size hierarchy.
    /// Moons use real radius ratio with a minimum floor so tiny bodies stay visible.
    ///
    /// Approximate scene sizes (planets):
    ///   Jupiter ~ 0.33, Saturn ~ 0.30, Uranus ~ 0.20, Neptune ~ 0.20
    ///   Earth ~ 0.10, Venus ~ 0.10, Mars ~ 0.07, Mercury ~ 0.06
    ///
    /// Approximate scene sizes (moons, real ratio to parent):
    ///   Moon ~ 0.027 (0.27x Earth), Ganymede ~ 0.012 (0.038x Jupiter)
    static let planetScaleBase: Double = 0.00125
    static let minimumBodyRadius: Float = 0.012

    static func sceneRadius(km: Double, type: BodyType) -> Float {
        switch type {
        case .star:
            return 0.8
        case .moon:
            let scaled = sqrt(km) * planetScaleBase
            return Float(max(Double(minimumBodyRadius), scaled))
        default:
            let scaled = sqrt(km) * planetScaleBase
            return Float(max(0.03, min(0.35, scaled)))
        }
    }

    // MARK: - Scene Construction

    /// Build the root scene with starfield background, lighting, and camera.
    func buildScene() -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.black

        addStarfield(to: scene)
        addLighting(to: scene)
        addCamera(to: scene)

        return scene
    }

    // MARK: - Celestial Body Nodes

    /// Create a SceneKit sphere node for a celestial body with appropriate material and decorations.
    func createBodyNode(for body: CelestialBody) -> SCNNode {
        let radius = SceneBuilder.sceneRadius(km: body.physical.radiusKm, type: body.type)
        let sphere = SCNSphere(radius: CGFloat(max(radius, 0.02)))
        sphere.segmentCount = body.type == .star ? 48 : 36

        let material = SCNMaterial()

        if body.physical.emissive {
            // Sun: procedural texture with granulation and limb darkening
            let sunTexture = TextureGenerator.generateSunTexture()
            material.diffuse.contents = sunTexture
            material.emission.contents = sunTexture
            material.lightingModel = .constant
        } else {
            // Planets and moons: physically-based rendering
            configurePlanetMaterial(material, for: body)
        }

        sphere.firstMaterial = material

        let node = SCNNode(geometry: sphere)
        node.name = body.id

        if body.physical.emissive {
            addSunGlow(to: node, radius: CGFloat(radius))
        }

        if body.physical.hasRings {
            addRings(to: node, body: body)
        }

        return node
    }

    // MARK: - Planet Materials

    /// Configure PBR material properties per planet for realistic appearance.
    private func configurePlanetMaterial(_ material: SCNMaterial, for body: CelestialBody) {
        let color = UIColor(
            red: CGFloat(body.physical.color.x),
            green: CGFloat(body.physical.color.y),
            blue: CGFloat(body.physical.color.z),
            alpha: 1.0
        )

        material.diffuse.contents = color
        material.lightingModel = .physicallyBased
        material.roughness.contents = NSNumber(value: 0.7)
        material.metalness.contents = NSNumber(value: 0.1)

        switch body.name {
        case "Earth":
            material.roughness.contents = NSNumber(value: 0.5)
            material.metalness.contents = NSNumber(value: 0.05)
        case "Jupiter", "Saturn":
            material.roughness.contents = NSNumber(value: 0.9)
        case "Mercury":
            // Heavily cratered surface = very rough
            material.roughness.contents = NSNumber(value: 0.95)
            material.metalness.contents = NSNumber(value: 0.15)
        case "Venus":
            material.roughness.contents = NSNumber(value: 0.6)
        case "Mars":
            material.roughness.contents = NSNumber(value: 0.85)
        default:
            break
        }
    }

    // MARK: - Sun Glow

    /// Add layered corona glow spheres around the Sun for a realistic luminous appearance.
    private func addSunGlow(to node: SCNNode, radius: CGFloat) {
        // Layer 1: Inner hot white-yellow corona
        addGlowLayer(to: node, name: "sun_glow_inner",
                     radius: radius * 1.3,
                     color: UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 0.4))

        // Layer 2: Mid orange glow
        addGlowLayer(to: node, name: "sun_glow_mid",
                     radius: radius * 1.8,
                     color: UIColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 0.2))

        // Layer 3: Outer faint corona
        addGlowLayer(to: node, name: "sun_glow_outer",
                     radius: radius * 2.8,
                     color: UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 0.08))

        // Layer 4: Very faint extended corona
        addGlowLayer(to: node, name: "sun_glow_corona",
                     radius: radius * 4.0,
                     color: UIColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 0.03))

    }

    /// Add a single additive-blended glow sphere with a radial gradient texture.
    private func addGlowLayer(to node: SCNNode, name: String, radius: CGFloat, color: UIColor) {
        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 36
        let material = SCNMaterial()
        material.diffuse.contents = TextureGenerator.generateGlowTexture(color: color)
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.blendMode = .add
        material.writesToDepthBuffer = false
        material.transparent.contents = TextureGenerator.generateGlowTexture(color: color)
        sphere.firstMaterial = material

        let glowNode = SCNNode(geometry: sphere)
        glowNode.name = name
        node.addChildNode(glowNode)
    }

    // MARK: - Saturn's Rings

    /// Build Saturn's ring system as a custom disc geometry with radial UV mapping.
    /// Uses bundled colour and alpha textures for the ring band structure.
    private func addRings(to node: SCNNode, body: CelestialBody) {
        let planetRadius = SceneBuilder.sceneRadius(km: body.physical.radiusKm, type: body.type)
        let innerScale = Float(body.physical.ringInnerRadiusKm / body.physical.radiusKm)
        let outerScale = Float(body.physical.ringOuterRadiusKm / body.physical.radiusKm)

        let innerR = planetRadius * innerScale
        let outerR = planetRadius * outerScale

        // Disc geometry: concentric rings subdivided radially
        let radialSegments = 72
        let ringSegments = 4

        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []

        for ring in 0...ringSegments {
            let t = Float(ring) / Float(ringSegments)
            let r = innerR + (outerR - innerR) * t

            for seg in 0...radialSegments {
                let angle = Float(seg) / Float(radialSegments) * 2.0 * .pi
                let x = r * cos(angle)
                let z = r * sin(angle)

                vertices.append(SCNVector3(x, 0, z))
                normals.append(SCNVector3(0, 1, 0))
                // u = radial position (inner=0, outer=1), v = azimuthal position
                uvs.append(CGPoint(x: CGFloat(t), y: CGFloat(seg) / CGFloat(radialSegments)))
            }
        }

        // Triangle strip indices connecting adjacent ring segments
        let vertsPerRing = radialSegments + 1
        for ring in 0..<ringSegments {
            for seg in 0..<radialSegments {
                let a = Int32(ring * vertsPerRing + seg)
                let b = a + 1
                let c = Int32((ring + 1) * vertsPerRing + seg)
                let d = c + 1

                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let uvSource = SCNGeometrySource(textureCoordinates: uvs)
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: indexData, primitiveType: .triangles,
                                          primitiveCount: indices.count / 3,
                                          bytesPerIndex: MemoryLayout<Int32>.size)

        let geometry = SCNGeometry(sources: [vertexSource, normalSource, uvSource], elements: [element])

        let ringMaterial = SCNMaterial()
        // Planet Pixel Emporium ring textures: separate colour and alpha maps
        if let colorPath = Bundle.main.path(forResource: "saturn_ring_color", ofType: "jpg") {
            ringMaterial.diffuse.contents = UIImage(contentsOfFile: colorPath)
        } else {
            ringMaterial.diffuse.contents = UIColor(red: 0.85, green: 0.78, blue: 0.6, alpha: 1.0)
        }
        if let alphaPath = Bundle.main.path(forResource: "saturn_ring_alpha", ofType: "gif") {
            ringMaterial.transparent.contents = UIImage(contentsOfFile: alphaPath)
        }
        ringMaterial.lightingModel = .constant
        ringMaterial.isDoubleSided = true
        geometry.firstMaterial = ringMaterial

        let ringNode = SCNNode(geometry: geometry)
        ringNode.name = "saturn_rings"
        // No extra tilt here — Saturn's axial tilt is applied via the rotation system
        node.addChildNode(ringNode)
    }

    // MARK: - Orbital Path Lines

    /// Create a line-segment geometry tracing a planet's full orbital path.
    func createOrbitNode(for body: CelestialBody, at date: Date) -> SCNNode? {
        guard let elements = body.orbitalElements else { return nil }

        let pathPoints = OrbitalMechanics.orbitPath(elements: elements, at: date, points: 180)

        var vertices: [SCNVector3] = []
        var indices: [Int32] = []

        for (i, point) in pathPoints.enumerated() {
            // Apply the same logarithmic distance compression used for body positions
            let dist = simd_length(point)
            let sceneDist = SceneBuilder.sceneDistance(au: dist)
            let scale = dist > 0 ? sceneDist / dist : 0
            let scaled = point * scale

            // Convert ecliptic (x,y,z) to SceneKit (x, z, -y)
            vertices.append(SCNVector3(Float(scaled.x), Float(scaled.z), Float(-scaled.y)))

            if i > 0 {
                indices.append(Int32(i - 1))
                indices.append(Int32(i))
            }
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: indices.count / 2,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(white: 0.45, alpha: 0.8)
        material.lightingModel = .constant
        geometry.firstMaterial = material

        let node = SCNNode(geometry: geometry)
        node.name = "\(body.id)_orbit"
        return node
    }

    // MARK: - Starfield (HYG Catalogue)

    /// Load the HYG star catalogue CSV and create a point-cloud geometry with
    /// per-vertex colour and brightness-tiered point sizes.
    private func addStarfield(to scene: SCNScene) {
        guard let path = Bundle.main.path(forResource: "stars", ofType: "csv"),
              let data = try? String(contentsOfFile: path, encoding: .utf8) else {
            return
        }

        let lines = data.components(separatedBy: "\n").dropFirst() // skip CSV header
        let r: Float = 500.0  // celestial sphere radius in scene units

        var positions: [SCNVector3] = []
        var colors: [SCNVector3] = []
        var sizes: [Float] = []

        for line in lines {
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cols.count >= 4,
                  let raHours = Double(cols[0]),
                  let decDeg = Double(cols[1]),
                  let mag = Double(cols[2]),
                  let bv = Double(cols[3]) else { continue }

            // Convert right ascension (hours) and declination (degrees) to radians
            let ra = raHours * (.pi / 12.0)
            let dec = decDeg * (.pi / 180.0)

            // Spherical to Cartesian on the celestial sphere
            let cosDec = cos(dec)
            let x = r * Float(cosDec * cos(ra))
            let y = r * Float(sin(dec))
            let z = r * Float(cosDec * sin(ra))
            let pos = SCNVector3(x, y, -z)
            positions.append(pos)

            // Convert B-V colour index to RGB for per-vertex colouring
            let rgb = bvToRGB(bv)
            colors.append(rgb)
            sizes.append(Float(mag))

            // Collect named stars (magnitude < 4.0) for the label overlay
            if cols.count >= 5 {
                let name = String(cols[4]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty && mag < 4.0 {
                    namedStars.append(NamedStar(name: name, position: pos, magnitude: Float(mag)))
                }
            }
        }

        // Build geometry with per-vertex RGB colour
        let vertexSource = SCNGeometrySource(vertices: positions)

        let colorData = colors.withUnsafeBufferPointer { buffer in
            Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<SCNVector3>.stride)
        }
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SCNVector3>.stride
        )

        // Split stars into brightness tiers for different point sizes:
        //   Tier 0: mag < 1.5  (~20 brightest stars)  - large points
        //   Tier 1: mag 1.5-3.5 (~200 stars)          - medium points
        //   Tier 2: mag 3.5-5.0 (~1500 stars)         - small points
        //   Tier 3: mag 5.0-6.5 (~7000 stars)         - tiny points
        let tiers: [(maxMag: Float, pointSize: CGFloat, minScreen: CGFloat, maxScreen: CGFloat)] = [
            (1.5,  8.0, 3.0, 8.0),
            (3.5,  4.0, 2.0, 5.0),
            (5.0,  2.5, 1.5, 3.0),
            (6.5,  1.5, 0.8, 2.0),
        ]

        var tierIndices: [[Int32]] = [[], [], [], []]
        for (i, mag) in sizes.enumerated() {
            let tier: Int
            if mag < 1.5 { tier = 0 }
            else if mag < 3.5 { tier = 1 }
            else if mag < 5.0 { tier = 2 }
            else { tier = 3 }
            tierIndices[tier].append(Int32(i))
        }

        // One geometry element per tier, each with its own point size
        var elements: [SCNGeometryElement] = []
        for (tierIdx, indices) in tierIndices.enumerated() {
            guard !indices.isEmpty else { continue }
            let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
            let element = SCNGeometryElement(
                data: indexData,
                primitiveType: .point,
                primitiveCount: indices.count,
                bytesPerIndex: MemoryLayout<Int32>.size
            )
            let tier = tiers[tierIdx]
            element.pointSize = tier.pointSize
            element.minimumPointScreenSpaceRadius = tier.minScreen
            element.maximumPointScreenSpaceRadius = tier.maxScreen
            elements.append(element)
        }

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: elements)

        // One constant-lighting material per tier (vertex colour provides the actual hue)
        for _ in elements {
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.white
            material.lightingModel = .constant
            geometry.materials.append(material)
        }

        let starNode = SCNNode(geometry: geometry)
        starNode.name = "starfield"
        scene.rootNode.addChildNode(starNode)
    }

    // MARK: - B-V Colour Mapping

    /// Convert B-V colour index to RGB for star rendering.
    /// B-V ranges from about -0.4 (hot blue-white O/B stars) through
    /// 0.0 (white A stars) to 2.0+ (cool red M stars).
    /// Uses piecewise linear approximation of the Planckian locus.
    private func bvToRGB(_ bv: Double) -> SCNVector3 {
        let bv = max(-0.4, min(2.0, bv))

        let r: Double
        let g: Double
        let b: Double

        if bv < 0.0 {
            // Blue-white stars (O, B type)
            r = 0.7 + bv * 0.3
            g = 0.8 + bv * 0.2
            b = 1.0
        } else if bv < 0.4 {
            // White to yellow-white (A, F type)
            r = 1.0
            g = 1.0 - bv * 0.3
            b = 1.0 - bv * 0.8
        } else if bv < 0.8 {
            // Yellow (G type, like our Sun)
            r = 1.0
            g = 0.95 - (bv - 0.4) * 0.5
            b = 0.7 - (bv - 0.4) * 0.7
        } else if bv < 1.2 {
            // Orange (K type)
            r = 1.0
            g = 0.7 - (bv - 0.8) * 0.4
            b = 0.4 - (bv - 0.8) * 0.35
        } else {
            // Red (M type)
            r = 1.0
            g = max(0.3, 0.55 - (bv - 1.2) * 0.3)
            b = max(0.15, 0.22 - (bv - 1.2) * 0.15)
        }

        return SCNVector3(Float(r), Float(g), Float(b))
    }

    // MARK: - Lighting

    /// Add a point light at the Sun's position and a dim ambient fill light.
    private func addLighting(to scene: SCNScene) {
        // Point light at the Sun (origin) illuminating all planets
        let sunLight = SCNLight()
        sunLight.type = .omni
        sunLight.color = UIColor(red: 1.0, green: 0.97, blue: 0.9, alpha: 1.0)
        sunLight.intensity = 2000
        sunLight.attenuationStartDistance = 0
        sunLight.attenuationEndDistance = 500

        let sunLightNode = SCNNode()
        sunLightNode.light = sunLight
        sunLightNode.position = SCNVector3Zero
        sunLightNode.name = "sun_light"
        scene.rootNode.addChildNode(sunLightNode)

        // Dim ambient light so the dark sides of planets aren't pure black
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(white: 0.15, alpha: 1.0)
        ambient.intensity = 500

        let ambientNode = SCNNode()
        ambientNode.light = ambient
        ambientNode.name = "ambient_light"
        scene.rootNode.addChildNode(ambientNode)
    }

    // MARK: - Camera

    /// Add the initial camera positioned above the inner solar system looking at the origin.
    private func addCamera(to scene: SCNScene) {
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 1000
        camera.fieldOfView = 60

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.name = "camera"

        // Start above and behind the inner solar system
        let earthDist = SceneBuilder.sceneDistance(au: 1.0)
        cameraNode.position = SCNVector3(0, Float(earthDist) * 1.5, Float(earthDist) * 2.0)
        cameraNode.look(at: SCNVector3Zero)

        scene.rootNode.addChildNode(cameraNode)
    }

    // MARK: - Position Updates

    /// Convert heliocentric ecliptic AU coordinates to SceneKit world position
    /// using logarithmic distance compression.
    func updateNodePosition(_ node: SCNNode, position: SIMD3<Double>) {
        let dist = simd_length(position)
        let sceneDist = SceneBuilder.sceneDistance(au: dist)
        let scale = dist > 0 ? sceneDist / dist : 0
        let scaled = position * scale

        // Ecliptic to SceneKit: x stays x, ecliptic z maps to scene y, ecliptic y flips to -z
        node.position = SCNVector3(Float(scaled.x), Float(scaled.z), Float(-scaled.y))
    }

    /// Position a moon relative to its parent planet. Uses the real orbital-radius-to-planet-radius
    /// ratio, compressed by pow(0.4) so close moons (Phobos at 2.8 radii) stay close and
    /// distant moons (Callisto at 26 radii) remain proportionally farther.
    func updateMoonNodePosition(_ moonNode: SCNNode, moonOffset: SIMD3<Double>,
                                 parentPosition: SIMD3<Double>,
                                 parentRadiusKm: Double,
                                 moonSemiMajorKm: Double) {
        let moonDist = simd_length(moonOffset)
        let parentSceneRadius = Double(SceneBuilder.sceneRadius(km: parentRadiusKm, type: .planet))

        // Compress the real orbital ratio so moons are visible but proportionally spaced:
        //   Moon:     384400/6371  = 60.3 -> pow(0.4) -> 5.9  -> x1.5 -> 8.8x parentRadius
        //   Io:       421700/69911 = 6.0  -> pow(0.4) -> 2.1  -> x1.5 -> 3.1x parentRadius
        //   Callisto: 1882709/69911= 26.9 -> pow(0.4) -> 3.8  -> x1.5 -> 5.7x parentRadius
        let realRatio = moonSemiMajorKm / parentRadiusKm
        let compressedRatio = pow(realRatio, 0.4) * 1.5
        let moonSceneDist = moonDist > 0 ? parentSceneRadius * compressedRatio : 0

        let direction: SIMD3<Double>
        if moonDist > 0 {
            direction = moonOffset / moonDist
        } else {
            direction = SIMD3<Double>(1, 0, 0)
        }
        let scaledOffset = direction * moonSceneDist

        // Get parent's scene position using the same log compression
        let parentDist = simd_length(parentPosition)
        let parentSceneDist = SceneBuilder.sceneDistance(au: parentDist)
        let parentScale = parentDist > 0 ? parentSceneDist / parentDist : 0
        let parentScenePos = parentPosition * parentScale

        let finalPos = parentScenePos + scaledOffset

        moonNode.position = SCNVector3(
            Float(finalPos.x),
            Float(finalPos.z),
            Float(-finalPos.y)
        )
    }
}
