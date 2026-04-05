// InfoPanelView.swift
// SolarSystem
//
// Top-of-screen overlay showing the current simulation date/time,
// time scale indicator, and a detail card for the currently selected
// celestial body (name, type, radius, and heliocentric distance).

import SwiftUI
import simd

struct InfoPanelView: View {
    let celestialBody: CelestialBody?
    let currentDate: Date
    let timeScale: Double
    let onDismiss: () -> Void

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Always-visible time display bar
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text(dateFormatter.string(from: currentDate))
                    .font(.caption)
                    .foregroundColor(.white)

                // Show time scale badge when not at real-time
                if timeScale != 1.0 {
                    Text("\(timeScale >= 1 ? String(format: "%.0f", timeScale) : String(format: "%.2f", timeScale))x")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            // Detail card for the selected body (hidden when nothing is selected)
            if let selectedBody = celestialBody {
                bodyInfoCard(selectedBody)
            }
        }
    }

    // MARK: - Body Info Card

    /// Expandable card showing the selected body's colour swatch, name, type, radius,
    /// and current distance from the Sun in AU.
    @ViewBuilder
    private func bodyInfoCard(_ celestialBody: CelestialBody) -> some View {
        HStack(spacing: 12) {
            // Colour swatch matching the body's base colour
            Circle()
                .fill(Color(
                    red: Double(celestialBody.physical.color.x),
                    green: Double(celestialBody.physical.color.y),
                    blue: Double(celestialBody.physical.color.z)
                ))
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(celestialBody.name)
                    .font(.headline)
                    .foregroundColor(.white)

                HStack(spacing: 8) {
                    Text(celestialBody.type.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("r: \(formatRadius(celestialBody.physical.radiusKm))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Show heliocentric distance for everything except the Sun
                    if celestialBody.type != .star {
                        let dist = simd_length(celestialBody.position)
                        Text("\(String(format: "%.2f", dist)) AU")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    /// Format a radius value for display, using "k km" for large bodies.
    private func formatRadius(_ km: Double) -> String {
        if km >= 10000 {
            return String(format: "%.0fk km", km / 1000.0)
        } else if km >= 100 {
            return String(format: "%.0f km", km)
        } else {
            return String(format: "%.1f km", km)
        }
    }
}
