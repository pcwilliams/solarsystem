# Apple Dev - Claude Code Project Conventions

This folder contains native iOS apps built entirely through conversation with Claude Code. This file captures the shared principles, patterns, and preferences that apply across all projects.

## Tech Stack

Every project uses the same foundation:

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
├── CLAUDE.md                    # Developer reference (this kind of file)
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

Smaller projects (e.g. Where) may flatten this into fewer files — the principle is simplicity over ceremony.

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

### Philosophy: Maximise Simulator Coverage Before Device

Device testing is expensive — each iteration requires a build, deploy, and manual interaction. The goal is to catch as many issues as possible in the simulator so that by the time the app runs on a real device, confidence is already high. This means:

1. **Every testable mode and feature should be exercisable from the command line** via launch arguments
2. **Bundled test files** (WAV, JSON, images) should exercise features that normally require live input (microphone, camera, network)
3. **Diagnostic logging** should capture algorithmic decisions so issues can be diagnosed from log output, not just visual inspection
4. **Screenshots are useful but logs are better** — a screenshot shows what happened, a log shows why

### Simulator Testing with Launch Arguments

For apps with multiple modes or views, add **launch argument parsing** so visual testing can be fully automated from the command line — never try to tap simulator UI with AppleScript (it's unreliable). Parse `ProcessInfo.processInfo.arguments` in the root view to accept flags like `-mode <value>`.

**Launch arguments must override persisted settings.** When an app uses `@AppStorage` or `UserDefaults` to remember UI state across launches, the persisted values load automatically. Launch arguments for testing must be applied *after* persistence loads (e.g. in `onAppear`) so they take priority. Without this, a test launch with `-mode bars` might be ignored because `@AppStorage` still holds `spectrogram` from the last manual session. Return optionals from launch-arg parsers (nil = no override) so they only replace the persisted value when explicitly provided.

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

This pattern was established in ShiftingSands (which supports `-mode`, `-count`, `-test`, `-autostart`, etc.) and adopted in Spectrum (`-mode bars|curve|circular|spectrogram`). Every new project with multiple visual states should support this from the start.

### Bundled Test Files for Hardware-Dependent Features

When a feature depends on hardware input (microphone, GPS, camera), create **bundled test files** that exercise the same code path in the simulator:

- **Audio**: Generate WAV files with Python that produce known inputs — pure tones (440Hz sine), multi-tone sequences (pitch changes every 1.5s), periodic beats (120 BPM kick drum). Bundle them in the app and play via `-testfile <name>` launch argument.
- **Location**: Bundle JSON files with known GPS coordinates for map-based testing.
- **Images**: Bundle sample photos with known EXIF data for photo-processing features.

The key principle: **the DSP / processing pipeline shouldn't know or care whether input comes from hardware or a test file**. If the pipeline works correctly with a known test input in the simulator, it will work with real input on device (barring hardware-specific issues like sample rate differences).

Example of generating a test audio file:

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

For complex algorithms (DSP, ML, signal processing), add **structured diagnostic logging** that captures the algorithm's internal decisions — not just the final output. Gate verbose logging behind a launch argument so it's off in normal use but available when debugging.

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

This pattern proved essential in Spectrum's pitch detection: the algorithm was tuned iteratively by deploying to device, singing test tones, and sending the log output back for analysis. Without the per-frame diagnostic output, it would have been impossible to distinguish between "the autocorrelation found the wrong peak" and "the confidence threshold rejected a valid peak".

**What to log:**
- Algorithm confidence/quality metrics (e.g. autocorrelation peak strength, SNR)
- Which branch/threshold was taken
- Input characteristics (signal level, frequency content)
- State changes (note changed, beat detected, silence entered)

**What NOT to log every frame** (too noisy):
- Raw sample values
- Full array contents
- Unchanged state

Use change-only logging for display state (only log when the displayed value changes) and periodic logging for diagnostics (every Nth frame).

### Reading Logs from Simulator and Device

```bash
# Simulator: read the app's Documents directory
CONTAINER=$(xcrun simctl get_app_container booted com.bundle.id data)
cat "$CONTAINER/Documents/app.log"

# Clear log before a test run
> "$CONTAINER/Documents/app.log"

# Device: build, install, launch, and retrieve logs automatically via CLI.
# The device is "Paul's iPhone 16 Pro" (970899A3-153F-5EC2-834F-BAFFCDF2560B).
# When connected, the full build-deploy-test cycle can run without Xcode GUI:

# Build for device (code signing required — no CODE_SIGNING_ALLOWED=NO)
xcodebuild -project ProjectName.xcodeproj -scheme ProjectName \
  -destination "platform=iOS,name=Paul's iPhone 16 Pro" build

# Install and launch with launch arguments
xcrun devicectl device install app --device 970899A3-153F-5EC2-834F-BAFFCDF2560B \
  path/to/ProjectName.app
xcrun devicectl device process launch --device 970899A3-153F-5EC2-834F-BAFFCDF2560B \
  com.pwilliams.ProjectName -- -mode bars -bpmlog

# Copy log file from device container
xcrun devicectl device copy from --device 970899A3-153F-5EC2-834F-BAFFCDF2560B \
  --source Documents/app.log --domain-type appDataContainer \
  --domain-identifier com.pwilliams.ProjectName --destination /tmp/app.log
```

### Performance Testing in the DSP/Rendering Pipeline

For real-time processing (audio, video, rendering), measure execution time to verify the pipeline completes within its time budget:

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

The budget is the time between callbacks (e.g. 2048 samples at 44.1kHz = 46.4ms). If average processing exceeds ~50% of the budget, optimise before adding features. If max processing occasionally exceeds the budget, investigate the spike.

### Simulator vs Device Differences

The simulator does NOT replicate everything. Always test on device for:

- **Microphone input** (simulator has no mic hardware)
- **GPS / CoreLocation** (simulator uses simulated locations)
- **Audio session behaviour** (`.playAndRecord` fails on simulator — use `.playback` with `#if targetEnvironment(simulator)`)
- **Sample rates** (simulator often uses 44.1kHz, device may use 48kHz — parameterise, don't hardcode)
- **Real-world signal characteristics** (voice has harmonics, vibrato, breath noise that pure test tones lack — algorithms that work on sine waves may fail on voice)
- **Hardware format edge cases** (0 Hz sample rate, 0 input channels — detect and alert the user)

The ideal workflow: build and iterate in the simulator until unit tests pass and test files produce correct output, then deploy to device for final validation with real-world input.

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

Each project includes four living documents that must be kept up to date as the project evolves:

### CLAUDE.md (developer reference)

The comprehensive knowledge base for Claude Code sessions. Must be updated whenever:
- A new file, model, view, or service is added or removed
- An architectural decision is made or changed
- A new API is integrated or an existing one changes
- A non-obvious bug is fixed or a gotcha is discovered
- Build configuration, test coverage, or project structure changes

This is the single source of truth for project context. A future session should be able to read CLAUDE.md and understand the entire project without exploring the codebase.

### README.md (user-facing)

The public-facing project overview. Must be updated whenever:
- Features are added, changed, or removed
- Setup instructions change (new dependencies, API keys, permissions)
- The project structure changes significantly
- Screenshots become outdated (note when a new screenshot is needed)

Keep it concise and practical — someone should be able to clone the repo and get running by following the README.

### architecture.html (architecture diagrams)

Interactive Mermaid.js diagrams rendered in a standalone HTML file. Must be updated whenever:
- The view hierarchy changes (new views, removed views, restructured navigation)
- Data flow changes (new services, new API integrations, changed data pipelines)
- New major subsystems are added (e.g. a notification system, a caching layer, a P&L calculator)

Use `graph TD` (top-down) for readability on narrow screens. Load Mermaid.js from CDN. Apply the shared dark theme with CSS custom properties and project-appropriate accent colours.

### tutorial.html (build narrative)

A step-by-step record of how the app was built through Claude Code conversation. Must be updated whenever:
- A significant new feature is added via a notable prompt interaction
- A major refactor or architectural change is made
- An interesting problem is solved through iterative prompting

Capture the essence of the prompt, the approach taken, and the outcome. This documents the collaborative development process and serves as a guide for building similar features in future projects.

**Prompt tone:** Prompts recorded in the tutorial should sound collaborative, not demanding. Use phrases like "Could we try...", "How about...", "Would you mind...", "Would it be worth...", "I'd love it if..." rather than "Make...", "Add...", "I want...", "I need...". When describing problems, use "I'm seeing..." or "I'm noticing..." rather than assertive declarations. The tone should reflect a partnership — two people working together on something, not instructions being issued.

### Formatting conventions

- Use plain Markdown in `.md` files (no inline HTML except README badges). Images must use `![alt](src)` syntax, not `<img>` tags
- HTML docs use a shared dark theme with CSS custom properties and Mermaid.js loaded from CDN
- HTML docs include a hero screenshot in a phone-frame wrapper (black background, rounded corners, drop shadow) below the title/badges

## Common Gotchas

- **Keychain: always delete before add** to avoid `errSecDuplicateItem`
- **SwiftUI `.refreshable` cancels structured concurrency** — wrap network calls in an unstructured `Task`
- **Wikimedia geosearch caps at 10,000m radius** — clamp before sending
- **Wikipedia disambiguation pages** — filter out articles where extract contains "may refer to"

---

# SolarSystem - Claude Code Developer Reference

## Overview

A GPU-accelerated solar system simulation for iPhone, using real Keplerian orbital mechanics (JPL J2000.0 elements) to calculate planet, moon, and Sun positions based on the current date and time. SceneKit renders the 3D scene with NASA/public-domain texture maps on all planets and major moons. 8,920 real stars from the Hipparcos catalogue form the backdrop, with correct positions, magnitudes, and colours. All bodies rotate at their real IAU sidereal rates with correct axial tilts. Custom gesture handling provides one-finger pan, two-finger orbit, and pinch-to-zoom navigation.

Physics runs on CPU (lightweight trig per body per frame). Rendering runs on GPU via SceneKit with PBR materials, multi-layer Sun corona, and Saturn's rings with Cassini colour/transparency maps.

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
- **SwiftUI overlay labels**: 3D `SCNText` labels can't maintain constant screen size. Labels are projected from 3D positions to screen coordinates via `SCNView.projectPoint()`, rendered as SwiftUI `Text` views. Pixel-perfect, tappable, constant size at all zoom levels. Star labels are occluded behind planet discs.
- **Logarithmic distance scaling**: Real distances span 4 orders of magnitude. `log(1 + AU/0.5) * 15` preserves ordering while keeping everything visible.
- **Sqrt radius scaling**: `sqrt(km) * 0.00125` for planet radii. Jupiter 3.3x Earth (real 11.2x) while keeping small planets visible. Moons use real ratio to parent with 0.012 minimum floor.
- **Moon distance compression**: `pow(realRatio, 0.4) * 1.5` preserves relative ordering.
- **Momentary planet shortcuts**: Selecting a planet flies camera there then releases control — no per-frame tracking that locks out manual navigation.
- **Deferred launch-arg focus**: Coordinator isn't available during `init()`. A `pendingFocus` string is applied once the coordinator connects via `didSet`.
- **Throttled label updates**: Labels only re-project every 3rd frame to reduce SwiftUI overhead. Labels hide entirely during zoom slider drag.
- **Real star catalogue**: 8,920 stars from HYG (Hipparcos/Yale/Gliese) database, filtered to naked-eye visibility (mag <= 6.5). ~120 brightest named stars labelled.
- **IAU rotation model**: Every body has sidereal rotation period, axial obliquity, and prime meridian at J2000.0. Tidally locked moons match their orbital period. Saturn's rings counter-rotate to cancel parent spin.
- **Persisted settings**: Label toggles (planet/moon/star) and orbit visibility saved to UserDefaults.

## Project Structure

```
SolarSystem/
├── SolarSystem.xcodeproj/
├── CLAUDE.md
├── README.md
├── architecture.html
├── tutorial.html
└── SolarSystem/
    ├── App/
    │   ├── SolarSystemApp.swift          # @main entry point (16 lines)
    │   └── ContentView.swift             # Root view, controls bar, zoom slider, labels overlay (263 lines)
    ├── Models/
    │   ├── CelestialBody.swift           # BodyType, PhysicalProperties, RotationProperties, CelestialBody (98 lines)
    │   ├── OrbitalElements.swift         # Keplerian element structs, angle helpers (94 lines)
    │   └── SolarSystemData.swift         # JPL elements: 9 planets + 16 moons + Sun (438 lines)
    ├── Views/
    │   ├── SolarSystemSceneView.swift    # UIViewRepresentable + custom camera Coordinator (252 lines)
    │   ├── InfoPanelView.swift           # HUD: date, time scale badge, body info card (130 lines)
    │   └── Components/
    ├── Services/
    │   ├── OrbitalMechanics.swift        # Julian dates, Kepler solver, positions (184 lines)
    │   ├── SceneBuilder.swift            # Scene graph, materials, rings, glow, starfield, B-V colours (599 lines)
    │   └── TextureGenerator.swift        # Procedural Sun texture, glow textures (114 lines)
    ├── ViewModels/
    │   └── SolarSystemViewModel.swift    # State management, display link, label projection, zoom (570 lines)
    ├── Extensions/
    │   └── SCNVector3+Math.swift         # SCNNode worldRight/worldUp for camera panning (24 lines)
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
    └── Assets.xcassets/
        ├── AppIcon.appiconset/          # Programmatic dark-mode solar system icon
        └── AccentColor.colorset/         # Orange (#FFAA33)
```

**Total: 12 Swift files, 2,782 lines of code. 17 texture/data files.**

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
| `-timeScale` | float | Speed multiplier (default 1.0) |
| `-date` | ISO8601 | Override current date |
| `-focus` | body name | Start focused on body (lowercase) |
| `-showOrbits` / `-hideOrbits` | flag | Toggle orbits |
| `-showLabels` / `-hideLabels` | flag | Toggle all labels |
| `-logPositions` | flag | Log heliocentric positions |
| `-innerOnly` | flag | Mercury–Mars only |

## Testing

### Simulator

```bash
xcodebuild -project SolarSystem.xcodeproj -scheme SolarSystem \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build \
  CODE_SIGNING_ALLOWED=NO

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/SolarSystem-*/Build/Products/Debug-iphonesimulator/SolarSystem.app -maxdepth 0)
xcrun simctl install booted "$APP_PATH"
xcrun simctl launch booted com.pwilliams.SolarSystem -- -focus jupiter -timeScale 5000
xcrun simctl io booted screenshot /tmp/screenshot.png
```

### Device

```bash
xcodebuild -project SolarSystem.xcodeproj -scheme SolarSystem \
  -destination "platform=iOS,name=Paul's iPhone 16 Pro" build

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/SolarSystem-*/Build/Products/Debug-iphoneos/SolarSystem.app -maxdepth 0)
xcrun devicectl device install app --device 970899A3-153F-5EC2-834F-BAFFCDF2560B "$APP_PATH"
xcrun devicectl device process launch --device 970899A3-153F-5EC2-834F-BAFFCDF2560B com.pwilliams.SolarSystem
```

## Build

```bash
xcodebuild -project SolarSystem.xcodeproj -scheme SolarSystem \
  -destination 'generic/platform=iOS' build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

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
- **Vertical pan direction**: Screen Y is inverted relative to world up. Fixed by flipping `dy * up`.
- **Saturn ring spin**: Rings are child nodes — cancel spin quaternion in local frame each frame.
- **Euler angle wobble**: `eulerAngles = (tilt, spin, 0)` causes axial tilt to rotate with spin because SceneKit applies Y-X-Z order. Use quaternion composition instead: `tiltQuat * spinQuat`.
- **Zoom range consistency**: All zoom controls (slider, pinch, presets, `updateCamera`, `setDistance`) must clamp to the same range (0.5–250). Mismatched minimums cause the slider to snap when switching between manual zoom and presets.

## Future Roadmap

- Asteroid belt visualisation
- Constellation lines connecting named stars
- Planet info cards with physical data
- AR mode (place solar system on a table)
- Time scrubber UI
- Eclipse prediction
- Unit tests against JPL Horizons
