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
                        creditRow("Mercury, Venus, Saturn (body & rings), Uranus, Neptune",
                                  detail: "Solar System Scope (solarsystemscope.com)")
                    }

                    // Galilean moon composites
                    creditsSection(title: "Publicly Available, Attribution Requested") {
                        creditRow("Io, Ganymede, Callisto",
                                  detail: "Björn Jónsson (bjj.mmedia.is), from NASA/JPL Voyager + Galileo data")
                    }

                    // Star catalogue
                    creditsSection(title: "Public Domain") {
                        creditRow("8,404 Stars",
                                  detail: "Yale Bright Star Catalog, 5th Rev. (Hoffleit & Warren, 1991), prepared at NASA Goddard NSSDC/ADC. Distributed via VizieR catalogue V/50.")
                    }

                    // Licence
                    creditsSection(title: "Licence") {
                        creditRow("Source code", detail: "MIT licence — see LICENSE and THIRDPARTY.md")
                    }

                    // Built with
                    creditsSection(title: "Built With") {
                        creditRow("Frameworks", detail: "SwiftUI, SceneKit, Foundation, simd")
                        creditRow("AI Pair Programming", detail: "Claude by Anthropic")
                    }
                }
                .padding()
            }
            // Grouped-background colour is iOS-only; on macOS we use the
            // windowBackgroundColor equivalent via the SwiftUI material.
            #if os(iOS)
            .background(Color(.systemGroupedBackground))
            #else
            .background(Color(.windowBackgroundColor))
            #endif
            .navigationTitle("Credits")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
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
