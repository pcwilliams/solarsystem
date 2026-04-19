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

                    controlsBar
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

    // MARK: - Controls Bar

    /// Bottom toolbar with play/pause, time scale, orbit/label toggles, and planet picker.
    private var controlsBar: some View {
        HStack(spacing: 16) {
            // Play/Pause toggle
            Button(action: { viewModel.isPaused.toggle() }) {
                Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
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
                Button("Reset to Now") { viewModel.resetToNow() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gauge.with.dots.needle.67percent")
                    Text(formatTimeScale(viewModel.timeScale))
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }

            Spacer()

            // Toggle orbital path visibility
            Button(action: { viewModel.toggleOrbits() }) {
                Image(systemName: viewModel.showOrbits ? "circle.circle.fill" : "circle.circle")
                    .foregroundColor(viewModel.showOrbits ? .orange : .gray)
            }

            // Label category toggles (planets, moons, stars)
            Menu {
                // iOS menus render bottom-to-top, so reverse order for visual top-to-bottom
                Button {
                    viewModel.showStarLabels.toggle()
                } label: {
                    Label("Stars", systemImage: viewModel.showStarLabels ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    viewModel.showMoonLabels.toggle()
                } label: {
                    Label("Moons", systemImage: viewModel.showMoonLabels ? "checkmark.circle.fill" : "circle")
                }
                Button {
                    viewModel.showPlanetLabels.toggle()
                } label: {
                    Label("Planets", systemImage: viewModel.showPlanetLabels ? "checkmark.circle.fill" : "circle")
                }
            } label: {
                Image(systemName: (viewModel.showPlanetLabels || viewModel.showMoonLabels || viewModel.showStarLabels) ? "tag.fill" : "tag")
                    .foregroundColor((viewModel.showPlanetLabels || viewModel.showMoonLabels || viewModel.showStarLabels) ? .orange : .gray)
            }

            // Satellites menu (ISS toggle — extensible if we add more satellites later)
            Menu {
                Button {
                    viewModel.showISS.toggle()
                } label: {
                    Label("ISS", systemImage: viewModel.showISS ? "checkmark.circle.fill" : "circle")
                }
            } label: {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(viewModel.showISS ? .orange : .gray)
            }

            // Missions dropdown (rocket icon → list of 11 missions + Stop replay)
            MissionsMenu(viewModel: viewModel)

            // Quick-jump to any planet
            Menu {
                Button("Overview") { viewModel.resetCamera() }
                Divider()
                Button("Sun") { viewModel.focusOnBody(named: "Sun") }
                ForEach(SolarSystemData.allPlanets, id: \.id) { planet in
                    Button(planet.name) { viewModel.focusOnBody(named: planet.name) }
                }
            } label: {
                Image(systemName: "globe")
                    .foregroundColor(.orange)
            }

            // Reset to full solar system overview
            Button(action: { viewModel.resetCamera() }) {
                Image(systemName: "house.fill")
                    .foregroundColor(.white)
            }

            // Credits / About
            Button(action: { showCredits = true }) {
                Image(systemName: "info.circle")
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
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

    // MARK: - Helpers

    /// Format the time scale value for display (e.g. "1,000x", "-100,000x", "1Mx").
    private func speedButton(_ title: String, scale: Double) -> some View {
        Button {
            viewModel.timeScale = scale
        } label: {
            Label(title, systemImage: viewModel.timeScale == scale ? "checkmark" : "")
        }
    }

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
