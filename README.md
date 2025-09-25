# UnifiedScanner

UnifiedScanner is a SwiftUI app that unifies the strongest capabilities from the legacy BonjourScanner and netscan prototypes into a single, modern network discovery experience for Apple platforms. It combines multi-source device discovery, intelligent classification, and persistence to help you understand devices and services running on your local network.

## Feature Highlights
- **Unified device model** that normalizes IPs, MAC addresses, services, ports, vendors, and fingerprints into a single canonical representation.
- **Dependency-injected environment** (`AppEnvironment`) that assembles scanning, classification, logging, and fingerprint services without singletons.
- **Multi-source discovery** via Bonjour/mDNS, ICMP ping (iOS/iPadOS), ARP table inspection (macOS), and tier-0 port scanning (22/80/443) with HTTP fingerprinting.
- **Deterministic merging** of discovery signals using `DeviceMutationBus` and `SnapshotService`, with conflict resolution and deduplication baked in.
- **Modular classification pipeline** (rule strategies + Apple model database) with injectable OUI/lookup providers for deterministic device typing.
- **Dashboard view models** (`StatusDashboardViewModel`, `DeviceDetailViewModel`) powering SwiftUI surfaces with predictable state updates and previews.
- **Session continuity** through iCloud Key-Value Store and UserDefaults, plus runtime logging controls for discovery pipelines.
- **Wi-Fi network detection** with proper entitlements and location services support for accurate SSID resolution.

## Supported Platforms
UnifiedScanner targets the latest Apple platform SDKs (macOS, iOS, iPadOS). Platform-specific behavior:
- **macOS:** ARP discovery is available; raw ICMP is intentionally omitted due to entitlement restrictions.
- **iOS / iPadOS:** Uses `SimplePingKitService` for ICMP-based reachability; ARP is skipped.

## Getting Started
### Prerequisites
- Xcode 15 or newer
- Swift 5.9 toolchain or newer
- macOS 14 (Sonoma) for development (iOS/iPadOS deployment requires the corresponding SDKs)

### Build & Run (Xcode)
1. Clone the repository.
2. Open `UnifiedScanner.xcodeproj` in Xcode.
3. Select the `UnifiedScanner` scheme and your desired destination (Mac, iPhone, or iPad simulator/device).
4. Build and run.

### Build & Test (Command Line)
```bash
# Build the app for macOS
xcodebuild -scheme UnifiedScanner -destination 'platform=macOS' build

# Run unit tests
xcodebuild test -scheme UnifiedScannerTests -destination 'platform=macOS'

# Run full test suite (unit + UI) with discovery disabled for determinism
UNIFIEDSCANNER_DISABLE_NETWORK_DISCOVERY=1 \
xcodebuild test -scheme UnifiedScanner -destination 'platform=macOS'
```

## Repository Layout
- `UnifiedScanner/` – Application source, including discovery services, SwiftUI views, and embedded view models.
- `UnifiedScannerTests/` – Unit tests covering device merging, classification, utilities, and dashboard/device detail view models.
- `UnifiedScannerUITests/` – UI automation (launch smoke tests using deterministic discovery disable flags).
- `UnifiedScanner.xcodeproj/` – Project configuration.
- `.build/` – SwiftPM build products (ignored).
- `PROJECT_OVERVIEW.md`, `PLAN.md`, `FEATURE_COMPARISON.md` – In-depth design, roadmap, and legacy comparison docs.
- `UnifiedScanner.entitlements` – App entitlements including multicast networking and Wi-Fi information access.

## Architecture & Discovery Overview
1. `DiscoveryCoordinator` orchestrates discovery providers and plugs them into the shared `DeviceMutationBus`.
2. Providers emit `DeviceMutation` events:
   - `BonjourDiscoveryProvider` (browse/resolve)
   - `SimplePingKitService` + `PingOrchestrator` (iOS/iPadOS)
   - `ARPService` (macOS)
   - `PortScanService` and `HTTPFingerprintService` enrich services and fingerprints.
3. `SnapshotService` merges incoming mutations into the canonical device list, updates classification via `ClassificationService`, and persists snapshots.
4. `ClassificationService` resolves device type using the injectable `ClassificationRulePipeline` stack plus the Apple model database/OUI lookup supplied by `AppEnvironment`.
5. `UnifiedScannerApp` drives the SwiftUI interface with live device updates, scan controls, and logging settings through observable view models.

## Development Notes
- Toggle runtime logging categories and minimum levels via `AppSettings`.
- Device history is persisted; use the "Clear KV Store" command (macOS) to reset.
- Port scanning currently covers tier-0 ports (22/80/443); expansion is planned.
- Interface information display can be toggled on/off in Settings for a more compact status bar.
- Wi-Fi network name detection requires Location Services to be enabled in System Settings.

## Roadmap & Further Reading
Refer to the following documents for detailed plans and comparisons:
- `PROJECT_OVERVIEW.md` – Architectural goals, models, and guiding principles.
- `PLAN.md` – Phase-by-phase implementation status and upcoming work.
- `FEATURE_COMPARISON.md` – Mapping between legacy apps and UnifiedScanner functionality.

Contributions and feedback are welcome as we continue to expand discovery providers, fingerprinting, accessibility, and test coverage.
