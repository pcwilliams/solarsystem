// MissionUIViews.swift
// SolarSystem
//
// SwiftUI overlays that surface the active mission in the UI: the missions
// dropdown menu, the orange timeline slider, the bottom-left telemetry HUD,
// and the animated event banner. Ported from the matching CSS overlays in
// the companion web app (`../solarsystem-web/index.html`).

import SwiftUI

// MARK: - Shared style

private extension Color {
    /// Faint orange used throughout the mission UI so it reads as distinct
    /// from celestial-body labels (which are white/grey).
    static let missionOrange = Color(red: 1.0, green: 0.67, blue: 0.31)
}

// MARK: - Rocket Icon

/// Procedural rocket silhouette used as the toolbar label for the missions
/// menu. SF Symbols has no rocket glyph, and keeping the app pure-Apple-
/// frameworks rules out bundled SVG assets — drawing it as a SwiftUI `Path`
/// is the lightweight match. Sized to read alongside SF Symbol icons at
/// default weight / dynamic type; `.foregroundColor` tints the whole shape.
private struct RocketIcon: View {
    /// Base size matches SF Symbol caps at large-title body weight.
    var size: CGFloat = 20

    var body: some View {
        Canvas { context, _ in
            let w = size
            let h = size
            // Centre of the icon — everything is drawn relative to this.
            let cx = w * 0.5
            let topY = h * 0.05
            let shoulderY = h * 0.35     // where the nose cone meets the body
            let bottomY = h * 0.75       // base of the main body
            let flameTipY = h * 0.98
            let bodyHalfWidth = w * 0.14
            let finHalfWidth = w * 0.30
            let finTopY = h * 0.62

            // Main fuselage — rounded top via the nose cone plus a rectangular body.
            var body = Path()
            body.move(to: CGPoint(x: cx, y: topY))
            body.addQuadCurve(to: CGPoint(x: cx + bodyHalfWidth, y: shoulderY),
                              control: CGPoint(x: cx + bodyHalfWidth * 0.4, y: topY + (shoulderY - topY) * 0.5))
            body.addLine(to: CGPoint(x: cx + bodyHalfWidth, y: bottomY))
            body.addLine(to: CGPoint(x: cx - bodyHalfWidth, y: bottomY))
            body.addLine(to: CGPoint(x: cx - bodyHalfWidth, y: shoulderY))
            body.addQuadCurve(to: CGPoint(x: cx, y: topY),
                              control: CGPoint(x: cx - bodyHalfWidth * 0.4, y: topY + (shoulderY - topY) * 0.5))
            body.closeSubpath()
            context.fill(body, with: .color(.missionOrange))

            // Side fins flaring out from the lower fuselage.
            var fins = Path()
            fins.move(to: CGPoint(x: cx + bodyHalfWidth, y: finTopY))
            fins.addLine(to: CGPoint(x: cx + finHalfWidth, y: bottomY))
            fins.addLine(to: CGPoint(x: cx + bodyHalfWidth, y: bottomY))
            fins.closeSubpath()
            fins.move(to: CGPoint(x: cx - bodyHalfWidth, y: finTopY))
            fins.addLine(to: CGPoint(x: cx - finHalfWidth, y: bottomY))
            fins.addLine(to: CGPoint(x: cx - bodyHalfWidth, y: bottomY))
            fins.closeSubpath()
            context.fill(fins, with: .color(.missionOrange))

            // Exhaust flame: simple triangle pointing down from the base.
            var flame = Path()
            flame.move(to: CGPoint(x: cx - bodyHalfWidth * 0.75, y: bottomY))
            flame.addLine(to: CGPoint(x: cx, y: flameTipY))
            flame.addLine(to: CGPoint(x: cx + bodyHalfWidth * 0.75, y: bottomY))
            flame.closeSubpath()
            context.fill(flame, with: .color(.missionOrange.opacity(0.55)))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Missions Menu

/// Toolbar dropdown that selects or cancels the active mission, plus a
/// show/hide toggle for trajectories. Labelled with a procedural rocket
/// silhouette (`RocketIcon`) — SF Symbols has no rocket glyph and a custom
/// asset would break the "pure Apple frameworks" rule.
///
/// Takes explicit bindings + a closure rather than `@ObservedObject var
/// viewModel` so this view doesn't re-evaluate on every per-frame
/// `@Published` change in the parent view model — that rebuilds the
/// `Menu` 20 times a second and makes its popover unreliable.
struct MissionsMenu: View {
    @Binding var activeMissionId: String?
    let missions: [Mission]
    let onCancel: () -> Void

    var body: some View {
        Menu {
            // iOS menus render bottom-to-top, so list control items first so
            // they appear at the *bottom* of the dropdown visually.
            Button("Stop replay (1x)") { onCancel() }
                .disabled(activeMissionId == nil)

            Divider()

            // Missions listed in reverse so the oldest (Apollo 8) sits at the
            // bottom of the menu and newest (Artemis II, Perseverance) at the top.
            ForEach(missions.reversed(), id: \.id) { mission in
                Button {
                    activeMissionId = mission.id
                } label: {
                    if activeMissionId == mission.id {
                        Label(mission.name, systemImage: "checkmark.circle.fill")
                    } else {
                        Text(mission.name)
                    }
                }
            }
        } label: {
            RocketIcon()
                .foregroundColor(activeMissionId != nil ? .missionOrange : .gray)
        }
    }
}

// MARK: - Timeline Slider

/// Horizontal scrubber showing mission progress from T+0 to durationHours.
/// Dragging pauses playback; releasing resumes. Syncs automatically during
/// normal playback via `viewModel.missionElapsedHours`.
struct MissionTimelineSlider: View {
    @ObservedObject var viewModel: SolarSystemViewModel

    var body: some View {
        if let id = viewModel.activeMissionId,
           let mission = viewModel.missionManager.missions.first(where: { $0.id == id }) {
            let thumb: CGFloat = 12
            HStack(spacing: 6) {
                Text(metLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.missionOrange.opacity(0.8))
                    .frame(width: 72, alignment: .trailing)

                GeometryReader { geo in
                    let track = geo.size.width
                    let frac = mission.durationHours > 0
                        ? max(0, min(1, viewModel.missionElapsedHours / mission.durationHours))
                        : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.missionOrange.opacity(0.2))
                            .frame(height: 2)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.missionOrange.opacity(0.7))
                            .frame(width: CGFloat(frac) * track, height: 2)
                        Circle()
                            .fill(Color.missionOrange)
                            .frame(width: thumb, height: thumb)
                            .offset(x: CGFloat(frac) * track - thumb / 2)
                    }
                    .frame(height: 22)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                viewModel.timelineScrubbing = true
                                let f = max(0, min(1, value.location.x / track))
                                viewModel.seekMission(toElapsedHours: f * mission.durationHours)
                            }
                            .onEnded { _ in
                                viewModel.timelineScrubbing = false
                            }
                    )
                }
                .frame(height: 22)

                Text(durationLabel(mission.durationHours))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.missionOrange.opacity(0.4))
                    .frame(width: 48, alignment: .leading)
            }
        }
    }

    private var metLabel: String {
        formatMET(viewModel.missionElapsedHours)
    }

    private func durationLabel(_ hours: Double) -> String {
        let days = Int(hours / 24)
        if days > 0 { return "T+\(days)d" }
        return "T+\(Int(hours))h"
    }
}

// MARK: - Telemetry Panel

/// Glass-morphism HUD pinned to the bottom-left showing the active mission's
/// primary vehicle telemetry. Hides itself when no mission is selected or
/// when the simulation is outside the mission duration.
struct MissionTelemetryPanel: View {
    @ObservedObject var viewModel: SolarSystemViewModel

    var body: some View {
        if let tel = viewModel.missionTelemetry {
            VStack(alignment: .leading, spacing: 6) {
                Text(tel.missionName.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.missionOrange)

                metricRow(label: "MET", value: formatMET(tel.metHours))
                metricRow(label: "DIST", value: formatDistance(tel))
                metricRow(label: "SPD",  value: formatSpeed(tel.speedKmS))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.missionOrange.opacity(0.25), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 180, alignment: .leading)
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.missionOrange.opacity(0.7))
                .frame(width: 34, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.92))
        }
    }
}

// MARK: - Event Banner

/// Briefly overlays an event name + detail when the simulation crosses a
/// mission event timestamp. Slides up from below + fades out after 4 seconds.
struct MissionEventBannerView: View {
    @ObservedObject var viewModel: SolarSystemViewModel

    var body: some View {
        ZStack {
            if let banner = viewModel.currentEventBanner {
                let rgb = banner.missionColor
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.name.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)))
                    Text(banner.detail)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                // Card itself is horizontally centred in its parent row; inner
                // text remains leading-aligned for readability.
                .frame(maxWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.missionOrange.opacity(0.35), lineWidth: 1)
                        )
                )
                .transition(.asymmetric(
                    // Banner now lives at top-centre, so it slides down into
                    // view rather than up from below.
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
                .id(banner.id)  // re-trigger animation on each new event
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: viewModel.currentEventBanner?.id)
    }
}

// MARK: - Formatting helpers

/// Format Mission Elapsed Time as `T+Nd HH:MM:SS` for >= 24h, else `T+HH:MM:SS`.
func formatMET(_ hours: Double) -> String {
    let totalSeconds = Int(hours * 3600)
    let days = totalSeconds / 86400
    let h = (totalSeconds % 86400) / 3600
    let m = (totalSeconds % 3600) / 60
    let s = totalSeconds % 60
    if days > 0 {
        return String(format: "T+%dd %02d:%02d:%02d", days, h, m, s)
    }
    return String(format: "T+%02d:%02d:%02d", h, m, s)
}

/// Format distance for the telemetry panel — AU for heliocentric missions,
/// kilometres for geocentric lunar missions. Thousands separator via the
/// locale-independent `%,` style.
func formatDistance(_ tel: MissionTelemetry) -> String {
    if tel.isHeliocentric, let au = tel.distanceAU {
        return String(format: "%.3f AU", au)
    }
    let km = tel.distanceKm
    if km >= 1000 {
        return String(format: "%.0fk km", km / 1000)
    }
    return String(format: "%.0f km", km)
}

/// Format speed in km/s with two decimals.
func formatSpeed(_ kmS: Double) -> String {
    if kmS >= 100 {
        return String(format: "%.0f km/s", kmS)
    }
    return String(format: "%.2f km/s", kmS)
}
