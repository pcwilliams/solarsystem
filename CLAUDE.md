
# iOS Development Conventions

Native iOS apps built with Swift and SwiftUI. No storyboards, no external dependencies.

## Tech Stack

- **Language:** Swift 5
- **UI Framework:** SwiftUI (no storyboards, no XIBs)
- **Minimum Target:** iOS 17.0+ (some projects use iOS 18.0+)
- **Xcode:** 16+
- **Device:** iPhone only (`TARGETED_DEVICE_FAMILY = 1`)
- **Orientation:** Portrait only
- **Dependencies:** Zero external dependencies — pure Apple frameworks only (SwiftUI, MapKit, CoreLocation, Photos, CryptoKit, Swift Charts, etc.)

## Architecture

All projects follow **MVVM** with SwiftUI's reactive data binding:

- **View models** are `ObservableObject` classes with `@Published` properties, observed via `@StateObject` in views
- **Views** are declarative SwiftUI — no UIKit unless wrapping a system controller (e.g. `SFSafariViewController`)
- **Services/API clients** use the `actor` pattern for thread safety
- **Networking** uses native `URLSession` with `async/await` — no external HTTP libraries
- **View models** are annotated `@MainActor` when they drive UI state

## Project Structure

Each project follows this standard layout:

```
ProjectName/
├── ProjectName.xcodeproj/
├── CLAUDE.md                    # Developer reference
├── README.md                    # User-facing documentation
├── architecture.html            # Interactive Mermaid.js architecture diagrams
├── tutorial.html                # Build narrative with prompts and responses
└── ProjectName/
    ├── App/
    │   ├── ProjectNameApp.swift # @main entry point
    │   └── ContentView.swift    # Root view / navigation
    ├── Models/                  # Data model structs and SwiftData @Models
    ├── Views/                   # SwiftUI views
    │   └── Components/          # Reusable view components
    ├── Services/                # API clients, managers, business logic
    ├── ViewModels/              # ObservableObject state management
    ├── Extensions/              # Formatters and helpers
    └── Assets.xcassets/
        ├── AppIcon.appiconset/  # 1024x1024 icons (standard, dark, tinted)
        └── AccentColor.colorset/
```

Smaller projects (e.g. Where) may flatten this into fewer files — simplicity over ceremony.

## Xcode Project File (project.pbxproj)

Projects are created and maintained by writing `project.pbxproj` directly, not via the Xcode GUI. When adding new Swift files to a target that doesn't use file system sync, register in four places:

1. **PBXBuildFile section** — build file entry
2. **PBXFileReference section** — file reference entry
3. **PBXGroup** — add to the appropriate group's `children` list
4. **PBXSourcesBuildPhase** — add build file to the target's Sources phase

ID patterns vary per project but follow a consistent incrementing convention within each project. Test targets may use `PBXFileSystemSynchronizedRootGroup` (Xcode 16+), meaning test files are auto-discovered.

## Build Verification

Always verify the build after any code change:

```bash
xcodebuild -project ProjectName.xcodeproj -scheme ProjectName \
  -destination 'generic/platform=iOS' build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

A clean result ends with `** BUILD SUCCEEDED **`. Fix any errors before considering a task complete.

## Testing

```bash
xcodebuild -project ProjectName.xcodeproj -scheme ProjectName \
  -destination 'platform=iOS Simulator,name=iPhone 16' test \
  CODE_SIGNING_ALLOWED=NO
```

- Use **in-memory containers** for SwiftData tests (fast, isolated)
- Use the **Swift Testing framework** (`import Testing`, `@Test`, `#expect()`) for newer projects
- **Extract pure decision logic as `internal static` methods** with explicit parameters so tests can inject values directly — avoid testing through singletons, UserDefaults, or system frameworks
- Test files that use Foundation types must `import Foundation` alongside `import Testing`

### Simulator Testing with Launch Arguments

For apps with multiple modes or views, add **launch argument parsing** so visual testing can be fully automated from the command line — never try to tap simulator UI with AppleScript (it's unreliable). Parse `ProcessInfo.processInfo.arguments` in the root view to accept flags like `-mode <value>`.

**Launch arguments must override persisted settings.** When an app uses `@AppStorage` or `UserDefaults`, launch arguments must be applied *after* persistence loads (e.g. in `onAppear`) so they take priority. Return optionals from launch-arg parsers (nil = no override).

```swift
// In ContentView or root view
private static func initialMode() -> Mode {
    let args = ProcessInfo.processInfo.arguments
    if let idx = args.firstIndex(of: "-mode"), idx + 1 < args.count {
        return Mode(rawValue: args[idx + 1]) ?? .default
    }
    return .default
}
```

Then test each mode from the command line:

```bash
xcrun simctl install booted path/to/App.app
xcrun simctl privacy booted grant microphone com.bundle.id  # if needed
xcrun simctl terminate booted com.bundle.id
xcrun simctl launch booted com.bundle.id -- -mode someMode
sleep 2
xcrun simctl io booted screenshot /tmp/screenshot.png
```

This pattern was established in ShiftingSands and adopted in Spectrum. Every new project with multiple visual states should support this from the start.

### Bundled Test Files for Hardware-Dependent Features

When a feature depends on hardware input (microphone, GPS, camera), create **bundled test files** that exercise the same code path in the simulator:

- **Audio**: Generate WAV files with Python — pure tones (440Hz sine), multi-tone sequences, periodic beats. Bundle and play via `-testfile <name>` launch argument.
- **Location**: Bundle JSON files with known GPS coordinates for map-based testing.
- **Images**: Bundle sample photos with known EXIF data for photo-processing features.

The DSP/processing pipeline shouldn't know or care whether input comes from hardware or a test file.

```python
import wave, struct, math
sample_rate = 44100
samples = []
for freq, duration in [(261.63, 1.5), (329.63, 1.5), (440.0, 1.5), (0, 1.0)]:
    for i in range(int(sample_rate * duration)):
        t = i / sample_rate
        value = 0.7 * math.sin(2 * math.pi * freq * t) if freq > 0 else 0
        samples.append(int(value * 32767))
with wave.open('test.wav', 'w') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(sample_rate)
    f.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
```

### Diagnostic Logging for Algorithm Debugging

For complex algorithms (DSP, ML, signal processing), add **structured diagnostic logging** gated behind a launch argument:

```swift
// In the engine/service
static var verboseLogging = false

// In the algorithm
if Self.verboseLogging {
    alog("PITCH DBG: acPeak=\(peak) lag=\(lag) freq=\(freq)Hz")
}

// In ContentView onAppear
if args.contains("-pitchlog") { AudioEngine.verboseLogging = true }
```

**What to log:** algorithm confidence metrics, which branch/threshold was taken, input characteristics, state changes.

**What NOT to log every frame:** raw sample values, full array contents, unchanged state.

Use change-only logging for display state and periodic logging for diagnostics (every Nth frame).

### Reading Logs from Simulator and Device

```bash
# Simulator: read the app's Documents directory
CONTAINER=$(xcrun simctl get_app_container booted com.bundle.id data)
cat "$CONTAINER/Documents/app.log"

# Clear log before a test run
> "$CONTAINER/Documents/app.log"

# Device: stream logs via:
xcrun devicectl device syslog --device <udid>
```

### Performance Testing in the DSP/Rendering Pipeline

For real-time processing, measure execution time against the time budget:

```swift
let start = CACurrentMediaTime()
// ... processing ...
let elapsed = CACurrentMediaTime() - start
dspTimingSum += elapsed
dspTimingCount += 1
if elapsed > dspTimingMax { dspTimingMax = elapsed }
if dspTimingCount % 100 == 0 {
    let avgMs = (dspTimingSum / Double(dspTimingCount)) * 1000
    let maxMs = dspTimingMax * 1000
    let budgetMs = Double(bufferSize) / Double(sampleRate) * 1000
    alog("DSP PERF: avg=\(avgMs)ms, max=\(maxMs)ms, budget=\(budgetMs)ms")
}
```

Budget = time between callbacks (e.g. 2048 samples at 44.1kHz = 46.4ms). If average exceeds ~50% of budget, optimise before adding features.

### Simulator vs Device Differences

The simulator does NOT replicate everything. Always test on device for:

- **Microphone input** (simulator has no mic hardware)
- **GPS / CoreLocation** (simulator uses simulated locations)
- **Audio session behaviour** (`.playAndRecord` fails on simulator — use `.playback` with `#if targetEnvironment(simulator)`)
- **Sample rates** (simulator often uses 44.1kHz, device may use 48kHz — parameterise, don't hardcode)
- **Real-world signal characteristics** (voice has harmonics, vibrato, breath noise that pure test tones lack)
- **Hardware format edge cases** (0 Hz sample rate, 0 input channels — detect and alert the user)

## Key Patterns

### Persistence

- **SwiftData** for structured app data (e.g. PillRecord)
- **UserDefaults / @AppStorage** for preferences, settings, and cache
- **iOS Keychain** for API credentials and secrets (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **JSON encoding** in UserDefaults for lightweight structured data (e.g. portfolio, saved places)

### Networking

- **Graceful degradation:** The app should work with reduced functionality when API calls fail. Isolate independent API calls in separate `do/catch` blocks so one failure doesn't take down the others
- **Task cancellation:** Cancel in-flight tasks before starting new ones. Check `Task.isCancelled` before publishing results
- **Debouncing:** Use 0.8-second debounce for rapid user interactions (e.g. map panning) to prevent API spam
- **Caching:** Cache API responses with TTLs in UserDefaults (e.g. 5-min for quotes, 30-min for historical data)

### Concurrency

- **Actor-based services** for thread-safe API clients
- **`async let` for parallel fetching** of independent data
- Wrap work in an unstructured `Task` inside `.refreshable` to prevent SwiftUI from cancelling structured concurrency children when `@Published` properties trigger re-renders
- **`Task.detached(.utility)`** for background work like photo library scanning
- **Swift 6 concurrency:** Use `guard let self else { return }` in detached task closures; copy mutable `var` to `let` before `await MainActor.run`

### Timers

- Prefer **one-shot `DispatchWorkItem`** over polling `Timer.publish`
- Avoid always-running timers — schedule on demand, cancel on completion

### SwiftUI

- **`.id()` modifier** on views for animated identity changes (e.g. month transitions)
- **GeometryReader** for proportional layouts
- **Asymmetric slide transitions** with tracked direction state
- **NavigationStack** with `.toolbar` and `.sheet` for settings
- **`.refreshable`** for pull-to-refresh
- **Segmented pickers** for mode selection (chart periods, map styles, etc.)
- **@AppStorage** for persisting UI preferences across launches
- **`.contentShape(Rectangle())`** for full-row tap targets

## App Icons

Generated programmatically using **Python/Pillow** — not designed in a graphics tool. Three variants at 1024x1024:

- **Standard** (light mode)
- **Dark** (dark mode)
- **Tinted** (greyscale for tinted mode)

Referenced in `Contents.json` with `luminosity` appearance variants. Use `Image.new("RGB", ...)` not `"RGBA"` — iOS strips alpha for app icons, causing compositing artefacts with semi-transparent overlays.

## Documentation

Each project includes four living documents that must be kept up to date:

### CLAUDE.md (developer reference)

Must be updated whenever: a file, model, view, or service is added/removed; an architectural decision is made; a new API is integrated; a non-obvious bug is fixed; build configuration or project structure changes.

This is the single source of truth for project context. A future session should be able to read CLAUDE.md and understand the entire project without exploring the codebase.

### README.md (user-facing)

Must be updated whenever: features are added/changed/removed; setup instructions change; project structure changes significantly; screenshots become outdated.

### architecture.html (architecture diagrams)

Interactive Mermaid.js diagrams. Must be updated whenever: view hierarchy changes; data flow changes; new major subsystems are added.

Use `graph TD` for readability. Load Mermaid.js from CDN. Apply the shared dark theme with CSS custom properties and project-appropriate accent colours.

### tutorial.html (build narrative)

A step-by-step record of how the app was built. Must be updated whenever: a significant new feature is added; a major refactor is made; an interesting problem is solved through iterative prompting.

**Prompt tone:** Use collaborative language — "Could we try...", "How about...", "I'd love it if..." rather than imperatives. Use "I'm seeing..." for problems rather than assertive declarations.

### Formatting conventions

- Plain Markdown in `.md` files (no inline HTML except README badges). Images use `![alt](src)` syntax, not `<img>` tags
- HTML docs use a shared dark theme with CSS custom properties and Mermaid.js loaded from CDN
- HTML docs include a hero screenshot in a phone-frame wrapper (black background, rounded corners, drop shadow) below the title/badges

## Common Gotchas

- **Keychain: always delete before add** to avoid `errSecDuplicateItem`
- **SwiftUI `.refreshable` cancels structured concurrency** — wrap network calls in an unstructured `Task`
- **Wikimedia geosearch caps at 10,000m radius** — clamp before sending
- **Wikipedia disambiguation pages** — filter out articles where extract contains "may refer to"

---


# macOS Development Conventions

Native macOS apps built with Swift and SwiftUI. No storyboards, no external dependencies.

## Tech Stack

- **Language:** Swift 5
- **UI Framework:** SwiftUI (no storyboards, no XIBs; AppKit only when wrapping a system controller)
- **Minimum Target:** macOS 14.0+
- **Xcode:** 16+
- **Dependencies:** Zero external dependencies — pure Apple frameworks only (SwiftUI, AppKit, AVFoundation, MusicKit, etc.)

## Architecture

All projects follow **MVVM** with SwiftUI's reactive data binding:

- **View models** are `ObservableObject` classes with `@Published` properties, observed via `@StateObject` in views
- **Views** are declarative SwiftUI — no AppKit unless wrapping a system controller
- **Services/API clients** use the `actor` pattern for thread safety
- **Networking** uses native `URLSession` with `async/await` — no external HTTP libraries
- **View models** are annotated `@MainActor` when they drive UI state

## Project Structure

Each project follows this standard layout:

```
ProjectName/
├── ProjectName.xcodeproj/
├── CLAUDE.md                    # Developer reference
├── README.md                    # User-facing documentation
├── architecture.html            # Interactive Mermaid.js architecture diagrams
├── tutorial.html                # Build narrative with prompts and responses
└── ProjectName/
    ├── App/
    │   ├── ProjectNameApp.swift # @main entry point
    │   └── ContentView.swift    # Root view / navigation
    ├── Models/                  # Data model structs and SwiftData @Models
    ├── Views/                   # SwiftUI views
    │   └── Components/          # Reusable view components
    ├── Services/                # API clients, managers, business logic
    ├── ViewModels/              # ObservableObject state management
    ├── Extensions/              # Formatters and helpers
    └── Assets.xcassets/
        ├── AppIcon.appiconset/  # 1024x1024 icon
        └── AccentColor.colorset/
```

## Xcode Project File (project.pbxproj)

Projects are created and maintained by writing `project.pbxproj` directly, not via the Xcode GUI. When adding new Swift files to a target that doesn't use file system sync, register in four places:

1. **PBXBuildFile section** — build file entry
2. **PBXFileReference section** — file reference entry
3. **PBXGroup** — add to the appropriate group's `children` list
4. **PBXSourcesBuildPhase** — add build file to the target's Sources phase

## Build Verification

Always verify the build after any code change:

```bash
xcodebuild -project ProjectName.xcodeproj -scheme ProjectName \
  -destination 'generic/platform=macOS' build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

A clean result ends with `** BUILD SUCCEEDED **`. Fix any errors before considering a task complete.

## Testing

```bash
xcodebuild -project ProjectName.xcodeproj -scheme ProjectName \
  -destination 'platform=macOS' test \
  CODE_SIGNING_ALLOWED=NO
```

- Use **in-memory containers** for SwiftData tests (fast, isolated)
- Use the **Swift Testing framework** (`import Testing`, `@Test`, `#expect()`) for newer projects
- **Extract pure decision logic as `internal static` methods** with explicit parameters so tests can inject values directly
- Test files that use Foundation types must `import Foundation` alongside `import Testing`
- macOS apps run directly on the Mac — test and iterate without a simulator

## Key Patterns

### Persistence

- **SwiftData** for structured app data
- **UserDefaults / @AppStorage** for preferences, settings, and cache
- **macOS Keychain** for API credentials and secrets (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **JSON encoding** in UserDefaults for lightweight structured data

### Networking

- **Graceful degradation:** The app should work with reduced functionality when API calls fail. Isolate independent API calls in separate `do/catch` blocks
- **Task cancellation:** Cancel in-flight tasks before starting new ones. Check `Task.isCancelled` before publishing results
- **Debouncing:** Use 0.8-second debounce for rapid user interactions to prevent API spam
- **Caching:** Cache API responses with TTLs in UserDefaults

### Concurrency

- **Actor-based services** for thread-safe API clients
- **`async let` for parallel fetching** of independent data
- Wrap work in an unstructured `Task` inside `.refreshable` to prevent SwiftUI from cancelling structured concurrency children
- **`Task.detached(.utility)`** for background work
- **Swift 6 concurrency:** Use `guard let self else { return }` in detached task closures; copy mutable `var` to `let` before `await MainActor.run`

### Timers

- Prefer **one-shot `DispatchWorkItem`** over polling `Timer.publish`
- Avoid always-running timers — schedule on demand, cancel on completion

### SwiftUI (macOS)

- **NavigationSplitView** for sidebar + detail layouts
- **`.commands`** modifier for menu bar items
- **`NSOpenPanel` / `NSSavePanel`** wrapped in `NSViewControllerRepresentable` for file pickers
- **`@AppStorage`** for persisting UI preferences across launches
- **`.contentShape(Rectangle())`** for full-row tap targets
- **`Settings { ... }`** scene for the Preferences window

## App Icons

Generated programmatically using **Python/Pillow** — not designed in a graphics tool. Single variant at 1024x1024 (macOS does not use dark/tinted app icon variants the same way iOS does).

Referenced in `Contents.json`. Use `Image.new("RGB", ...)` not `"RGBA"`.

## Documentation

Each project includes four living documents that must be kept up to date:

### CLAUDE.md (developer reference)

Must be updated whenever: a file, model, view, or service is added/removed; an architectural decision is made; a new API is integrated; a non-obvious bug is fixed; build configuration or project structure changes.

### README.md (user-facing)

Must be updated whenever: features are added/changed/removed; setup instructions change; screenshots become outdated.

### architecture.html (architecture diagrams)

Interactive Mermaid.js diagrams. Use `graph TD` for readability. Load Mermaid.js from CDN. Apply the shared dark theme.

### tutorial.html (build narrative)

A step-by-step record of how the app was built. Use collaborative prompt tone — "Could we try...", "How about...", "I'd love it if..."

### Formatting conventions

- Plain Markdown in `.md` files. Images use `![alt](src)` syntax, not `<img>` tags
- HTML docs use a shared dark theme with CSS custom properties and Mermaid.js loaded from CDN

## Common Gotchas

- **Keychain: always delete before add** to avoid `errSecDuplicateItem`
- **SwiftUI `.refreshable` cancels structured concurrency** — wrap network calls in an unstructured `Task`
- **Sandbox entitlements:** macOS apps are sandboxed by default — ensure `com.apple.security.files.user-selected.read-write` or similar entitlements are set for file access
- **MusicKit / AppleScript:** `MusicKit` is the modern API for Apple Music access; `AppleScript` bridging via `NSAppleScript` is a fallback for operations MusicKit doesn't cover

---

# SolarSystem - Claude Code Developer Reference

## Overview

A GPU-accelerated solar system simulation for **iPhone and macOS**, using real Keplerian orbital mechanics (JPL J2000.0 elements) to calculate planet, moon, and Sun positions based on the current date and time. SceneKit renders the 3D scene with NASA/public-domain texture maps on all planets and major moons. 8,920 real stars from the Hipparcos catalogue form the backdrop, with correct positions, magnitudes, and colours. All bodies rotate at their real IAU sidereal rates with correct axial tilts. Custom gesture handling provides platform-native navigation: touch gestures on iOS (one-finger pan, two-finger orbit, pinch-to-zoom) and mouse / trackpad on macOS (left-drag pan, right-drag orbit, scroll / pinch zoom).

The app is a **single multi-platform target** — one Xcode target builds for both `iphoneos`/`iphonesimulator` and `macosx`. A thin `Platform.swift` abstraction file handles the UIKit↔AppKit type differences; everything above that file is 100% shared code.

Physics runs on CPU (lightweight trig per body per frame). Rendering runs on GPU via SceneKit with PBR materials, multi-layer Sun corona, and Saturn's rings with Cassini colour/transparency maps.

All 11 space missions from the companion web app are rendered as trajectory trails with multi-vehicle support, Moon-aligned waypoint frames, runtime lunar orbit/landing phases, timed event detection, live telemetry (MET, distance, speed), mission UI overlays (telemetry panel, timeline scrubber, event banners, 3D event labels), and a lazy-follow mission camera for lunar missions. The International Space Station is available as a procedural 3D model via the Satellites menu. See `../solarsystem-web/MISSIONS.md` for the shared specification.

## Port Status (Web → iOS)

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Centralised moon-distance compression (0.4→0.6), camera azimuth/elevation API, scaling unit tests | Complete |
| 2 | Mission data model, CatmullRom, MissionManager, Apollo 11 end-to-end, mission + Catmull tests | Complete |
| 3 | All 11 missions via bundled JSON export + autoTrajectory transfer arcs | Complete |
| 4 | Mission UI layer (menu, timeline slider, telemetry panel, event banners) | Complete |
| 5 | ISS satellite (procedural 3D model, Earth orbit) | Complete |
| 6 | Lazy-follow mission camera, 3D event labels, end-of-mission polish | Complete |

## Architecture

### Data Flow

```
Real Time (Date)
    -> Julian Centuries from J2000.0
        -> Keplerian Elements (JPL data, CPU)
            -> Heliocentric Ecliptic Coordinates
                -> Logarithmic Distance Scaling
                    -> SceneKit Node Positions (GPU)
                        -> IAU Rotation (axial tilt + spin)
                            -> SCNView (UIViewRepresentable)
                                -> SwiftUI Overlay (Labels, HUD, Zoom, Controls)
                                    -> Custom Camera Coordinator (gestures)
```

### Key Design Decisions

- **SceneKit over raw Metal**: PBR materials, lighting, camera, hit testing out of the box. GPU-accelerated, pure Apple framework.
- **CPU for orbital mechanics**: ~20 trig ops per body per frame = microseconds. No GPU compute benefit.
- **Custom camera controller**: SceneKit's built-in `allowsCameraControl` maintains internal state that conflicts with programmatic camera positioning. Replaced entirely with a `Coordinator` class managing explicit spherical camera state (target, distance, azimuth, elevation).
- **SwiftUI overlay labels**: 3D `SCNText` labels can't maintain constant screen size. Labels are projected from 3D positions to screen coordinates via a cached view × projection matrix (constructed from `camera.fieldOfView` + current viewport aspect — see Performance Debugging), rendered as SwiftUI `Text` views. Pixel-perfect, tappable, constant size at all zoom levels. Each label is offset above its body by the body's on-screen radius + 4 pt so the name sits just above the disc rather than covering it. Star labels are occluded behind planet discs.
- **Logarithmic distance scaling**: Real distances span 4 orders of magnitude. `log(1 + AU/0.5) * 15` preserves ordering while keeping everything visible.
- **Sqrt radius scaling**: `sqrt(km) * 0.00125` for planet radii. Jupiter 3.3x Earth (real 11.2x) while keeping small planets visible. Moons use real ratio to parent with 0.012 minimum floor.
- **Moon distance compression**: `pow(realRatio, SceneBuilder.moonDistExponent) * SceneBuilder.moonDistScale` where `moonDistExponent = 0.6` and `moonDistScale = 1.5`. Centralised constants (exported `nonisolated`) so mission trajectory rendering uses the same formula. With 0.6 the Moon sits at 17.6 Earth radii (real is 60.3, previous 0.4 exponent gave 8.8).
- **Momentary planet shortcuts**: Selecting a planet flies camera there then releases control — no per-frame tracking that locks out manual navigation. Framing uses a 0.8× base multiplier for moon-hosting bodies and 6.0× for moonless ones, scaled by viewport aspect so portrait phones frame tighter (`multiplier = base * (0.5 + 0.5 * min(aspect, 1))`). Camera azimuth is placed Sun-side of the target via `atan2(-x, -z) + 0.55 rad` so the target shows a two-thirds-lit crescent; elevation is 0.3 rad (~17°).
- **Missions as scene-graph groups**: Each mission is a `SCNNode` child of the scene. Geocentric missions (Apollo, Artemis) reposition the group to Earth's scene location every frame; heliocentric missions (Voyager, Cassini) stay at the origin. Trajectory line shape is pre-computed at initialisation — only the group position updates per frame.
- **Moon-aligned waypoint frame**: Lunar-mission waypoints are defined in km with +X toward the Moon at flyby time. At init, the Moon's ecliptic angle at the flyby instant is computed via `OrbitalMechanics.moonPosition`, and all waypoints are rotated to match, so any launch date yields a physically aligned trajectory.
- **Runtime lunar orbit / landing phases**: `moonOrbit`, `moonLanding`, and `moonOrbitReturn` on a vehicle trigger runtime cos/sin motion around the Moon's actual scene position (plane perpendicular to the Earth-Moon line). Both phases use the Moon's semi-major axis distance, not its actual (eccentric) distance, so vehicles stay glued to the rendered Moon mesh.
- **Centripetal CatmullRom**: Trajectories are smoothed with a pure-Swift centripetal Catmull-Rom implementation (alpha = 0.5) matching Three.js's `CatmullRomCurve3`. Sampling is time-parameterised (uniform time steps, not arc length) so the marker advances linearly with mission time.
- **Deferred launch-arg focus**: Coordinator isn't available during `init()`. A `pendingFocus` string is applied once the coordinator connects via `didSet`.
- **Throttled label updates**: Labels only re-project every 3rd frame to reduce SwiftUI overhead. Labels hide entirely during zoom slider drag.
- **Real star catalogue**: 8,920 stars from HYG (Hipparcos/Yale/Gliese) database, filtered to naked-eye visibility (mag <= 6.5). ~120 brightest named stars labelled.
- **IAU rotation model**: Every body has sidereal rotation period, axial obliquity, and prime meridian at J2000.0. Tidally locked moons match their orbital period. Saturn's rings counter-rotate to cancel parent spin.
- **Persisted settings**: Label toggles (planet/moon/star) and orbit visibility saved to UserDefaults.

## Platform abstraction (iOS + macOS)

The app is a single multi-platform target. 99% of the code is platform-neutral; the differences are funneled through one file and a handful of narrowly-scoped `#if` blocks.

### `Extensions/Platform.swift`

Defines the typealiases every other file references:

| Typealias | iOS resolves to | macOS resolves to |
|-----------|-----------------|-------------------|
| `PlatformColor` | `UIColor` | `NSColor` |
| `PlatformImage` | `UIImage` | `NSImage` |
| `PlatformView` | `UIView` | `NSView` |
| `PlatformViewRepresentable` | `UIViewRepresentable` | `NSViewRepresentable` |

Plus `makePlatformImage(cgImage:size:)` and `cgImage(from:)` helpers for UIImage↔NSImage bridging where the construction differs.

**Rule**: outside `Platform.swift` (and the gesture / animation-loop files flagged below), never write `UIColor`, `UIImage`, or UIKit/AppKit-typed names directly — use the `Platform…` aliases. The handful of files still using `#if canImport(UIKit)` are:

- `SolarSystemSceneView.swift` — gesture recognisers (UIKit vs AppKit APIs diverge meaningfully)
- `SolarSystemViewModel.swift` — frame-tick loop (CADisplayLink on iOS, Timer on macOS)
- `TextureGenerator.swift` — procedural texture drawing via `CGContext` (cross-platform, so actually no `#if` needed here once UIGraphicsImageRenderer was replaced)
- `ContentView.swift` + `CreditsView.swift` — SwiftUI modifiers that only exist on one platform (`.statusBarHidden`, `navigationBarTitleDisplayMode`, `topBarTrailing`)

### Gesture map (macOS)

| Input | Action | Implementation |
|-------|--------|----------------|
| Left-mouse drag | Pan (translate camera target) | `NSPanGestureRecognizer` with `buttonMask = 0x1` |
| Right-mouse drag | Orbit (azimuth + elevation) | `NSPanGestureRecognizer` with `buttonMask = 0x2` |
| Trackpad pinch | Zoom | `NSMagnificationGestureRecognizer` |
| Scroll wheel / 2-finger scroll | Zoom | `ScrollZoomSCNView` subclass overrides `scrollWheel(with:)` |
| Single click | Select body | `NSClickGestureRecognizer` (numberOfClicks = 1) |
| Double click | Reset to overview | `NSClickGestureRecognizer` (numberOfClicks = 2) |

The AppKit Y axis is inverted relative to UIKit, so the macOS pan / orbit handlers flip `dy` (`lastPanPoint.y - translation.y`) to keep the "drag up = look up" feel consistent with iOS. All the actual camera maths (`applyPan`, `applyOrbit`, `applyPinchZoom`) is shared between platforms.

### Frame-tick loop

`CADisplayLink` on both platforms — just constructed differently:

- **iOS**: `CADisplayLink(target: self, selector: ...)` on the main run loop, display-synchronised 30–60 Hz.
- **macOS 14+**: `scnView.displayLink(target: self, selector: ...)` — the NSView-bound form. Binds the link to whichever display the window is on so ticks stay synced to that screen's VBlank.

Both feed the same `advanceOneFrame()` path. A brief early experiment with `Timer.scheduledTimer` on macOS produced visible ~1-per-second stutters because Timer's cadence drifts in and out of phase with the 60 Hz refresh — abandoned in favour of the real display link.

Because the macOS display link needs an SCNView to bind to, `startAnimation()` may be called before the view connects (SwiftUI's `onAppear` can fire before `makeNSView` completes). The view model parks the request in `pendingAnimationStart` and the `cameraCoordinator.didSet` re-runs `startAnimation()` once the view arrives.

### SCNVector3 component types

`SCNVector3.x/y/z` is `Float` on iOS but `CGFloat` on macOS. Two helpers in `SCNVector3+Math.swift` hide the gap:

- `SCNVector3(_ x: Double, _ y: Double, _ z: Double)` — build a vector from Double components.
- `SCNVector3.adding(_ dx: Double, _ dy: Double, _ dz: Double) -> SCNVector3` — offset a vector by Double deltas, returning a new vector.

Use these anywhere the existing code was doing `SCNVector3(x, y, z)` with Float arithmetic — they keep one-line call sites working on both platforms.

## Project Structure

```
SolarSystem/
├── SolarSystem.xcodeproj/
├── CLAUDE.md
├── README.md
├── architecture.html
├── tutorial.html
├── SolarSystemTests/
│   ├── ScalingTests.swift            # Log distance, sqrt radius, moon compression (91 lines)
│   ├── CatmullRomTests.swift         # Centripetal curve endpoints, time sampling (98 lines)
│   ├── MissionTests.swift            # Rotation, anchors, autoTimeScale, transfer arcs, JSON load, event fire-once (~210 lines)
│   └── MissionUITests.swift          # MET / distance / speed formatting (~80 lines)
├── tools/
│   └── export-missions.mjs           # Node 22 extractor: web JS → bundled Missions.json (one-shot)
└── SolarSystem/
    ├── App/
    │   ├── SolarSystemApp.swift          # @main entry point (16 lines)
    │   └── ContentView.swift             # Root view, controls bar, zoom slider, labels overlay (273 lines)
    ├── Models/
    │   ├── CelestialBody.swift           # BodyType, PhysicalProperties, RotationProperties, CelestialBody (98 lines)
    │   ├── OrbitalElements.swift         # Keplerian element structs, angle helpers (94 lines)
    │   ├── SolarSystemData.swift         # JPL elements: 9 planets + 16 moons + Sun (438 lines)
    │   ├── Mission.swift                 # Mission, Vehicle, Waypoint, MissionEvent, MoonOrbit/Landing phases (166 lines)
    │   └── MissionData.swift             # JSON loader with DTO layer (decodes Resources/Missions.json, 161 lines)
    ├── Views/
    │   ├── SolarSystemSceneView.swift    # UIViewRepresentable + custom camera Coordinator (269 lines)
    │   ├── InfoPanelView.swift           # HUD: date, time scale badge, body info card (130 lines)
    │   ├── CreditsView.swift             # Credits overlay for texture and data sources (110 lines)
    │   └── MissionUIViews.swift          # MissionsMenu, TimelineSlider, TelemetryPanel, EventBanner (~250 lines)
    ├── Services/
    │   ├── OrbitalMechanics.swift        # Julian dates, Kepler solver, positions (184 lines)
    │   ├── SceneBuilder.swift            # Scene graph, materials, rings, glow, starfield, B-V colours, moonDist constants (615 lines)
    │   ├── TextureGenerator.swift        # Procedural Sun texture, glow textures (114 lines)
    │   ├── CatmullRom.swift              # Centripetal Catmull-Rom in SIMD3<Double>, time-parameterised (109 lines)
    │   └── MissionManager.swift          # Scene-node construction, per-frame update, telemetry, events (683 lines)
    ├── ViewModels/
    │   └── SolarSystemViewModel.swift    # State management, display link, label projection, zoom, mission wiring (620 lines)
    ├── Extensions/
    │   ├── SCNVector3+Math.swift         # worldRight/worldUp + cross-platform Double-based init (55 lines)
    │   └── Platform.swift                 # PlatformColor / Image / View / ViewRepresentable typealiases (~80 lines)
    ├── Textures/
    │   ├── earth_2k.jpg                  # NASA Blue Marble (5400x2700, 2.4 MB)
    │   ├── moon_2k.jpg                   # NASA LRO (1024x512, 136 KB)
    │   ├── jupiter_2k.jpg               # NASA Cassini PIA07782 (3601x1801, 431 KB)
    │   ├── saturn_2k.jpg                # Cassini composite (1800x900, 69 KB)
    │   ├── mars_2k.jpg                  # Viking MDIM21 mosaic (4096x2048, 2.6 MB)
    │   ├── mercury_2k.jpg              # MESSENGER (2048x1024, 852 KB)
    │   ├── venus_2k.jpg                # Atmosphere map (2048x1024, 224 KB)
    │   ├── uranus_2k.jpg               # Voyager-based (2048x1024, 76 KB)
    │   ├── neptune_2k.jpg              # Voyager-based (2048x1024, 236 KB)
    │   ├── pluto_2k.jpg                # NASA New Horizons (5926x2963, 3.8 MB)
    │   ├── io_2k.jpg                   # Voyager/Galileo (4096x2048, 997 KB)
    │   ├── europa_2k.jpg               # Voyager/Galileo (1024x512, 133 KB)
    │   ├── ganymede_2k.jpg             # Voyager/Galileo (4096x2048, 938 KB)
    │   ├── callisto_2k.jpg             # Voyager/Galileo (1800x900, 430 KB)
    │   ├── saturn_ring_color.jpg       # Ring colour map (915x64, 9 KB)
    │   ├── saturn_ring_alpha.gif       # Ring transparency (915x64, 28 KB)
    │   └── stars.csv                    # HYG catalogue: 8,920 stars (274 KB)
    ├── Resources/
    │   └── Missions.json                # 11 missions, 58 events, 213 waypoints (~80 KB); generated by tools/export-missions.mjs
    └── Assets.xcassets/
        ├── AppIcon.appiconset/          # Programmatic dark-mode solar system icon
        └── AccentColor.colorset/         # Orange (#FFAA33)
```

**Total: 17 Swift files, ~5,050 lines of app code + 4 test files, ~490 lines. 18 texture/data files (17 textures/CSV + Missions.json).**

## Celestial Bodies

### Planets (JPL J2000.0 Keplerian Elements)

| Body | a (AU) | e | I (deg) | Scene Radius | Rotation Period | Axial Tilt |
|------|--------|---|---------|-------------|-----------------|-----------|
| Mercury | 0.387 | 0.206 | 7.00 | 0.062 | 58.65 days | 0.03° |
| Venus | 0.723 | 0.007 | 3.39 | 0.097 | 243 days (retro) | 177.4° |
| Earth | 1.000 | 0.017 | 0.00 | 0.100 | 23.93 hours | 23.4° |
| Mars | 1.524 | 0.093 | 1.85 | 0.073 | 24.62 hours | 25.2° |
| Jupiter | 5.203 | 0.048 | 1.30 | 0.331 | 9.93 hours | 3.1° |
| Saturn | 9.537 | 0.054 | 2.49 | 0.302 | 10.66 hours | 26.7° |
| Uranus | 19.189 | 0.047 | 0.77 | 0.199 | 17.24 hours (retro) | 97.8° |
| Neptune | 30.070 | 0.009 | 1.77 | 0.196 | 16.11 hours | 28.3° |
| Pluto | 39.482 | 0.249 | 17.14 | 0.043 | 6.39 days (retro) | 122.5° |

### Moons (16 total, all tidally locked)

- **Earth**: Moon (27.32d, obliquity 6.7°)
- **Mars**: Phobos (0.32d), Deimos (1.26d)
- **Jupiter**: Io (1.77d), Europa (3.55d), Ganymede (7.15d), Callisto (16.69d)
- **Saturn**: Mimas (0.94d), Enceladus (1.37d), Tethys (1.89d), Dione (2.74d), Rhea (4.52d), Titan (15.95d), Iapetus (79.32d)

### Texture Sources

| Body | Source | Licence |
|------|--------|---------|
| Earth | NASA Blue Marble Next Generation | Public domain (US govt) |
| Moon | NASA LRO Camera | Public domain (US govt) |
| Mars | USGS Viking MDIM21 via Wikimedia | Public domain |
| Mercury | MESSENGER via Solar System Scope | CC-BY 4.0 |
| Venus | Atmosphere map, Solar System Scope | CC-BY 4.0 |
| Uranus | Voyager-based, Solar System Scope | CC-BY 4.0 |
| Neptune | Voyager-based, Solar System Scope | CC-BY 4.0 |
| Jupiter | NASA/JPL/SSI Cassini PIA07782 | Public domain |
| Saturn (+rings) | Cassini composite, Planet Pixel Emporium | Free non-commercial |
| Pluto | NASA/JHUAPL/SwRI New Horizons | Public domain |
| Io, Europa, Ganymede | Voyager/Galileo, Steve Albers | Public domain data |
| Callisto | Voyager/Galileo, Bjorn Jonsson | Public domain data |
| Stars | HYG Database v38 (Hipparcos/Yale/Gliese) | Public domain |

## Orbital Mechanics

### Shared astronomical constants

`OrbitalMechanics.j2000` (2451545.0) and `OrbitalMechanics.kmPerAU` (149,597,870.7) are the single source of truth for every date-to-epoch and AU-to-km conversion in the app. If you need either value elsewhere, reference the constant rather than inlining the literal — that way changes (e.g. the IAU revising the AU definition) propagate everywhere. Earth's radius in km is likewise referenced from `SolarSystemData.earth.physical.radiusKm` rather than hardcoded in mission compression maths.

### Calculation Pipeline

1. `julianDate(from: Date) -> Double` — Meeus algorithm, Gregorian to JD
2. `julianCenturies(from: Date) -> Double` — `(JD - 2451545.0) / 36525.0`
3. `elements.elements(at: T) -> CurrentElements` — Base + rate * T
4. `meanAnomaly = L - wBar` (normalised to [0, 2pi))
5. `solveKepler(M, e) -> E` — Newton-Raphson, initial guess `E0 = M + e*sin(M)`, tolerance 1e-8, max 50 iterations
6. `trueAnomaly(E, e) -> nu` — `2*atan2(sqrt(1+e)*sin(E/2), sqrt(1-e)*cos(E/2))`
7. `r = a * (1 - e*cos(E))` — heliocentric distance
8. Rotate by omega, I, w to ecliptic (x,y,z)

### Moon Positions

Simplified circular orbits with period-based mean motion: `M = longitudeAtEpoch + (2pi/period) * daysSinceJ2000`.

### IAU Rotation

Each body has `RotationProperties(periodHours, obliquity, w0, tidallyLocked)`. Applied per frame using quaternion composition: `tiltQuat * spinQuat` where tilt is around the X axis (fixed in space) and spin is around Y (the tilted pole). Euler angles can't do this correctly — SceneKit applies them in Y-X-Z order, causing the tilt axis to wobble with each spin cycle. Saturn's rings cancel the spin quaternion in local frame to stay fixed in the equatorial plane.

### Coordinate System

- **Orbital mechanics**: Heliocentric ecliptic (x,y in ecliptic plane, z perpendicular)
- **SceneKit**: x = ecliptic x, y = ecliptic z (up), z = -ecliptic y
- **Distance**: `log(1 + AU/0.5) * 15` scene units

## Rendering

### Scene Graph

```
SCNScene (black background)
├── Camera (custom-controlled, FOV 60°, zNear 0.01, zFar 1000)
├── Starfield (8,920 HYG stars, 4 brightness tiers, B-V colour, r=500)
├── Sun Light (omni, warm white, intensity 2000, falloff 0-500)
├── Ambient Light (intensity 500, 15% white)
├── Sun (r=0.8, emissive, procedural texture, 25.05-day rotation)
│   ├── Glow Inner (1.3x, additive, radial gradient)
│   ├── Glow Mid (1.8x, additive)
│   ├── Glow Outer (2.8x, additive)
│   └── Glow Corona (4.0x, additive)
├── [Planet] (PBR, NASA texture, IAU rotation)
│   ├── [Saturn Rings] (custom disc, radial UVs, Cassini textures, counter-rotated)
│   └── [Orbit Path] (line geometry, 180 segments)
└── [Moon] (PBR, texture or colour, tidally locked rotation)
```

### Star Rendering

- 8,920 stars parsed from bundled `stars.csv` (HYG v38)
- RA/Dec mapped to celestial sphere at r=500
- 4 brightness tiers with different point sizes (mag < 1.5: 3-8px, mag 5-6.5: 0.8-2px)
- Per-vertex B-V colour (blue-white O/B → white A → yellow G → orange K → red M)
- ~120 brightest named stars labelled (Sirius, Vega, Betelgeuse, etc.)
- Star labels occluded behind planet screen discs

### Saturn's Rings

Custom flat disc geometry with radial UV mapping:
- 72 radial segments x 4 ring segments
- `u` maps 0 (inner) to 1 (outer) — radially across the ring strip texture
- Cassini colour map + alpha transparency for ring density
- `lightingModel = .constant` for visibility
- Counter-rotated each frame to cancel parent planet's spin

## Missions

Ported from the web app (see `../solarsystem-web/MISSIONS.md` for the full specification shared between ports). All 11 missions (Artemis II, Apollo 8, Apollo 11, Apollo 13, Cassini-Huygens, Voyager 1, Voyager 2, Perseverance, New Horizons, Parker Solar Probe, BepiColombo) ship as of Phase 3.

### Where the data lives

The waypoint data is a one-shot export from `../solarsystem-web/js/missions.js`. Run `node tools/export-missions.mjs` whenever upstream waypoints change; the script evaluates the data-declaration portion of missions.js (everything before `class MissionManager`) in a sandboxed Node context with stubbed imports and writes `SolarSystem/Resources/Missions.json`.

App startup decodes the JSON through a `MissionJSON` DTO layer (in `MissionData.swift`) that converts to the domain `Mission` / `Vehicle` / `Waypoint` structs. The DTO layer isolates Swift's Codable from the ergonomic domain types — the domain types keep their custom initialisers and convenience computed properties, while the DTO tracks whatever shape the JSON happens to have.

### Missions in the bundle

| Mission | Frame | Vehicles | Duration | Notable features |
|---------|-------|----------|----------|------------------|
| Artemis II | Geocentric | SLS + SRBs + Orion | 210 h | Crewed lunar flyby (Apr 2026) |
| Apollo 8 | Geocentric | CSM | 147 h | First crewed lunar orbit |
| Apollo 11 | Geocentric | Saturn V + Columbia + Eagle | 195 h | moonOrbit, moonLanding, moonOrbitReturn |
| Apollo 13 | Geocentric | Saturn V + Odyssey/Aquarius | 143 h | Free-return trajectory |
| Cassini-Huygens | Heliocentric | Cassini | 59,064 h (~6.7 y) | VVEJGA gravity assists, 6 anchorBody waypoints |
| Voyager 1 | Heliocentric | Voyager 1 | 28,200 h (~3.2 y) | Jupiter + Saturn flybys |
| Voyager 2 | Heliocentric | Voyager 2 | ~105k h | Grand tour (4 planets) |
| Perseverance | Heliocentric | Perseverance | 4,920 h | `autoTrajectory: "transfer"` Hohmann arc |
| New Horizons | Heliocentric | New Horizons | ~78k h | Pluto flyby |
| Parker Solar Probe | Heliocentric | Parker | ~43,800 h | Multi-loop Venus-assist solar approach |
| BepiColombo | Heliocentric | BepiColombo | ~52k h | Mercury orbiter |

### Architecture

```
Missions.json (bundled resource, exported from web JS)
    -> MissionData.all (JSON → DTO → domain)
    -> MissionManager.initialize(in: scene)
        -> per mission: anchor waypoints resolve, Moon-aligned → ecliptic rotation
            -> centripetal CatmullRom sampling (400 pts for primary, ≥40 * N for others)
                -> trajectory line (SCNGeometryElement .line, per-vertex colour gradient)
                -> vehicle marker (nested emissive SCNSphere + additive halo)
            -> ready
    -> MissionManager.update(simulatedDate, earthHelioPos, cameraNode) each frame
        -> group.position = earthScenePos (geocentric) or zero (heliocentric)
        -> per vehicle: interpolate CatmullRom OR moonOrbit cos/sin OR moonLanding snap
        -> scale marker by camera distance (max(0.04, camDist * 0.012))
```

### Mission data shape (Swift structs)

| Type | Fields | Notes |
|------|--------|-------|
| `Mission` | id, name, subtitle, launchDate, durationHours, flybyTimeHours, referenceFrame, events, vehicles | `autoTimeScale()` snaps `durationHours * 80` to nearest preset in {100, 1k, 10k, 100k, 1M, 10M} |
| `Vehicle` | id, name, color, primary, waypoints, moonOrbit?, moonLanding?, moonOrbitReturn? | `primary` → camera tracks and telemetry reads from this vehicle |
| `Waypoint` | t (hours), x, y, z, anchorMoon, anchorBody? | km+Moon-aligned (geocentric) or AU ecliptic (heliocentric) |
| `MissionEvent` | t, name, detail, showLabel | `showLabel: false` for Earth-surface events (Launch, MECO, splashdown) |
| `MoonOrbitPhase` | startTime, endTime, periodHours, radiusKm | Runtime circular orbit around the Moon's scene position |
| `MoonLandingPhase` | startTime, endTime | Marker snaps to Moon scene position throughout window |

### Coordinate handling

- **Geocentric waypoints** (Apollo, Artemis) are km in a Moon-aligned frame (X toward Moon at `flybyTimeHours`). At init, rotated by `atan2(moonPos.y, moonPos.x)` to ecliptic. `anchorMoon: true` replaces a waypoint with the Moon's actual ecliptic direction × semi-major-axis distance (so the line meets the rendered Moon).
- **Heliocentric waypoints** (Voyager, Cassini, etc.) are AU in ecliptic coordinates. `anchorBody: "planet_id"` replaces the waypoint with that planet's `OrbitalMechanics.heliocentricPosition(...)` at time `t`.
- **`autoTrajectory: "transfer"`** (Perseverance) expands 2–3 anchor waypoints into an elliptical arc via `MissionManager.generateTransferArc(_:)`. Prograde (CCW) sweep between anchor angles, linear radius interpolation with a sin(π·frac) outward bulge, 12 intermediate samples per segment. Runs after anchor resolution so the arc connects real planet positions.
- Geocentric scene conversion: `earthSceneR * pow(distKm / 6371, moonDistExponent) * moonDistScale` — same compression as moon positioning.
- Heliocentric scene conversion: `SceneBuilder.sceneDistance(au:)` — same log formula as planet positioning.

### Runtime phases (geocentric only)

Each frame, for a vehicle with any moon-phase property, the marker position is computed from the Moon's *current* scene position rather than by interpolating waypoints. This keeps the vehicle glued to the rendered Moon mesh:

1. **moonOrbit**: `phase = (t - start) / period * 2π`, position = moonScenePos + tangent·cos·r + normal·sin·r where tangent/normal are perpendicular to the Earth-Moon line. Orbit radius is the scene distance of `(sma + radiusKm)` minus the scene distance of `sma` — shrinks proportionally with the pow(0.6) compression.
2. **moonLanding**: marker snaps to moonScenePos for the entire window.
3. **moonOrbitReturn**: same as moonOrbit but in a distinct time window (post-landing ascent).

### Scene graph

```
SCNScene
├── [planets, moons, stars, orbits, sun]            (unchanged)
└── mission_<id> (SCNNode group, positioned at Earth or origin)
    ├── trajectory_line                              # SCNGeometryElement .line + per-vertex colours
    └── vehicle_marker                               # emissive SCNSphere + additive halo child
```

### Telemetry

`missionManager.telemetry(missionId:, simulatedDate:)` returns MET (hours), distance (km), distance (AU, heliocentric only), and speed (km/s). Speed is computed via finite difference: position(elapsed) vs position(elapsed + 0.01h) for geocentric, (elapsed + 1.0h) for heliocentric (longer step smooths AU-scale quantisation).

### Event detection

`checkEventTrigger(simulatedDate:)` returns the next unfired event whose timestamp was just crossed. Each event fires once via a `lastTriggeredEvent[missionId]` cursor; a rewind past the cursor-pointed event resets it so replays work. The rewind-reset check runs unconditionally — even when simulation time is outside the mission's active window — so jumping far before launch still clears the cursor.

### UI overlays

| Component | Location | Purpose |
|-----------|----------|---------|
| `MissionsMenu` | Toolbar (procedural `RocketIcon`) | Dropdown: all 11 missions + `Stop replay (1x)` |
| `MissionTimelineSlider` | Above zoom slider, only when a mission is active | Shows T+0 → duration; drag pauses + seeks, auto-syncs on playback |
| `MissionTelemetryPanel` | Above timeline slider, left-aligned | MET / distance (km or AU) / speed for the primary vehicle |
| `MissionEventBannerView` | Top-centre overlay (below the date bar) | 4-second slide-down banner triggered by `checkEventTrigger`. Placed top-centre so it doesn't occlude the vehicle marker, Moon, or trajectory arc as events fire. |
| Event labels (3D) | SwiftUI overlay, projected from trajectory | Visible within ±3% of mission duration around each event (clamped 1–500h) |
| Satellites menu | Toolbar (`antenna.radiowaves.left.and.right` icon) | ISS on/off toggle (`showISS`, persisted) |

View-model state powering them: `activeMissionId`, `missionTelemetry`, `missionElapsedHours`, `currentEventBanner`, `timelineScrubbing` (flipping this pauses playback and restores prior pause state on release), `lazyFollowActive` (per-frame target lerp toward Earth + trajectory centre). End-of-mission speed-reset fires once when elapsed crosses `durationHours` with `timeScale > 1`, so the simulation doesn't race past splashdown.

**Toolbar icon philosophy**: SF Symbols first, procedural SwiftUI `Canvas` second, bundled assets never. The missions dropdown uses `RocketIcon` (a `Canvas` with three `Path`s for fuselage, fins, flame) because there's no SF rocket glyph — see `MissionUIViews.swift`. This keeps the "pure Apple frameworks, zero dependencies" rule intact and avoids asset-catalogue bookkeeping for what's effectively a 40-line vector drawing.

### Planet preset focus

Same maths as the mission camera, just triggered by the globe-menu planet picks or the `-focus <body>` launch arg. Computed in `SolarSystemViewModel.focusCamera(on:)`:

- **Distance**: `extent × baseMultiplier × (0.5 + 0.5 × min(aspect, 1))`, where `baseMultiplier` is `0.8` for moon-hosting bodies (Earth, Mars, Jupiter, Saturn) and `6.0` for moonless ones (Mercury, Venus, Uranus, Neptune, Pluto, Sun). The aspect-scaled portrait factor tightens the frame on phones where the constraining dimension (width) is much smaller than landscape.
- **Azimuth**: `atan2(-pos.x, -pos.z) + 0.55` radians — camera sits on the Sun-facing side of the target (~31° off the Sun direction) for a two-thirds-lit view. Elevation fixed at 0.3 rad (~17°).

Exactly matches the web app's `focusCamera` function (`../solarsystem-web/js/main.js:465`), so the two ports frame planet picks identically.

### Lazy-follow mission camera

Geocentric missions (Apollo, Artemis) auto-frame on selection:

1. `MissionManager.missionBounds(missionId:)` returns the trajectory's local AABB (Earth-relative) for geocentric missions, or `nil` for heliocentric ones — those bypass framing entirely and use `resetToOverview` instead.
2. `applyMissionCameraFraming(for:)` computes a Sun-side azimuth `atan2(-earthX, -earthZ) + 0.55 rad` — the negated arguments place the camera between the Sun (at the scene origin) and Earth so Earth's day side faces the camera, with the 0.55 rad offset putting the terminator on the far side for a two-thirds-lit view. Elevation is 0.3 rad (~17°), and distance = `radius / tan(30°) × 1.4` to fit the trajectory's local radius into a portrait viewport.
3. Per-frame `stepLazyFollowCamera()` lerps the camera target toward `earthScenePos + localCenter` at `0.02/frame` so the trajectory stays centred as Earth drifts through its orbit.
4. `Coordinator.userInteractionHandler` fires on pan/orbit/pinch `.began` and the view model clears `lazyFollowActive` — the user gets full manual control the moment they touch the screen.

Heliocentric missions (Voyager, Cassini, …) call `resetToOverview` instead — the standard solar system view shows the trajectory cleanly across the full system.

### 3D event labels

Event label positions are pre-computed once per mission via `MissionManager.eventLabelLocalPositions(missionId:)` — the primary vehicle's trajectory is interpolated at each event's timestamp. Each frame, `projectEventLabels(into:earthScenePosition:)` adds to the label list only when the elapsed time is within ±3% of the mission duration around the event (clamped 1–500h). The labels flow through the same deconfliction pass as planet/moon/star labels, so they respect screen crowding and occlusion rules.

### Tests

- `CatmullRomTests`: endpoint hits, interior uniform-u hits, two-point linearity, time-parameterised sampling, out-of-range clamping, degenerate-waypoint safety.
- `MissionTests`: geocentric rotation, heliocentric pass-through, anchorMoon → SMA distance, autoTimeScale preset snap, Apollo 11 data integrity, event fire-once + rewind reset, all-11-missions-load, heliocentric frame integrity for interplanetary missions, Perseverance `autoTrajectory` flag, transfer arc monotonic timeline.
- `MissionUITests`: MET formatting (<24h / ≥24h / zero), distance formatting (heliocentric AU / small km / thousands km), speed formatting (<100 / ≥100 km/s).
- `ScalingTests`: log distance monotonicity, moon compression formula, moon monotonicity in semi-major axis, sqrt radius clamps, moon floor.

## Custom Camera Controller

### State

- `cameraTarget: SCNVector3` — look-at point
- `cameraDistance: Float` — distance from target (clamped 0.15–250)
- `orbitAngleX: Float` — azimuth (radians)
- `orbitAngleY: Float` — elevation (clamped ±85°)

### Gestures

| Gesture | Action | Speed |
|---------|--------|-------|
| 1-finger pan | Translate target in camera-local right/up | `distance * 0.002` |
| 2-finger pan | Orbit (azimuth/elevation) | `0.005 rad/pt` |
| Pinch | Zoom (clamped 0.15–250) | Reciprocal of scale |
| Single tap | Hit-test → select body | — |
| Double-tap | Reset to overview | — |

### Zoom Slider

Horizontal custom drag-gesture control above the toolbar. Logarithmically mapped (0.5–250 scene units): `distance = exp(logMin + zoom * (logMax - logMin))`. Labels hidden during drag for performance. Syncs with pinch gestures via `syncZoomFromCamera()` every 3rd frame. All zoom controls (slider, pinch, presets, coordinator) clamp to the same 0.5–250 range to prevent discrepancies.

### setCamera(azimuth:elevation:) extension

`Coordinator.setCamera(target:distance:azimuth:elevation:)` accepts optional azimuth and elevation overrides so mission camera framing (Phase 6) can place the camera Sun-side of the Earth-Moon system without disturbing the user's current orbit angles. A `currentTarget` read-only accessor lets higher layers lerp toward a new target without fighting the coordinator's internal state.

## UI Controls

### Toolbar (bottom)

| Control | Icon | Action |
|---------|------|--------|
| Play/Pause | play/pause.fill | Toggle simulation |
| Speed menu | gauge | 0.1x to 1Mx, reverse, Reset to Now |
| Orbits | circle.circle | Toggle orbital paths |
| Labels menu | tag | Planets / Moons / Stars (independent toggles) |
| Planet picker | globe | Jump to any body or overview |
| Home | house.fill | Reset to overview |

### Persisted Settings (UserDefaults)

- `showOrbits` (default: true)
- `showPlanetLabels` (default: true)
- `showMoonLabels` (default: true)
- `showStarLabels` (default: true)

## Launch Arguments

| Argument | Values | Description |
|----------|--------|-------------|
| `-timeScale` | float | Speed multiplier (default 1.0). Overridden when `-mission` is specified. |
| `-date` | ISO8601 | Override current date |
| `-focus` | body name | Start focused on body (lowercase) |
| `-mission` | mission id | Select mission on launch (e.g. `apollo11`). Jumps simulation time to the mission's launch date and applies `autoTimeScale()`. |
| `-showISS` / `-hideISS` | flag | Toggle ISS visibility (overrides the persisted UserDefaults value) |
| `-showOrbits` / `-hideOrbits` | flag | Toggle orbits |
| `-showLabels` / `-hideLabels` | flag | Toggle all labels |
| `-logPositions` | flag | Log heliocentric positions |
| `-frameLog` | flag | Print frame-timing diagnostics: any tick > 20 ms or work > 5 ms, plus a once-per-second summary (fps, worst tick, worst work). Phases covered: `bodies`, `stars`, `decon`, `mm` (mission update), `mui` (mission UI). Used to track down the macOS `projectPoint` stutter — see the Performance Debugging section below. |
| `-innerOnly` | flag | Mercury–Mars only |

## Testing

### Unit tests

All 34 unit tests run identically on both platforms:

```bash
# iOS Simulator
xcodebuild -project SolarSystem.xcodeproj -scheme SolarSystem \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test \
  CODE_SIGNING_ALLOWED=NO

# macOS (faster — runs on host, no simulator boot)
xcodebuild -project SolarSystem.xcodeproj -scheme SolarSystem \
  -destination 'platform=macOS' test
```

Pure-math helpers (`SceneBuilder.sceneDistance`, `sceneRadius`, `moonSceneDistance`, `CatmullRom.sample*`, `MissionManager.resolveAndRotateWaypointsForTesting`, `Mission.autoTimeScale`) are marked `nonisolated` so Swift Testing suites don't need `@MainActor`. Only the event-trigger test hops to the main actor via `@MainActor @Test` because it instantiates `MissionManager`.

### Simulator

```bash
xcodebuild -project SolarSystem.xcodeproj -scheme SolarSystem \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build \
  CODE_SIGNING_ALLOWED=NO

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/SolarSystem-*/Build/Products/Debug-iphonesimulator/SolarSystem.app -maxdepth 0)
xcrun simctl install booted "$APP_PATH"
xcrun simctl launch booted com.pwilliams.SolarSystem -- -focus jupiter -timeScale 5000
xcrun simctl io booted screenshot /tmp/screenshot.png

# Apollo 11 mission replay (Phase 2):
xcrun simctl launch booted com.pwilliams.SolarSystem -- -mission apollo11 -focus earth
```

### Device

```bash
xcodebuild -project SolarSystem.xcodeproj -scheme SolarSystem \
  -destination "platform=iOS,name=Paul's iPhone 16 Pro" build

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/SolarSystem-*/Build/Products/Debug-iphoneos/SolarSystem.app -maxdepth 0)
xcrun devicectl device install app --device 970899A3-153F-5EC2-834F-BAFFCDF2560B "$APP_PATH"
xcrun devicectl device process launch --device 970899A3-153F-5EC2-834F-BAFFCDF2560B com.pwilliams.SolarSystem
```

### macOS (Debug from DerivedData)

```bash
xcodebuild -project SolarSystem.xcodeproj -scheme SolarSystem \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/SolarSystem-*/Build/Products/Debug/SolarSystem.app -maxdepth 0)

# Launch with any of the same args the iOS version accepts:
open -n "$APP_PATH" --args -mission apollo11 -focus earth
open -n "$APP_PATH" --args -mission cassini
open -n "$APP_PATH" --args -focus jupiter -timeScale 5000
open -n "$APP_PATH" --args -showISS
```

`open -n` launches a fresh instance each time (`-n` for "new"); drop it to reuse the running copy. The `--args` flag feeds everything after it into `ProcessInfo.processInfo.arguments`, picked up by `SolarSystemViewModel.parseLaunchArguments()` the same way the iOS simulator invokes it.

### macOS (Release install to /Applications)

`run-macos.sh` builds in Release, installs the bundle into `/Applications` (falling back to `~/Applications` if the system folder isn't writable), and launches a fresh instance. Extra arguments are passed through to the app:

```bash
./run-macos.sh                                 # launches with default settings
./run-macos.sh -mission apollo11 -focus earth  # mission replay
./run-macos.sh -focus jupiter -timeScale 5000  # planet focus, fast-forward
./run-macos.sh -frameLog                       # with per-frame timing in the console
```

Any running instance is killed first so the install doesn't race. The script uses `xcodebuild … -configuration Release` — which relies on the target's existing `DEVELOPMENT_TEAM = L7GB763YG3` setting for code signing, same as a normal Xcode "Run" on macOS.

## Build

```bash
xcodebuild -project SolarSystem.xcodeproj -scheme SolarSystem \
  -destination 'generic/platform=iOS' build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

## Performance Debugging

The `-frameLog` launch arg prints per-frame timing so regressions show up immediately. Recipe:

```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData/SolarSystem-*/Build/Products/Debug/SolarSystem.app -maxdepth 0 | head -1)
"$APP/Contents/MacOS/SolarSystem" -focus earth -showISS -timeScale 10000 -frameLog > /tmp/frame.log 2>&1 &
sleep 10
grep STUTTER /tmp/frame.log | head -20   # individual slow frames, with sub-phase breakdown
grep summary /tmp/frame.log | head -10   # once-per-second fps/worst-work roll-up
pkill -f Contents/MacOS/SolarSystem
```

Example healthy output: `fps~60 worst-dt=16.8ms worst-work=3.3ms` per second.

The sub-phase columns (`bodies`, `stars`, `decon`, `mm`, `mui`) correspond to the five big blocks inside `updatePositions`. If one column spikes while others stay flat, the stutter is localised to that phase — that's how the `projectPoint` blocking was tracked down in April 2026 (bodies ballooned to 230 ms, everything else stayed under 1 ms, pointing straight at the per-label projection calls in the body loop).

### Matrix-based label projection

`SCNView.projectPoint` on macOS blocks the main thread by synchronising with the render thread — about 16.7 ms (one 60 Hz frame) per call during heavy scene activity. We bypass it: `refreshProjectionCache()` builds the view × projection matrix once per frame as a `simd_float4x4`, and `projectToSwiftUIPoint(_:in:)` does the world-to-clip-to-screen maths with pure SIMD arithmetic (sub-millisecond for all 26 bodies combined). Output is already in SwiftUI top-left-origin coords so no per-platform Y flip is needed. Same code path runs on iOS, where it happens to also be ~100× faster than `projectPoint`.

The **projection matrix is constructed from first principles** (camera `fieldOfView` + live `view.bounds` aspect) rather than read from `camera.projectionTransform`. The latter returns a matrix whose `[0][0]` aspect term didn't match the current viewport on macOS, so labels drifted horizontally away from their bodies. Building the matrix ourselves also correctly handles `SCNCameraProjectionDirection.horizontal` (macOS default) vs `.vertical` (iOS default) — the two branches differ in which axis gets the `1/tan(fov/2)` term raw and which gets it multiplied by aspect.

```
horizontal FOV:   xScale = f,         yScale = f * aspect
vertical FOV:     xScale = f / aspect, yScale = f
where f = 1 / tan(fov/2)
```

Heads-up: `SCNCameraProjectionDirection` only has `.horizontal` and `.vertical` cases — there is **no `.automatic` case** despite the common assumption.

### Label placement (on-screen-radius offsets)

Labels are offset above each body by the body's actual on-screen radius plus a 4 pt margin — so at every zoom level the label sits just above the disc rather than overlapping it. The screen radius is computed from the same cached projection matrix:

```
cachedPixelsPerUnit = yScale * (viewportHeight / 2)   // cached per frame
screenR = worldRadius * cachedPixelsPerUnit / clip.w  // per-body
offsetY = max(8, screenR + 4)
```

`cachedPixelsPerUnit` is derived from the projection matrix itself, not an empirical constant. The 8 pt floor handles nodes without `SCNSphere` geometry (stars, the procedural ISS model) — they still get a readable gap even though their world radius is nominally zero. A previous version used an ad-hoc `r / w * 300` formula that undershot by 3–4× on widescreen Mac windows, which was why the labels always landed inside the planet disc.

The matrix maths and helpers live in `SolarSystemViewModel` near the `projectLabel` helper. If you need to project from elsewhere, call `refreshProjectionCache()` first.

## Frameworks Used

- **SwiftUI** — UI layer, gesture state, overlay labels, zoom slider
- **SceneKit** — 3D rendering, PBR materials, camera, lighting, hit testing
- **UIKit** — UIGraphicsImageRenderer for procedural textures, UIImage for bundled textures
- **Foundation** — Date/calendar, ISO8601DateFormatter, ProcessInfo, UserDefaults
- **simd** — SIMD3<Double> vectors, simd_length

## Known Gotchas

### Orbital Mechanics
- **Kepler divergence**: For e > 0.9, use `E0 = M + e*sin(M)` as initial guess
- **Angle wrapping**: Normalise to [0, 2pi) via `truncatingRemainder`
- **Julian date precision**: Use `Double` — `Float` lacks precision

### SceneKit
- **Camera controller conflict**: `allowsCameraControl` overrides programmatic changes. Must disable entirely and implement custom gestures.
- **SCNTube UV mapping**: Caps map linearly, not radially. Saturn rings need custom disc geometry.
- **SCNText scaling**: Can't maintain constant screen size. Use SwiftUI overlay with `projectPoint()`.

### Performance
- **SwiftUI label overhead**: 100+ labels re-rendered via `@Published` every frame kills performance. Throttle to every 3rd frame.
- **Zoom slider**: Hide labels during drag gesture to prevent frame drops.
- **Star occlusion**: O(stars × bodies) per frame — keep named star count reasonable (~120).

### Camera
- **Deferred coordinator**: `cameraCoordinator` is nil during `init()`. Use `pendingFocus` with `didSet`.
- **Focus-at-wrong-time**: `pendingFocus` must run `updatePositions(projectLabels: false)` *before* calling `focusOnBody`, otherwise focus maths read each node's default origin position (because nodes haven't been positioned for the current simulated date yet) and the camera ends up pointed at the Sun. Fixed by calling updatePositions inside the `cameraCoordinator.didSet`.
- **Vertical pan direction**: Screen Y is inverted relative to world up. Fixed by flipping `dy * up`.
- **Saturn ring spin**: Rings are child nodes — cancel spin quaternion in local frame each frame.
- **Euler angle wobble**: `eulerAngles = (tilt, spin, 0)` causes axial tilt to rotate with spin because SceneKit applies Y-X-Z order. Use quaternion composition instead: `tiltQuat * spinQuat`.
- **Zoom range consistency**: All zoom controls (slider, pinch, presets, `updateCamera`, `setDistance`) must clamp to the same range (0.5–250). Mismatched minimums cause the slider to snap when switching between manual zoom and presets.

### Missions
- **Main-actor isolation for pure math**: `SceneBuilder` is `@MainActor`, so static scaling helpers used by `MissionManager` + tests need explicit `nonisolated` annotation. Same for `MissionManager.resolveAndRotateWaypointsForTesting` and `Mission.autoTimeScale`.
- **Moon-relative semi-major axis**: `moonOrbit`/`moonLanding` must use `moonElements.semiMajorAxisKm` (matching how the Moon mesh is rendered), not `simd_length(moonPosition(...))` which fluctuates ±21,000 km due to eccentricity and makes vehicles miss the Moon.
- **anchorMoon scale factor**: Rescale the unit ecliptic direction by the semi-major axis in km, not by the raw `moonPosition()` magnitude — otherwise the waypoint lands at the Moon's actual eccentric distance instead of its rendered position.
- **Event rewind past launch**: The rewind-reset check in `checkEventTrigger` must run before the "outside active window" continue, otherwise jumping far before launch never clears the cursor and Launch can't replay.
- **CatmullRom knot clamp**: Minimum knot delta (1e-8) prevents division-by-zero when two adjacent waypoints coincide (can happen with `anchorMoon` waypoints at similar times).
- **Line primitive indexing**: `SCNGeometryElement(primitiveType: .line, ...)` takes *pairs* of indices, not a line-strip array. Build `[0,1, 1,2, 2,3, …]` for a connected polyline.
- **Auto-speed overrides -timeScale**: Setting `activeMissionId` calls `autoTimeScale()` and overwrites whatever the user supplied via `-timeScale`. Intentional — the mission auto-speed targets ~45s replay.
- **JSON export workflow**: `tools/export-missions.mjs` reads `../solarsystem-web/js/missions.js`, slices off everything from `class MissionManager` onward, stubs the imports, and evaluates the data declarations in a Node vm context. Re-run whenever upstream waypoints change; check `Missions.json` into git as the bundled source of truth.
- **DTO vs domain types**: `MissionJSON` in `MissionData.swift` exists only for Decodable conformance; the domain `Mission` / `Vehicle` / `Waypoint` types stay free of Codable boilerplate so they can keep ergonomic custom initialisers. Add new JSON fields to the DTO first, then map in `toDomain()`.
- **autoTrajectory runs after anchor resolution**: The transfer-arc generator expects waypoint x/y/z to already be resolved to real planet positions, not anchor sentinels. Order in `buildVehicle` is: resolve anchors → rotate (geocentric only) → transfer arc → CatmullRom sample.
- **Telemetry / banner throttle**: `updateMissionUIState()` runs every 3rd frame (same cadence as label projection) so the publisher doesn't fire at 60 Hz for identical values. If a test needs immediate state, call `seekMission(toElapsedHours:)` which runs a synchronous single-frame update.
- **Timeline scrub pauses playback**: `timelineScrubbing.didSet` flips `isPaused` (restoring the prior value on release) so the display link doesn't advance simulation time while the user drags. Without this, the slider thumb fights the view model's auto-sync.
- **Banner animation re-fires on identical names**: `MissionEventBanner.id` is a `UUID()` rather than the event name, so SwiftUI treats each firing as a distinct identity and re-runs the slide-in transition. Without this, a rewind + replay past the same event would show no animation.
- **End-of-mission auto-reset is one-shot**: `missionEndSpeedResetArmed` prevents the speed-reset from firing every frame once elapsed time has passed `durationHours`. Rearmed when the user rewinds back inside the mission window.
- **Swift expression complexity in tests**: Long chained arithmetic with mixed `Int`/`Double` literals (e.g. `2 * 24 + 14 + 32.0 / 60.0 + 8.0 / 3600.0`) can trip "unable to type-check in reasonable time". Split into named intermediate values with explicit `Double` types.

### ISS / Satellites
- **ISS as a moon, gated by a toggle**: Added to Earth's `moons` array so the existing moon-positioning, label projection, and rotation pipelines apply for free. Hidden by default via `showISS` UserDefaults. The label projection path explicitly skips ISS when `!showISS` — otherwise the "ISS" text would float next to Earth with no geometry beneath it.
- **Procedural geometry, not a sphere**: `SceneBuilder.createBodyNode(for:)` special-cases `body.id == "iss"` and returns the truss+panels+radiators group. The moon sphere isn't created at all, so nothing to hide beyond the group itself.

### Lazy-follow mission camera
- **Framing depends on up-to-date node positions**: `applyMissionCameraFraming(for:)` calls `updatePositions(projectLabels: false)` once before reading `earthNode.position`, same pattern as `pendingFocus` — without it, Earth is at (0,0,0) and the framing lands at the Sun.
- **Azimuth uses Earth's x/z, not x/y**: In SceneKit's coordinate system (scene y = ecliptic z), Earth's "horizontal" position is (x, z). Using (x, y) would pick a vertical offset instead and place the camera below the ecliptic plane.
- **User-break runs on `.began`, not `.changed`**: Firing on every gesture delta would spam the handler. Firing on `.began` once is enough — the view model clears `lazyFollowActive` and stops stepping the lerp for the rest of the session.
- **Heliocentric missions bypass framing**: Interplanetary trajectories span AU; framing them tight around a local centre breaks because the trajectory overlaps the Sun. The code falls through to `resetToOverview` for heliocentric missions.
- **`pendingMissionFraming`**: When `-mission` is set at init and the camera coordinator hasn't connected yet, the framing request is parked and applied in `cameraCoordinator.didSet`. Analogous to `pendingFocus`.
- **Sun-side azimuth sign flip**: The camera's spherical offset is measured *from* the target, so the direction pointing at the Sun (at scene origin) is `-earthPos / |earthPos|`. Using `atan2(-x, -z)` (both negated) puts the camera on the Sun side; using `atan2(x, z)` places it on the anti-Sun side and the target renders unlit. Applies to both `focusCamera(on:)` and `applyMissionCameraFraming(for:)`.
- **Trajectory lines bypass depth**: Mission trajectory lines set both `writesToDepthBuffer = false` and `readsFromDepthBuffer = false`, so the full arc is visible even behind the Moon/planets. Without `readsFromDepthBuffer = false` the behind-Moon half of an Artemis / Apollo flyby disappears into the Moon mesh and the trajectory appears to terminate at the lunar horizon.
- **`SCNView.projectPoint` blocks the render thread on macOS**: At high time-scales with rapidly-changing scene content (e.g. 10,000× + ISS), each call waits ~16.7 ms (one 60 Hz frame) for a render-thread sync. With 26 bodies projected per UI-update frame that's a 230–280 ms stutter every ~1 s. Fixed by caching the view × projection matrix once per frame (`refreshProjectionCache()`) and computing screen coordinates manually via SIMD — sub-millisecond total per frame, no sync. Run with `-frameLog` to print per-frame phase timings if similar issues recur.
- **`camera.projectionTransform` has the wrong aspect on macOS**: The property returns a matrix whose `[0][0]` term doesn't track the live viewport size, causing labels to drift horizontally from their bodies (vertical tracking stays fine because `[1][1]` doesn't depend on aspect). Fixed by constructing the projection matrix ourselves from `camera.fieldOfView` + `view.bounds` aspect each frame. Don't read `projectionTransform` directly in render-critical code paths.
- **`SCNCameraProjectionDirection` has no `.automatic` case**: Only `.horizontal` and `.vertical`. macOS defaults to `.horizontal`, iOS to `.vertical`. When constructing your own projection matrix the two require different `xScale`/`yScale` formulas (see the *Matrix-based label projection* section) — applying the wrong one stretches one axis.
- **Label screen-radius needs the real projection factor**: A rough `r / clip.w * 300` formula undershoots on widescreen Mac windows by 3–4×, so labels offset by that amount still land inside the planet disc. The correct factor is `yScale × (viewportHeight / 2)`, where `yScale` comes from the same projection matrix you're rendering with. Cached once per frame as `cachedPixelsPerUnit`.

### 3D event labels
- **Label positions are computed once, positioned per frame**: `eventLabelLocalPositions` returns trajectory-local positions cached at mission selection. Each frame the current Earth scene position is added on top so the label moves with Earth's heliocentric drift. Re-projecting every frame would cost far more than it gains.
- **Window clamp**: A ±3% window on a 195-hour Apollo 11 mission gives ~6h of screen time (at 10,000× replay ≈ 2 real seconds). The 500-hour upper clamp prevents Voyager-length missions from producing weeks-long visibility windows where every label shows throughout the replay.

## Future Roadmap

All six planned port phases are shipped. Future work picks up from the existing backlog:

- Asteroid belt visualisation
- Constellation lines connecting named stars
- Planet info cards with physical data
- AR mode (place solar system on a table)
- Time scrubber UI
- Eclipse prediction
- Unit tests against JPL Horizons
