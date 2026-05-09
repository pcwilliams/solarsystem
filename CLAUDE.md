
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

### GPU rendering — 3D surfaces, terrain, waterfalls, landscapes

For any feature that renders a 2D value field as a lit, animated 3D surface (frequency × time, day × hour, X × Y × any-Z, ridgelines, terrain), use the **`3dsurface`** skill. It captures the canonical Metal pipeline, mesh, camera math, lighting, smoothing, and animation patterns extracted from HeartMap and Spectrum — including the non-obvious decisions (fixed colour scales, smoothing-decoupled-from-colour, face normals, locked camera) that make a surface read as *stunning* rather than just correct.

### Apple Health / HealthKit

For any feature that reads heart rate, steps, workouts, sleep, or other Apple Health data, use the **`healthkit`** skill. It captures the actor-based service shape, authorization (single combined prompt; read perms aren't queryable), the optimized fetch patterns (per-month queries, server-side bucketing via `HKStatisticsCollectionQuery + .cumulativeSum`, parallel `async let`), the three-phase load (disk-cache seed → current-month refresh → background stream), the empty-result fallback to demo data, infinity-safe JSON disk caching, workout activity type → label/symbol mapping, and entitlements/provisioning gotchas (wildcard profiles can't carry HealthKit).

For *clinical interpretation* of that data — fitness scores, resting heart rate calculations, AHA active-minute zones, age-adjusted scoring, evidence-based step thresholds — use the **`health`** skill. It's platform-agnostic (useful in web dashboards too) and always carries an explicit "not medical advice" disclaimer.

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

## Multi-platform iOS+macOS apps

A single Xcode target can build for both `iphoneos`/`iphonesimulator` and `macosx`. ~99% of the code is platform-neutral; the differences are funneled through a small set of typealiases plus a handful of narrowly-scoped `#if` blocks. Pattern proven on a SceneKit solar-system app — see SolarSystem's `Extensions/Platform.swift`.

### Platform.swift typealiases

In `Extensions/Platform.swift`:

| Typealias | iOS | macOS |
|-----------|-----|-------|
| `PlatformColor` | `UIColor` | `NSColor` |
| `PlatformImage` | `UIImage` | `NSImage` |
| `PlatformView` | `UIView` | `NSView` |
| `PlatformViewRepresentable` | `UIViewRepresentable` | `NSViewRepresentable` |

Plus `makePlatformImage(cgImage:size:)` and `cgImage(from:)` helpers for `UIImage`↔`NSImage` bridging where construction differs.

**Rule**: outside `Platform.swift` (and a handful of files that genuinely need `#if`), never write `UIColor`/`UIImage`/UIKit-typed names directly. Use the `Platform…` aliases and most code stays one-line.

The places that *do* still need `#if canImport(UIKit)` in practice:
- Gesture recognisers (UIKit and AppKit APIs diverge meaningfully)
- The frame-tick loop (different display-link constructors)
- SwiftUI modifiers that exist on only one platform (`.statusBarHidden`, `navigationBarTitleDisplayMode`, `topBarTrailing`, etc.)

### Frame-tick loop

Use `CADisplayLink` on both platforms — just constructed differently:

- **iOS**: `CADisplayLink(target: self, selector: ...)` on the main run loop, display-synchronised 30–60 Hz.
- **macOS 14+**: `scnView.displayLink(target: self, selector: ...)` — the NSView-bound form. Binds to whichever display the window is on so ticks stay synced to that screen's VBlank.

**Don't try `Timer.scheduledTimer` on macOS as a substitute.** It produces visible ~1-per-second stutters because Timer's cadence drifts in and out of phase with the 60 Hz refresh. Only the real display link is reliable.

Because the macOS display link needs an SCNView/NSView to bind to, the start-animation request can arrive before the view is connected (SwiftUI's `onAppear` can fire before `makeNSView` completes). Park the request in a `pendingAnimationStart` flag and re-issue once the view's `didSet` runs.

### Gesture conventions (macOS vs iOS)

The AppKit Y axis is inverted relative to UIKit. macOS pan/orbit handlers must flip `dy` (e.g. `lastPoint.y - translation.y`) so "drag up = look up" stays consistent with iOS. All actual camera/transform maths stays shared between platforms — only the input plumbing differs.

Typical macOS gesture map for a 3D scene:

| Input | Action | Implementation |
|-------|--------|----------------|
| Left-mouse drag | Pan target | `NSPanGestureRecognizer` with `buttonMask = 0x1` |
| Right-mouse drag | Orbit | `NSPanGestureRecognizer` with `buttonMask = 0x2` |
| Trackpad pinch | Zoom | `NSMagnificationGestureRecognizer` |
| Scroll wheel / 2-finger scroll | Zoom | Subclass overriding `scrollWheel(with:)` |
| Single click | Select | `NSClickGestureRecognizer` (`numberOfClicks = 1`) |
| Double click | Reset | `NSClickGestureRecognizer` (`numberOfClicks = 2`) |

### SCNVector3 component types

`SCNVector3.x/y/z` is `Float` on iOS but `CGFloat` on macOS. Two helpers in `SCNVector3+Math.swift` (or equivalent) hide the gap:

- `SCNVector3(_ x: Double, _ y: Double, _ z: Double)` — build a vector from `Double` components.
- `SCNVector3.adding(_ dx: Double, _ dy: Double, _ dz: Double) -> SCNVector3` — offset by `Double` deltas, returning a new vector.

Use these wherever you previously wrote `SCNVector3(x, y, z)` with `Float` arithmetic — one-line call sites compile on both platforms.

### Launching with arguments (Debug from DerivedData)

Same `ProcessInfo.processInfo.arguments` parsing pattern as iOS, but the launcher is different:

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/<Project>-*/Build/Products/Debug/<Project>.app -maxdepth 0)
open -n "$APP_PATH" --args -mode someMode -timeScale 5000
```

`open -n` launches a fresh instance each time (`-n` for "new"); drop it to reuse the running copy. The `--args` flag feeds everything after it into `ProcessInfo.processInfo.arguments`. For Release-built apps installed to `/Applications`, just point `open -n` at the bundle there.

## Common Gotchas

- **Keychain: always delete before add** to avoid `errSecDuplicateItem`
- **SwiftUI `.refreshable` cancels structured concurrency** — wrap network calls in an unstructured `Task`
- **Sandbox entitlements:** macOS apps are sandboxed by default — ensure `com.apple.security.files.user-selected.read-write` or similar entitlements are set for file access
- **MusicKit / AppleScript:** `MusicKit` is the modern API for Apple Music access; `AppleScript` bridging via `NSAppleScript` is a fallback for operations MusicKit doesn't cover
- **`Timer.scheduledTimer` is not a frame clock** — it drifts in and out of phase with 60 Hz refresh, producing ~1 Hz stutters. Use `scnView.displayLink(target:selector:)` (macOS 14+) for any per-frame work bound to a SceneKit view; for non-SceneKit frame work, use `CVDisplayLink` directly.
- **AppKit Y axis is inverted vs UIKit** — flip `dy` in any pan / drag handler shared with iOS code, otherwise the "drag up = look up" convention reverses on macOS.

---


# Space Mechanics & Celestial Rendering

Conventions for any app that simulates planet / moon / spacecraft motion and renders it in 3D — distilled from a multi-platform SceneKit solar-system port.

## Constants (single source of truth)

Keep these as named constants on a single `OrbitalMechanics` (or equivalent) namespace; never inline the literals:

| Name | Value | Notes |
|------|-------|-------|
| J2000.0 | `2451545.0` | Reference Julian Date for all element epochs |
| Days/Julian century | `36525.0` | For `T = (JD - J2000) / 36525` |
| AU in km | `149_597_870.7` | IAU 2012 definition |
| Earth equatorial radius | `6378.137` km (or `6371` mean) | Used in geocentric scene scaling |

If the IAU revises any of these, you change one place.

## Orbital mechanics pipeline (Keplerian, CPU)

For tens of bodies the cost is microseconds per frame — no GPU compute benefit. Pipeline:

1. `julianDate(from: Date) -> Double` — Meeus algorithm, Gregorian → JD.
2. `julianCenturies(from: Date) -> Double` — `(JD - 2451545.0) / 36525.0`.
3. `elements.elements(at: T) -> CurrentElements` — base value + rate × T (per JPL).
4. `meanAnomaly = L - varpi`, normalised to `[0, 2π)` via `truncatingRemainder`.
5. `solveKepler(M, e) -> E` — Newton-Raphson with initial guess `E0 = M + e·sin(M)`, tolerance `1e-8`, max 50 iterations.
6. `trueAnomaly(E, e) -> ν = 2·atan2(sqrt(1+e)·sin(E/2), sqrt(1-e)·cos(E/2))`.
7. `r = a · (1 - e·cos(E))` — heliocentric distance.
8. Rotate by Ω, I, ω to ecliptic `(x, y, z)`.

**Numerical gotchas:**
- Use `Double` for Julian dates and elements. `Float` precision is insufficient.
- For high eccentricity (`e > 0.9`), the `M + e·sin(M)` initial guess still converges but bound iterations defensively.
- Always wrap angles via `truncatingRemainder(dividingBy: 2·π)` to keep `M` in `[0, 2π)`.

For moons, simplified circular orbits with period-based mean motion are usually accurate enough: `M = longitudeAtEpoch + (2π / period) · daysSinceJ2000`.

## IAU rotation model (every body)

Each body gets `RotationProperties(periodHours, obliquity, w0, tidallyLocked)`. Apply per frame with **quaternion composition**, not Euler angles:

```
finalRotation = tiltQuat(around X axis) * spinQuat(around Y axis)
```

**Why quaternions, not Euler:** SceneKit applies Euler angles in Y-X-Z order, so writing `eulerAngles = (tilt, spin, 0)` causes the tilt axis itself to rotate with the spin and you get a wobble per spin cycle. With quaternion composition, tilt is fixed in space and spin is around the tilted pole — physically correct.

Tidally locked moons just match their orbital period. A ring system (e.g. Saturn's) needs to **counter-rotate in local frame** to cancel the parent planet's spin so the ring stays in the equatorial plane.

## Coordinate system mapping

Common Apple-3D convention:

- **Orbital mechanics**: heliocentric ecliptic — x, y in the ecliptic plane, z perpendicular.
- **SceneKit / RealityKit**: y is up. Map `scene.x = ecliptic.x`, `scene.y = ecliptic.z`, `scene.z = -ecliptic.y`.

This means when you compute angles in the scene, "horizontal position" is `(x, z)`, not `(x, y)`. Using `(x, y)` for an azimuth like `atan2(x, y)` will silently place things below the ecliptic plane.

## Distance / radius scene scaling

Real distances span 4+ orders of magnitude. Pure realism makes the inner system invisible. Three formulas keep ordering correct while bringing everything into view:

```
sceneDistance(au)        = log(1 + au / 0.5) * 15            // planets, heliocentric
sceneRadius(km)          = sqrt(km) * 0.00125                // planet radii (floor 0.012)
moonSceneDistance(ratio) = pow(realRatio, 0.6) * 1.5         // moon distance from parent
```

- `0.5` is the "knee" — distances under that AU compress less aggressively. Tune for inner-system visibility.
- `sqrt` (rather than linear or log) gives Jupiter ~3.3× Earth (real is 11.2×) — readable without overwhelming.
- Moon compression: with exponent `0.6` and scale `1.5`, the Moon sits at ~17.6 Earth radii (real 60.3). Exponent `0.4` collapses it too far (~8.8). `0.6` is the sweet spot.

**Centralise these.** Any mission/trajectory rendering code must use the *same* formulas as the body-positioning code, otherwise vehicles drift away from the bodies they should hug. Mark static helpers `nonisolated` so they're callable from `@MainActor` and pure-math contexts alike.

Geocentric mission scaling matches moon scaling:
```
geocentricSceneR(km) = earthSceneR * pow(distKm / earthRadiusKm, 0.6) * 1.5
```

Use the parent's **semi-major axis** (not its instantaneous distance) when placing satellites/orbiters near a body — actual distance fluctuates with eccentricity (Moon: ±21,000 km) and makes vehicles miss the rendered mesh.

## Star catalogue rendering

Bundle the **Yale Bright Star Catalog, 5th Rev. (BSC5)** — Hoffleit & Warren (1991), prepared at NASA Goddard NSSDC/ADC, public domain. Available via VizieR catalogue [V/50](https://cdsarc.cds.unistra.fr/viz-bin/cat/V/50) as `catalog.gz` (197-byte fixed-width records, 9,110 stars). Filter to naked-eye visibility (`mag ≤ 6.5`) — that's roughly 8,400 stars. Map RA/Dec to a celestial sphere at large radius (`r = 500` scene units works well).

Avoid the **HYG database** unless the project tolerates CC-BY-SA. HYG v3+ is licensed CC-BY-SA 4.0 (was 2.5 in earlier versions) — the share-alike clause is incompatible with permissive (MIT/BSD) project licences. BSC5 is a clean PD substitute that preserves the same RA/Dec/Vmag/B-V columns; rebuild from the raw VizieR file with a small parser script.

Star *names* (Sirius, Vega, Aldebaran …) are traditional / IAU-standardised — factual references, not subject to copyright, so they can be embedded freely or cross-referenced from the IAU-CSN list regardless of catalogue licence.

Use **4 brightness tiers** with different point sizes (mag < 1.5 → 3–8 px; mag 5–6.5 → 0.8–2 px) and **per-vertex B-V colour** for spectral type (blue-white O/B → white A → yellow G → orange K → red M).

Label only the brightest ~120 named stars (Sirius, Vega, Betelgeuse, …). The label-occlusion check (hide a star label when a planet's screen disc covers it) is `O(stars × bodies)` per frame — keeping labels at ~120 stays cheap.

## Saturn-style rings: use custom disc geometry

`SCNTube` UV-maps caps **linearly**, not radially, so a ring-strip texture stretches and warps. Build a custom flat disc:

- 72 radial segments × 4 ring segments
- `u` maps 0 (inner radius) to 1 (outer radius) — radially across the texture
- Apply ring colour map + alpha transparency for density
- `lightingModel = .constant` so it stays visible without a normal map
- Counter-rotate each frame to cancel parent's spin (see IAU rotation note)

## Mission / trajectory rendering

Each mission is a `SCNNode` group child of the scene. Geocentric missions (Apollo, Artemis) reposition the group to Earth's scene location every frame; heliocentric missions (Voyager, Cassini) stay at the origin. **Trajectory line shape is pre-computed at init** — only the group position updates per frame.

### Centripetal Catmull-Rom (alpha = 0.5)

Smooth waypoint sequences with centripetal Catmull-Rom (alpha = 0.5, matching Three.js's `CatmullRomCurve3`). **Sample by uniform time, not arc length**, so the marker advances linearly with mission time.

Knot-clamp guard: minimum knot delta `1e-8` prevents division-by-zero when two adjacent waypoints coincide (anchored waypoints at similar timestamps can collide).

### Moon-aligned waypoint frames

Lunar-mission waypoints are usually authored with `+X toward the Moon at flyby time`, in km. At init:

1. Compute the Moon's ecliptic angle at the flyby instant.
2. Rotate all waypoints by that angle to ecliptic.
3. Now any launch date yields a physically aligned trajectory.

`anchorMoon: true` on a waypoint replaces it with the Moon's actual ecliptic direction × **semi-major-axis distance** (not instantaneous distance, which is eccentric — see scene-scaling note).

`anchorBody: "planet_id"` on a heliocentric waypoint replaces it with that planet's `heliocentricPosition(...)` at time `t`.

### Runtime lunar orbit / landing phases

Don't try to express tight close-up motion as waypoints. Add explicit phase descriptors:

| Phase | Behaviour |
|-------|-----------|
| `moonOrbit(start, end, period, radiusKm)` | Each frame: `phase = (t - start) / period · 2π`, position = `moonScenePos + tangent·cos·r + normal·sin·r` where tangent/normal are perpendicular to the Earth-Moon line |
| `moonLanding(start, end)` | Marker snaps to `moonScenePos` for the entire window |
| `moonOrbitReturn` | Same as `moonOrbit` for post-landing ascent |

Orbit radius in scene units: `sceneDistance(sma + radiusKm) - sceneDistance(sma)` so the close-orbit shrinks proportionally with the same `pow(0.6)` compression as the body itself.

### `autoTrajectory: "transfer"` (Hohmann arcs)

For interplanetary transfers (e.g. Earth→Mars), expand 2–3 anchor waypoints into an elliptical arc:
- Prograde (CCW) sweep between anchor angles
- Linear radius interpolation with a `sin(π · frac)` outward bulge
- 12 intermediate samples per segment

**Order matters**: resolve `anchorBody` waypoints to real planet positions *first*, then expand the transfer arc, then CatmullRom-sample. The transfer-arc generator expects already-resolved x/y/z, not anchor sentinels.

### Line geometry

`SCNGeometryElement(primitiveType: .line, ...)` takes **pairs** of indices, not a strip. Build `[0,1, 1,2, 2,3, …]` for a connected polyline.

**Trajectory lines should bypass the depth buffer:** set both `writesToDepthBuffer = false` and `readsFromDepthBuffer = false`. Without `readsFromDepthBuffer = false`, the half of an Apollo flyby behind the Moon disappears into the lunar mesh and the trajectory appears to terminate at the lunar horizon.

### Event detection

Each mission has a list of `MissionEvent(t, name, detail, showLabel)`. `checkEventTrigger(simulatedDate)` returns the next unfired event whose timestamp was just crossed. Each event fires once via a `lastTriggeredEvent[missionId]` cursor; a rewind past the cursor-pointed event resets it so replays work.

**The rewind-reset check must run unconditionally** — even when simulation time is outside the mission's active window — so jumping far before launch still clears the cursor.

## Camera framing math

### Sun-side framing (planet picks, mission selection)

Place the camera between the Sun (at scene origin) and the target so the day side faces the camera, then offset slightly so the terminator falls on the far side for a two-thirds-lit view:

```swift
azimuth   = atan2(-targetPos.x, -targetPos.z) + 0.55  // ~31° off Sun direction
elevation = 0.3                                       // ~17°
```

**Sign matters.** The camera's spherical offset is *from* the target, so the direction toward the Sun is `-targetPos / |targetPos|`. Using `atan2(targetPos.x, targetPos.z)` (positive args) places the camera on the anti-Sun side and the target renders unlit.

Distance:
```swift
distance = extent * baseMultiplier * (0.5 + 0.5 * min(aspect, 1))
```

- `baseMultiplier = 0.8` for moon-hosting bodies (Earth, Mars, Jupiter, Saturn) — frame includes moons.
- `baseMultiplier = 6.0` for moonless ones (Mercury, Venus, Uranus, Neptune, Pluto, Sun) — pull back to give context.
- The aspect-scaled portrait factor tightens the frame on phones where the constraining dimension is much smaller than landscape.

### Lazy-follow mission camera (geocentric only)

For Apollo/Artemis-style missions that orbit Earth:

1. Compute `missionBounds(missionId)` — the trajectory's local AABB (Earth-relative). Returns `nil` for heliocentric missions (use overview reset instead).
2. Apply Sun-side framing as above, with `distance = radius / tan(30°) * 1.4` to fit the trajectory's local radius into a portrait viewport.
3. Per-frame, lerp the camera target toward `earthScenePos + localCenter` at `0.02/frame` so the trajectory stays centred as Earth drifts.
4. Hook the gesture coordinator's `.began` callback (not `.changed`) to clear the lazy-follow flag — user touches anywhere → full manual control for the rest of the session.

Heliocentric missions span AU; framing them tightly breaks because the trajectory overlaps the Sun. Skip framing and do an overview reset.

### Framing reads node positions, not init defaults

Before any camera-framing math reads `node.position`, run the per-frame `updatePositions(...)` once for the current simulated date. Otherwise nodes are still at their default origin and you'll frame on `(0, 0, 0)` (the Sun). Same gotcha applies to launch-arg `-focus` handling — defer until the camera coordinator connects, then run positions, then frame.

## SceneKit gotchas (everything below has bitten this domain)

### `allowsCameraControl` conflicts with programmatic camera

SceneKit's built-in `allowsCameraControl` maintains internal state that fights any programmatic camera moves. **Disable it entirely** and implement custom gestures with explicit spherical state (`target`, `distance`, `azimuth`, `elevation`).

### `SCNText` can't hold constant screen size

3D text labels grow/shrink with zoom. For HUD-style labels that must stay readable at all zoom levels, project 3D positions to screen coords each frame and render with SwiftUI `Text` views overlaid on the SCNView.

### `SCNView.projectPoint` blocks the render thread on macOS

Each call waits ~16.7 ms (one 60 Hz frame) for a render-thread sync. Projecting 26 bodies per UI-update frame at high time-scales = 230–280 ms stutter every ~1 s. **Bypass it**: build the view × projection matrix once per frame, then do the world → clip → screen maths with SIMD (sub-millisecond for dozens of points). Same code path on iOS is also ~100× faster than `projectPoint`.

### `camera.projectionTransform`'s aspect term doesn't track viewport on macOS

The matrix it returns has a `[0][0]` term that doesn't match the live `view.bounds` aspect, so labels drift horizontally from their bodies. Construct the projection matrix yourself from `camera.fieldOfView` + live aspect each frame.

```
horizontal FOV (macOS default):  xScale = f,         yScale = f * aspect
vertical   FOV (iOS default):    xScale = f / aspect, yScale = f
where f = 1 / tan(fov/2)
```

### `SCNCameraProjectionDirection` has no `.automatic` case

Only `.horizontal` and `.vertical`. macOS defaults to horizontal, iOS to vertical. Applying the wrong formula stretches one axis.

### Label screen-radius needs the real projection factor

To offset labels just above each body's on-screen disc:

```
cachedPixelsPerUnit = yScale * (viewportHeight / 2)   // cached per frame
screenR             = worldRadius * cachedPixelsPerUnit / clip.w
offsetY             = max(8, screenR + 4)             // 8 pt floor for non-sphere nodes
```

A rough `r / clip.w * 300` formula undershoots on widescreen Mac windows by 3–4× — labels land *inside* the planet disc.

### SwiftUI label overhead

100+ labels re-rendered via `@Published` every frame kills performance. Throttle re-projection to every 3rd frame, hide labels entirely during zoom-slider drags.

## Performance debugging

For real-time scenes, ship a `-frameLog` launch arg that prints per-frame timing with sub-phase breakdown (e.g. `bodies`, `stars`, `decon`, `mm`, `mui`):

- Print every tick > 20 ms or work > 5 ms (individual STUTTER lines)
- Print a once-per-second summary (fps, worst tick, worst work)

When a single sub-phase column spikes while others stay flat, the stutter is localised — that's how `projectPoint` blocking was tracked down (bodies ballooned to 230 ms, everything else stayed under 1 ms, pointing straight at per-label projection).

Recipe (macOS):
```bash
APP=$(find ~/Library/Developer/Xcode/DerivedData/<Project>-*/Build/Products/Debug/<Project>.app -maxdepth 0 | head -1)
"$APP/Contents/MacOS/<Project>" -frameLog > /tmp/frame.log 2>&1 &
sleep 10
grep STUTTER /tmp/frame.log | head -20   # individual slow frames, with sub-phase breakdown
grep summary  /tmp/frame.log | head -10   # once-per-second roll-up
pkill -f "Contents/MacOS/<Project>"
```

Healthy output: `fps~60 worst-dt=16.8ms worst-work=3.3ms` per second.

## Testing

Pure-math helpers (scaling, Catmull-Rom sampling, Kepler solver, rotation math) belong in `internal static` (or `nonisolated`) functions taking explicit parameters. They run identically on iOS Simulator and macOS — and macOS is much faster for CI since there's no simulator boot.

Test specifically:
- Log distance monotonicity, moon compression formula, sqrt radius clamps/floors.
- CatmullRom endpoint hits, interior uniform-u hits, two-point linearity, time-parameterised sampling, out-of-range clamping, degenerate-waypoint safety.
- Mission rotation, anchor resolution, autoTimeScale preset snap, transfer-arc monotonic timeline.
- Event fire-once + rewind reset (cursor must reset even when sim time is outside the active window, so jumping pre-launch still clears it).

## Texture / data sources (MIT-redistributable)

These sources have worked, are easy to fetch, and stay clear of share-alike (CC-BY-SA) and non-commercial (CC-BY-NC) licences that would block bundling under a permissive project licence:

- Earth: NASA Blue Marble Next Generation — public domain
- Moon: NASA LRO Camera — public domain
- Mars: USGS Viking MDIM21 via Wikimedia — public domain
- Mercury / Venus / Saturn (body + rings) / Uranus / Neptune: [Solar System Scope](https://www.solarsystemscope.com/textures/) — CC-BY 4.0
- Jupiter: NASA/JPL/SSI Cassini [PIA07782](https://photojournal.jpl.nasa.gov/catalog/PIA07782) — public domain
- Pluto: NASA/JHUAPL/SwRI New Horizons — public domain
- Galilean moons (Io, Ganymede, Callisto): [Björn Jónsson](https://bjj.mmedia.is/) from NASA/JPL Voyager + Galileo data — "publicly available, please mention origin" (CC-BY-equivalent)
- Europa: NASA/JPL Voyager/Galileo mosaic via Wikimedia — public domain
- Stars: Yale Bright Star Catalog 5th Rev. (BSC5), Hoffleit & Warren 1991 / NASA Goddard NSSDC/ADC, via [VizieR V/50](https://cdsarc.cds.unistra.fr/viz-bin/cat/V/50) — public domain

**Avoid for MIT-redistributable projects:**
- Planet Pixel Emporium (James Hastings-Trew) — "free non-commercial" only
- HYG Database v3+ (astronexus) — CC-BY-SA 4.0 (share-alike is viral copyleft)
- Steve Albers' planetary maps — page declares "personal non-commercial use only" despite being derived from public-domain NASA data

NASA, USGS, and PDS-hosted Cassini data are public domain (US Government works). Solar System Scope textures are CC-BY 4.0 — credit them. Björn Jónsson's terms ("publicly available, please mention origin") are functionally CC-BY. All three categories can be bundled with a permissive (MIT/BSD/Apache) project licence as long as the attributions are preserved (typically via a `THIRDPARTY.md` notice file and an in-app credits panel).

---

# SolarSystem - Claude Code Developer Reference

## Overview

A GPU-accelerated solar system simulation for **iPhone and macOS**, using real Keplerian orbital mechanics (JPL J2000.0 elements) to calculate planet, moon, and Sun positions based on the current date and time. SceneKit renders the 3D scene with NASA/public-domain texture maps on all planets and major moons. 8,404 real stars from the Yale Bright Star Catalog (BSC5) form the backdrop, with correct positions, magnitudes, and colours. All bodies rotate at their real IAU sidereal rates with correct axial tilts. Custom gesture handling provides platform-native navigation: touch gestures on iOS (one-finger pan, two-finger orbit, pinch-to-zoom) and mouse / trackpad on macOS (left-drag pan, right-drag orbit, scroll / pinch zoom).

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
- **Real star catalogue**: 8,404 stars from Yale Bright Star Catalog 5th Rev. (BSC5, Hoffleit & Warren 1991, NASA Goddard NSSDC/ADC, public domain) via VizieR V/50. Filtered to naked-eye visibility (V ≤ 6.5). ~370 named stars labelled. Build script at `tools/build_stars.py` regenerates `Textures/stars.csv` from the raw VizieR catalogue.
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
├── run-macos.sh                       # macOS Release build → /Applications → launch
├── run_phone.sh                       # iPhone build (signed) → install → launch
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
    │   ├── saturn_rings.png            # Ring colour + alpha (2048x125 RGBA, 12 KB)
    │   └── stars.csv                    # Yale BSC5: 8,404 stars (258 KB)
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
| Saturn (+rings) | Solar System Scope | CC-BY 4.0 |
| Pluto | NASA/JHUAPL/SwRI New Horizons | Public domain |
| Io, Ganymede, Callisto | Björn Jónsson, from NASA/JPL Voyager + Galileo data | Publicly available, attribution requested |
| Europa | NASA/JPL Voyager/Galileo via Wikimedia | Public domain |
| Stars | Yale Bright Star Catalog 5th Rev. (BSC5, NASA Goddard NSSDC/ADC) via VizieR V/50 | Public domain |

### Saturn ring tinting (SceneKit specific)

The Solar System Scope ring texture (`saturn_rings.png`) is essentially a luminance/alpha density map with negligible chroma. Without a tint, the rings render greyscale. The fix in `SceneBuilder.swift` is to apply a warm cream tint via the material's multiply channel:

```swift
ringMaterial.diffuse.contents = ringImage         // RGBA — Three.js's `map`
ringMaterial.transparent.contents = ringImage      // alpha channel for transparency
ringMaterial.multiply.contents = PlatformColor(red: 0xE8/255, green: 0xD8/255, blue: 0xB8/255, alpha: 1)
```

`#E8D8B8` is the same value used by the web port and reads as a Cassini-natural-colour cream. More saturated tints (e.g. `#D4B483`) take the rings brown — too warm. SceneKit's `multiply.contents` is the equivalent of Three.js's `material.color`: the channel is multiplied with the diffuse texture per-pixel, preserving the alpha-encoded ring banding while shifting hue.

## Licence

Source code is MIT (see `LICENSE`). Bundled assets each carry their own
licence — see `THIRDPARTY.md` for the full inventory. All bundled assets
permit redistribution including commercial use when their attributions are
preserved. The Credits sheet in `Views/CreditsView.swift` (top-right toolbar
button) also surfaces these to end users at runtime.

Replacing assets must keep the project MIT-redistributable: avoid CC-BY-SA
(viral/share-alike) and "non-commercial only" sources. Acceptable additions:
NASA/USGS public-domain works, CC-BY 4.0 (e.g. Solar System Scope), and
"publicly available, please mention origin" assets like Björn Jónsson's
maps. The star catalogue is reproducible from `tools/build_stars.py` against
the public-domain VizieR BSC5 (V/50) source.

## Project-Specific Implementation Notes

The general orbital-mechanics pipeline, IAU rotation model, scaling formulas, mission/trajectory architecture, camera framing math, and SceneKit gotchas all live in the `astro` skill. This section just records the SolarSystem-specific glue.

### Shared astronomical constants

`OrbitalMechanics.j2000` (2451545.0) and `OrbitalMechanics.kmPerAU` (149,597,870.7) are the single source of truth for every date-to-epoch and AU-to-km conversion in the app. Earth's radius in km is referenced from `SolarSystemData.earth.physical.radiusKm` rather than hardcoded in mission compression maths.

### Scene Graph

```
SCNScene (black background)
├── Camera (custom-controlled, FOV 60°, zNear 0.01, zFar 1000)
├── Starfield (8,404 BSC5 stars, 4 brightness tiers, B-V colour, r=500)
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
├── [Moon] (PBR, texture or colour, tidally locked rotation)
└── mission_<id> (SCNNode group, positioned at Earth or origin)
    ├── trajectory_line                              # SCNGeometryElement .line + per-vertex colours
    └── vehicle_marker                               # emissive SCNSphere + additive halo child
```

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

### Where the mission data lives

The waypoint data is a one-shot export from `../solarsystem-web/js/missions.js`. Run `node tools/export-missions.mjs` whenever upstream waypoints change; the script evaluates the data-declaration portion of missions.js (everything before `class MissionManager`) in a sandboxed Node context with stubbed imports and writes `SolarSystem/Resources/Missions.json`.

App startup decodes the JSON through a `MissionJSON` DTO layer (in `MissionData.swift`) that converts to the domain `Mission` / `Vehicle` / `Waypoint` structs. The DTO layer isolates Swift's Codable from the ergonomic domain types — the domain types keep their custom initialisers and convenience computed properties, while the DTO tracks whatever shape the JSON happens to have.

### Mission data shape (Swift structs)

| Type | Fields | Notes |
|------|--------|-------|
| `Mission` | id, name, subtitle, launchDate, durationHours, flybyTimeHours, referenceFrame, events, vehicles | `autoTimeScale()` snaps `durationHours * 80` to nearest preset in {100, 1k, 10k, 100k, 1M, 10M} |
| `Vehicle` | id, name, color, primary, waypoints, moonOrbit?, moonLanding?, moonOrbitReturn? | `primary` → camera tracks and telemetry reads from this vehicle |
| `Waypoint` | t (hours), x, y, z, anchorMoon, anchorBody? | km+Moon-aligned (geocentric) or AU ecliptic (heliocentric) |
| `MissionEvent` | t, name, detail, showLabel | `showLabel: false` for Earth-surface events (Launch, MECO, splashdown) |
| `MoonOrbitPhase` | startTime, endTime, periodHours, radiusKm | Runtime circular orbit around the Moon's scene position |
| `MoonLandingPhase` | startTime, endTime | Marker snaps to Moon scene position throughout window |

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
| ISS toggle | Toolbar (`antenna.radiowaves.left.and.right` icon, direct button) | One-tap on/off for the ISS model (`showISS`, persisted). Originally wrapped in a single-item `Menu`; collapsed to a plain `Button` since there's no second satellite to add yet. |

View-model state powering them: `activeMissionId`, `missionTelemetry`, `missionElapsedHours`, `currentEventBanner`, `timelineScrubbing` (flipping this pauses playback and restores prior pause state on release), `lazyFollowActive` (per-frame target lerp toward Earth + trajectory centre). End-of-mission speed-reset fires once when elapsed crosses `durationHours` with `timeScale > 1`, so the simulation doesn't race past splashdown.

**Toolbar icon philosophy**: SF Symbols first, procedural SwiftUI `Canvas` second, bundled assets never. The missions dropdown uses `RocketIcon` (a `Canvas` with three `Path`s for fuselage, fins, flame) because there's no SF rocket glyph — see `MissionUIViews.swift`. This keeps the "pure Apple frameworks, zero dependencies" rule intact and avoids asset-catalogue bookkeeping for what's effectively a 40-line vector drawing.

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
| Speed menu | gauge | 0.1x to 1Mx, reverse, Reset to Now (label is a single-line `Text` with `.lineLimit(1)` + `.fixedSize(horizontal: true, …)` so wide values like `"100,000x"` don't wrap into a vertical column) |
| Orbits | circle.circle | Toggle orbital paths |
| Labels menu | tag | Planets / Moons / Stars (independent toggles) |
| ISS | antenna.radiowaves.left.and.right | One-tap toggle for the ISS model |
| Missions | procedural `RocketIcon` | Pick a mission to replay, or stop the current one |
| Planet picker | globe | Jump to any body or overview |
| Home | house.fill | Reset to overview |
| Credits | info.circle | About / texture and data attributions |

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
| `-frameLog` | flag | Print frame-timing diagnostics: any tick > 20 ms or work > 5 ms, plus a once-per-second summary (fps, worst tick, worst work). Phases covered: `bodies`, `stars`, `decon`, `mm` (mission update), `mui` (mission UI). Used to track down the macOS `projectPoint` stutter — see the Performance Debugging section in the `astro` skill. |
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

Use the bundled `run_phone.sh` for the build → install → launch flow:

```bash
./run_phone.sh                                 # plain launch
./run_phone.sh -mission apollo11 -focus earth  # forward launch-args
./run_phone.sh -showISS -frameLog              # ISS visible + frame timing
```

It reads `APPLE_TEAM_ID`, `IPHONE_UDID`, and `IPHONE_BUILD_ID` from
`~/appledev/setupenv.sh` (with the fail-loud `${VAR:?}` guard pattern), builds
for the device with `-destination "id=$IPHONE_BUILD_ID" -allowProvisioningUpdates
DEVELOPMENT_TEAM=$APPLE_TEAM_ID`, installs via `devicectl`, and launches with
any trailing arguments forwarded to the app's `parseLaunchArguments()`.

If you need to invoke `xcodebuild` manually, use this exact form — the bare
`-destination "platform=iOS,name=…"` form silently produces an *unsigned*
`.app` on this project, which then fails to install with `No code signature
found`:

```bash
xcodebuild -project SolarSystem.xcodeproj -scheme SolarSystem \
  -destination "id=$IPHONE_BUILD_ID" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" build

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/SolarSystem-*/Build/Products/Debug-iphoneos/SolarSystem.app -maxdepth 0)
xcrun devicectl device install app --device "$IPHONE_UDID" "$APP_PATH"
xcrun devicectl device process launch --device "$IPHONE_UDID" com.pwilliams.SolarSystem
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

## Frameworks Used

- **SwiftUI** — UI layer, gesture state, overlay labels, zoom slider
- **SceneKit** — 3D rendering, PBR materials, camera, lighting, hit testing
- **UIKit** — UIGraphicsImageRenderer for procedural textures, UIImage for bundled textures
- **Foundation** — Date/calendar, ISO8601DateFormatter, ProcessInfo, UserDefaults
- **simd** — SIMD3<Double> vectors, simd_length

## Project-Specific Gotchas

The general SceneKit gotchas (`allowsCameraControl`, `SCNText` scaling, `projectPoint` blocking on macOS, `projectionTransform` aspect bug, no `.automatic` projection direction, line index pairing, ring UV mapping, depth-buffer rules for trajectories), the orbital-mechanics gotchas (Kepler divergence, angle wrapping, Julian-date precision, IAU rotation via quaternion composition), and the multi-platform gotchas (`Platform.swift` typealiases, frame-tick loop, AppKit Y inversion, `SCNVector3` component types) all live in the `astro` and `macos` skills. This section just records what's specific to SolarSystem.

### Camera plumbing
- **Deferred coordinator**: `cameraCoordinator` is nil during `init()`. Use `pendingFocus` with `didSet`.
- **Focus-at-wrong-time**: `pendingFocus` must run `updatePositions(projectLabels: false)` *before* calling `focusOnBody`, otherwise focus maths read each node's default origin position (because nodes haven't been positioned for the current simulated date yet) and the camera ends up pointed at the Sun. Fixed by calling updatePositions inside the `cameraCoordinator.didSet`.
- **`pendingMissionFraming`**: When `-mission` is set at init and the camera coordinator hasn't connected yet, the framing request is parked and applied in `cameraCoordinator.didSet`. Analogous to `pendingFocus`.
- **Vertical pan direction**: Screen Y is inverted relative to world up. Fixed by flipping `dy * up`.
- **Saturn ring spin**: Rings are child nodes — cancel spin quaternion in local frame each frame.
- **Zoom range consistency**: All zoom controls (slider, pinch, presets, `updateCamera`, `setDistance`) must clamp to the same range (0.5–250). Mismatched minimums cause the slider to snap when switching between manual zoom and presets.

### Missions (project-specific)
- **Main-actor isolation for pure math**: `SceneBuilder` is `@MainActor`, so static scaling helpers used by `MissionManager` + tests need explicit `nonisolated` annotation. Same for `MissionManager.resolveAndRotateWaypointsForTesting` and `Mission.autoTimeScale`.
- **Auto-speed overrides -timeScale**: Setting `activeMissionId` calls `autoTimeScale()` and overwrites whatever the user supplied via `-timeScale`. Intentional — the mission auto-speed targets ~45s replay.
- **JSON export workflow**: `tools/export-missions.mjs` reads `../solarsystem-web/js/missions.js`, slices off everything from `class MissionManager` onward, stubs the imports, and evaluates the data declarations in a Node vm context. Re-run whenever upstream waypoints change; check `Missions.json` into git as the bundled source of truth.
- **DTO vs domain types**: `MissionJSON` in `MissionData.swift` exists only for Decodable conformance; the domain `Mission` / `Vehicle` / `Waypoint` types stay free of Codable boilerplate so they can keep ergonomic custom initialisers. Add new JSON fields to the DTO first, then map in `toDomain()`.
- **Telemetry / banner throttle**: `updateMissionUIState()` runs every 3rd frame (same cadence as label projection) so the publisher doesn't fire at 60 Hz for identical values. If a test needs immediate state, call `seekMission(toElapsedHours:)` which runs a synchronous single-frame update.
- **Timeline scrub pauses playback**: `timelineScrubbing.didSet` flips `isPaused` (restoring the prior value on release) so the display link doesn't advance simulation time while the user drags. Without this, the slider thumb fights the view model's auto-sync.
- **Banner animation re-fires on identical names**: `MissionEventBanner.id` is a `UUID()` rather than the event name, so SwiftUI treats each firing as a distinct identity and re-runs the slide-in transition. Without this, a rewind + replay past the same event would show no animation.
- **End-of-mission auto-reset is one-shot**: `missionEndSpeedResetArmed` prevents the speed-reset from firing every frame once elapsed time has passed `durationHours`. Rearmed when the user rewinds back inside the mission window.
- **Swift expression complexity in tests**: Long chained arithmetic with mixed `Int`/`Double` literals (e.g. `2 * 24 + 14 + 32.0 / 60.0 + 8.0 / 3600.0`) can trip "unable to type-check in reasonable time". Split into named intermediate values with explicit `Double` types.

### ISS / Satellites
- **ISS as a moon, gated by a toggle**: Added to Earth's `moons` array so the existing moon-positioning, label projection, and rotation pipelines apply for free. Hidden by default via `showISS` UserDefaults. The label projection path explicitly skips ISS when `!showISS` — otherwise the "ISS" text would float next to Earth with no geometry beneath it.
- **Procedural geometry, not a sphere**: `SceneBuilder.createBodyNode(for:)` special-cases `body.id == "iss"` and returns the truss+panels+radiators group. The moon sphere isn't created at all, so nothing to hide beyond the group itself.
- **UI: direct toggle, not a menu**: The toolbar's antenna icon is a plain `Button { showISS.toggle() }`, not a `Menu` wrapping a single item. The original Menu form was a placeholder for future Hubble / JWST entries; until those exist, a one-tap toggle is the right shape and matches the orbits-toggle pattern next to it.

### Toolbar reliability (ControlsBarView)
- **Toolbar is an `Equatable` subview, not a computed property of `ContentView`**: `ContentView.body` re-evaluates ~20 Hz while time is ticking because `viewModel.currentDate` and `viewModel.screenLabels` republish on every 3rd frame. With the toolbar inline (the original `controlsBar` computed property) the entire HStack — including all five `Menu`s — was reconstructed at 20 Hz, which made popovers tear down mid-tap, items occasionally fail to register, and dropdowns clip mid-render. Fixed by extracting `ControlsBarView: View, Equatable` with explicit `@Binding`s for the toolbar's actual reads (`isPaused`, `timeScale`, `showOrbits`, label toggles, `showISS`, `activeMissionId`) and closures for actions. SwiftUI uses our custom `==` to skip body evaluation whenever no toolbar-relevant value changed.
- **`MissionsMenu` takes bindings, not the view model**: Same isolation principle — observing `@ObservedObject var viewModel` in a `Menu`-bearing subview reintroduces the 20 Hz rebuild. `MissionsMenu` now takes `@Binding activeMissionId`, `let missions`, and an `onCancel: () -> Void`.
- **Speed-menu label needs `.lineLimit(1)` + `.fixedSize(horizontal: true, vertical: false)`**: Without these, `Text(formatTimeScale(timeScale))` wraps vertically (one character per row) for wider values like `"100,000x"` or `"-100,000x"`, growing the toolbar's height. The fix pins the Text to its natural intrinsic width on a single line; the surrounding HStack has plenty of horizontal room thanks to the `Spacer()`.

### Lazy-follow mission camera (project-specific)
- **Framing depends on up-to-date node positions**: `applyMissionCameraFraming(for:)` calls `updatePositions(projectLabels: false)` once before reading `earthNode.position`, same pattern as `pendingFocus` — without it, Earth is at (0,0,0) and the framing lands at the Sun.
- **User-break runs on `.began`, not `.changed`**: Firing on every gesture delta would spam the handler. Firing on `.began` once is enough — the view model clears `lazyFollowActive` and stops stepping the lerp for the rest of the session.

### Performance (project-specific tuning)
- **SwiftUI label overhead**: 100+ labels re-rendered via `@Published` every frame kills performance. Throttle to every 3rd frame.
- **Zoom slider**: Hide labels during drag gesture to prevent frame drops.
- **Star occlusion**: O(stars × bodies) per frame — keep named star count reasonable (~120).

## Future Roadmap

All six planned port phases are shipped. Future work picks up from the existing backlog:

- Asteroid belt visualisation
- Constellation lines connecting named stars
- Planet info cards with physical data
- AR mode (place solar system on a table)
- Time scrubber UI
- Eclipse prediction
- Unit tests against JPL Horizons
