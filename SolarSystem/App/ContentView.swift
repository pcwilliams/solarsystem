// ContentView.swift
// SolarSystem
//
// Root view combining the 3D SceneKit scene with SwiftUI overlay controls.
// Hosts the scene view, screen-space planet/moon/star labels, time/zoom
// controls, and the info panel for the currently selected body.

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SolarSystemViewModel()
    @State private var showControls = true
    @State private var showCredits = false

    var body: some View {
        ZStack {
            // 3D SceneKit scene (full-screen, behind all overlays)
            SolarSystemSceneView(
                scene: viewModel.scene,
                onBodyTapped: { body in
                    viewModel.selectedBody = body
                    viewModel.focusOnBody(named: body.name)
                },
                onDoubleTap: {
                    viewModel.resetCamera()
                },
                onViewReady: { view, coordinator in
                    viewModel.scnView = view
                    viewModel.cameraCoordinator = coordinator
                }
            )
            .ignoresSafeArea()

            // Screen-space labels projected from 3D world positions
            if viewModel.showPlanetLabels || viewModel.showMoonLabels || viewModel.showStarLabels {
                labelsOverlay
            }

            // UI chrome: info panel, zoom slider, and bottom control bar
            VStack(spacing: 0) {
                InfoPanelView(
                    celestialBody: viewModel.selectedBody,
                    currentDate: viewModel.currentDate,
                    timeScale: viewModel.timeScale,
                    onDismiss: {
                        viewModel.selectedBody = nil
                    }
                )

                Spacer()

                if showControls {
                    // Mission telemetry is pinned bottom-left, above the timeline
                    // slider. The event banner lives as a separate top-centre
                    // overlay so it doesn't occlude the vehicle marker / Moon
                    // when mission highlights fire.
                    MissionTelemetryPanel(viewModel: viewModel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)

                    if viewModel.activeMissionId != nil {
                        MissionTimelineSlider(viewModel: viewModel)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    }

                    // Horizontal zoom slider across the bottom
                    zoomSlider
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)

                    ControlsBarView(
                        isPaused: $viewModel.isPaused,
                        timeScale: $viewModel.timeScale,
                        showPlanetLabels: $viewModel.showPlanetLabels,
                        showMoonLabels: $viewModel.showMoonLabels,
                        showStarLabels: $viewModel.showStarLabels,
                        showISS: $viewModel.showISS,
                        activeMissionId: $viewModel.activeMissionId,
                        showOrbits: viewModel.showOrbits,
                        missions: viewModel.missionManager.missions,
                        planets: SolarSystemData.allPlanets,
                        onToggleOrbits: { viewModel.toggleOrbits() },
                        onResetCamera: { viewModel.resetCamera() },
                        onResetToNow: { viewModel.resetToNow() },
                        onShowCredits: { showCredits = true },
                        onFocusBody: { viewModel.focusOnBody(named: $0) },
                        onCancelMission: { viewModel.cancelMission() }
                    )
                    .equatable()
                }
            }

            // Event banner overlay — top-centre of the screen, below the date
            // bar. Kept out of the main VStack so it floats over the scene
            // without pushing telemetry / timeline / controls around when it
            // appears and disappears.
            VStack(spacing: 0) {
                // Reserve space for the info panel so the banner doesn't
                // overlap the date / body info at the very top.
                Color.clear.frame(height: 88)
                MissionEventBannerView(viewModel: viewModel)
                    .padding(.horizontal, 16)
                Spacer()
            }
        }
        .onAppear {
            viewModel.startAnimation()
        }
        .onDisappear {
            viewModel.stopAnimation()
        }
        .preferredColorScheme(.dark)
        #if os(iOS)
        // Keep the system status bar visible on iOS (the date bar sits below it).
        // macOS has no equivalent — the modifier is unavailable.
        .statusBarHidden(false)
        #endif
        .sheet(isPresented: $showCredits) {
            CreditsView()
        }
    }

    // MARK: - Zoom Slider

    /// Vertical slider on the right edge for logarithmic camera zoom control.
    /// Top = zoomed out (far), bottom = zoomed in (close).
    private var zoomSlider: some View {
        let thumbSize: CGFloat = 10

        return HStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.orange.opacity(0.4))

            GeometryReader { geo in
                let trackWidth = geo.size.width

                ZStack(alignment: .leading) {
                    // Thin track
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(.orange.opacity(0.15))
                        .frame(height: 1)

                    // Filled portion (left = zoomed in)
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(.orange.opacity(0.4))
                        .frame(width: max(0, (1.0 - viewModel.zoomLevel) * trackWidth), height: 1)

                    // Thumb
                    Circle()
                        .fill(Color.orange.opacity(0.7))
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(x: (1.0 - viewModel.zoomLevel) * trackWidth - thumbSize / 2)
                }
                .frame(height: 20)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            viewModel.isZooming = true
                            // Left = close (zoom 0), right = far (zoom 1)
                            let fraction = 1.0 - max(0, min(1, value.location.x / trackWidth))
                            viewModel.applyZoom(fraction)
                        }
                        .onEnded { _ in
                            viewModel.isZooming = false
                        }
                )
            }
            .frame(height: 20)

            Image(systemName: "minus")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.orange.opacity(0.4))
        }
    }

    // MARK: - Labels Overlay

    /// SwiftUI overlay that renders screen-projected labels for planets, moons, and stars.
    private var labelsOverlay: some View {
        GeometryReader { geo in
            ForEach(viewModel.screenLabels) { label in
                Text(label.name)
                    .font(.system(size: label.isStar ? 9 : (label.isMoon ? 10 : 12),
                                  weight: label.isStar ? .regular : .medium))
                    .foregroundColor(.white.opacity(label.isStar ? 0.35 : (label.isMoon ? 0.6 : 0.85)))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.focusOnBody(named: label.name)
                    }
                    // `screenPoint` is already offset above the body by the
                    // on-screen radius + a small margin (see
                    // `SolarSystemViewModel.projectLabel`), so no extra fixed
                    // vertical offset is needed here.
                    .position(x: label.screenPoint.x, y: label.screenPoint.y)
            }
        }
        .ignoresSafeArea()
    }

}

// MARK: - Controls Bar

/// Bottom toolbar with play/pause, time scale, orbit/label toggles,
/// satellites, missions, and planet picker.
///
/// Lives in its own `Equatable` View so it doesn't re-evaluate when the
/// parent `SolarSystemViewModel`'s per-frame `@Published` properties tick
/// (`currentDate`, `screenLabels`, `missionTelemetry`). Without this,
/// `ContentView.body` rebuilds the toolbar HStack at ~20 Hz during
/// simulation, which made every `Menu` popover unreliable: taps landed on
/// stale views, dropdowns clipped mid-render, and items occasionally
/// failed to register. Inputs are explicit `@Binding`s and closures so
/// the auto-synthesized equality (plus the explicit `==` below) skips
/// rebuild whenever no toolbar-relevant state has changed.
private struct ControlsBarView: View, Equatable {
    @Binding var isPaused: Bool
    @Binding var timeScale: Double
    @Binding var showPlanetLabels: Bool
    @Binding var showMoonLabels: Bool
    @Binding var showStarLabels: Bool
    @Binding var showISS: Bool
    @Binding var activeMissionId: String?

    let showOrbits: Bool
    let missions: [Mission]
    let planets: [CelestialBody]

    let onToggleOrbits: () -> Void
    let onResetCamera: () -> Void
    let onResetToNow: () -> Void
    let onShowCredits: () -> Void
    let onFocusBody: (String) -> Void
    let onCancelMission: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isPaused == rhs.isPaused
            && lhs.timeScale == rhs.timeScale
            && lhs.showPlanetLabels == rhs.showPlanetLabels
            && lhs.showMoonLabels == rhs.showMoonLabels
            && lhs.showStarLabels == rhs.showStarLabels
            && lhs.showISS == rhs.showISS
            && lhs.activeMissionId == rhs.activeMissionId
            && lhs.showOrbits == rhs.showOrbits
        // missions / planets are static immutable lists; closures aren't
        // comparable. Skipping both is safe — neither carries state that
        // should force a rebuild on its own.
    }

    var body: some View {
        HStack(spacing: 16) {
            // Play/Pause toggle
            Button(action: { isPaused.toggle() }) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .foregroundColor(.white)
            }

            // Time scale picker (real-time through 1Mx, plus reverse options)
            Menu {
                speedButton("Real-time (1x)", scale: 1.0)
                speedButton("Fast (100x)", scale: 100.0)
                speedButton("1,000x", scale: 1000.0)
                speedButton("10,000x", scale: 10000.0)
                speedButton("100,000x", scale: 100000.0)
                speedButton("1,000,000x", scale: 1000000.0)
                Divider()
                speedButton("Slow (0.1x)", scale: 0.1)
                speedButton("Reverse (-1x)", scale: -1.0)
                speedButton("Reverse (-1,000x)", scale: -1000.0)
                speedButton("Reverse (-100,000x)", scale: -100000.0)
                Divider()
                Button("Reset to Now") { onResetToNow() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                    Text(formatTimeScale(timeScale))
                        .font(.caption)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundColor(.orange)
            }

            Spacer()

            // Toggle orbital path visibility
            Button(action: onToggleOrbits) {
                Image(systemName: showOrbits ? "circle.circle.fill" : "circle.circle")
                    .foregroundColor(showOrbits ? .orange : .gray)
            }

            // Label category toggles (planets, moons, stars)
            Menu {
                // iOS menus render bottom-to-top, so reverse order for visual top-to-bottom
                Button {
                    showStarLabels.toggle()
                } label: {
                    Label("Stars", systemImage: showStarLabels ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    showMoonLabels.toggle()
                } label: {
                    Label("Moons", systemImage: showMoonLabels ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    showPlanetLabels.toggle()
                } label: {
                    Label("Planets", systemImage: showPlanetLabels ? "checkmark.circle.fill" : "circle")
                }
            } label: {
                Image(systemName: (showPlanetLabels || showMoonLabels || showStarLabels) ? "tag.fill" : "tag")
                    .foregroundColor((showPlanetLabels || showMoonLabels || showStarLabels) ? .orange : .gray)
            }

            // ISS toggle (direct button — same pattern as the orbits toggle).
            // If more satellites get added later, swap this for a Menu again.
            Button(action: { showISS.toggle() }) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(showISS ? .orange : .gray)
            }

            // Missions dropdown (rocket icon → list of 11 missions + Stop replay)
            MissionsMenu(activeMissionId: $activeMissionId,
                         missions: missions,
                         onCancel: onCancelMission)

            // Quick-jump to any planet
            Menu {
                Button("Overview") { onResetCamera() }
                Divider()
                Button("Sun") { onFocusBody("Sun") }
                ForEach(planets, id: \.id) { planet in
                    Button(planet.name) { onFocusBody(planet.name) }
                }
            } label: {
                Image(systemName: "globe")
                    .foregroundColor(.orange)
            }

            // Reset to full solar system overview
            Button(action: onResetCamera) {
                Image(systemName: "house.fill")
                    .foregroundColor(.white)
            }

            // Credits / About
            Button(action: onShowCredits) {
                Image(systemName: "info.circle")
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func speedButton(_ title: String, scale: Double) -> some View {
        Button {
            timeScale = scale
        } label: {
            Label(title, systemImage: timeScale == scale ? "checkmark" : "")
        }
    }

    /// Format the time scale value for display (e.g. "1,000x", "-100,000x", "1Mx").
    private func formatTimeScale(_ scale: Double) -> String {
        let absScale = abs(scale)
        let prefix = scale < 0 ? "-" : ""
        if absScale >= 1_000_000 {
            return "\(prefix)\(String(format: "%.0f", absScale / 1_000_000))Mx"
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = absScale < 1 ? 1 : 0
            let formatted = formatter.string(from: NSNumber(value: absScale)) ?? "\(absScale)"
            return "\(prefix)\(formatted)x"
        }
    }
}
