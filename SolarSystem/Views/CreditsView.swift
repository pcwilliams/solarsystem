// CreditsView.swift
// SolarSystem
//
// Credits and attribution sheet listing all data sources, texture
// providers, and their respective licences.

import SwiftUI

struct CreditsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 4) {
                        Text("SolarSystem")
                            .font(.title.bold())
                        Text("Real-time orbital mechanics simulation")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)

                    // Orbital Data
                    creditsSection(title: "Orbital Mechanics") {
                        creditRow("Planetary Elements",
                                  detail: "JPL Keplerian Elements for Approximate Positions of the Major Planets (Standish, 1992)")
                        creditRow("Rotation Models",
                                  detail: "IAU Working Group on Cartographic Coordinates and Rotational Elements")
                    }

                    // Public Domain Textures
                    creditsSection(title: "Public Domain (NASA/USGS)") {
                        creditRow("Earth", detail: "NASA Blue Marble Next Generation")
                        creditRow("Moon", detail: "NASA Lunar Reconnaissance Orbiter Camera")
                        creditRow("Mars", detail: "USGS Viking MDIM21 mosaic")
                        creditRow("Jupiter", detail: "NASA/JPL/SSI Cassini (PIA07782)")
                        creditRow("Pluto", detail: "NASA/JHUAPL/SwRI New Horizons")
                        creditRow("Europa", detail: "NASA/JPL Voyager/Galileo")
                    }

                    // CC-BY 4.0
                    creditsSection(title: "CC-BY 4.0") {
                        creditRow("Mercury, Venus, Uranus, Neptune",
                                  detail: "Solar System Scope (solarsystemscope.com)")
                    }

                    // Planet Pixel Emporium
                    creditsSection(title: "Free Non-Commercial Use") {
                        creditRow("Saturn (body & rings)",
                                  detail: "Planet Pixel Emporium by James Hastings-Trew")
                    }

                    // Galilean moon composites
                    creditsSection(title: "From NASA Public Domain Data") {
                        creditRow("Io, Ganymede", detail: "Assembled by Steve Albers")
                        creditRow("Callisto", detail: "Assembled by Bjorn Jonsson")
                    }

                    // Star catalogue
                    creditsSection(title: "CC-BY-SA 2.0") {
                        creditRow("8,920 Stars",
                                  detail: "HYG Database v38 by David Nash (astronexus). Compiled from ESA Hipparcos, Yale BSC, and Gliese catalogues.")
                    }

                    // Built with
                    creditsSection(title: "Built With") {
                        creditRow("Frameworks", detail: "SwiftUI, SceneKit, Foundation, simd")
                        creditRow("AI Pair Programming", detail: "Claude by Anthropic")
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Credits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

    private func creditsSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.orange)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
    }

    private func creditRow(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.subheadline.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
