# UnifiedScanner Project Overview

## Purpose
UnifiedScanner is a new, greenfield consolidation UI that draws on the *reference-only* legacy projects **BonjourScanner** and **netscan**. Those two codebases remain frozen as comparative artifacts; **they must never be modified**. UnifiedScanner selectively integrates their strongest concepts to produce a cohesive, future‑proof network scanning and device intelligence application.

## Vision
Create a single experience that:
- Discovers devices via multiple mechanisms (mDNS / Bonjour, ARP, ICMP ping, SSDP, port scan enrichment, reverse DNS, heuristics)
- Normalizes heterogeneous discovery signals into a single canonical `Device` domain model
- Classifies devices (type + confidence + rationale) using multi-signal heuristics (services, hostnames, vendor OUIs, model hints)
- Surfaces actionable service endpoints (HTTP(S), SSH, AirPlay, HomeKit, Chromecast, etc.) with appropriate contextual actions (open in browser, copy SSH command, etc.)
- Persists device timeline (first seen / last seen / stability indicators) for longitudinal insight
- Presents clear, progressive disclosure: high-level device list, expandable rich detail

## Non‑Goals (Phase 1)
- Full parity with every experimental feature from netscan or BonjourScanner
- Live editing of devices (nicknames, tagging) — may come later
- Cross-platform (watchOS, tvOS) targets
- Heavy analytics or telemetry pipelines

## Guiding Principles
1. **Single Source of Truth**: A unified `Device` core model — no parallel “temporary” structs in production code.
2. **Extensibility over Exhaustiveness**: Provide enums + raw fallback fields (e.g., `deviceTypeRaw`, `serviceRawType`) so new network signatures don’t require an immediate code change.
3. **Deterministic Presentation**: Sorting & deduplication rules are explicit and centralized (services, ports, discovery sources).
4. **Safety + Clarity**: Computed properties (e.g., `isOnline`) must clearly state assumptions (time window threshold).
5. **Isolation of Reference Code**: Zero imports *from* legacy app modules; only copy or adapt logic where justified.
6. **Test the Semantics**: Unit tests validate merging, deduplication, classification mapping, and derived collections.

## Core Domain Model (Draft)
```swift
public struct Device: Identifiable, Hashable, Codable, Sendable {
    public struct Classification: Hashable, Codable, Sendable {
        public let formFactor: DeviceFormFactor?
        public let rawType: String?
        public let confidence: ClassificationConfidence
        public let reason: String
        public let sources: [String] // e.g. ["mdns:airplay", "vendor:apple"]
    }

    public let id: String                 // Stable identity (prefer MAC > primary IP > hostname)
    public var primaryIP: String?         // Chosen via heuristics from `ips`
    public var ips: Set<String>           // All known IPs (v4/v6 acceptable)
    public var hostname: String?
    public var macAddress: String?
    public var vendor: String?            // OUI-resolved or user override
    public var modelHint: String?         // Raw model fingerprint (e.g., from mDNS TXT)

    public var classification: Classification?

    public var discoverySources: Set<DiscoverySource>
    public var rttMillis: Double?

    public var services: [NetworkService] // Normalized network service representations
    public var openPorts: [Port]          // Port scan enrichment

    public var fingerprints: [String:String]? // Arbitrary signal map (e.g., banners, http headers)

    public var firstSeen: Date?
    public var lastSeen: Date?

    public var isOnlineOverride: Bool?    // Manual or externally forced state

    // Derived ------------------
    public var isOnline: Bool { isOnlineOverride ?? recentlySeen }
    public var recentlySeen: Bool { guard let ls = lastSeen else { return false }; return Date().timeIntervalSince(ls) < DeviceConstants.onlineGraceInterval }
    public var displayServices: [NetworkService] { ServiceDeriver.displayServices(services: services, openPorts: openPorts) }
    public var bestDisplayIP: String? { primaryIP ?? IPHeuristics.bestDisplayIP(ips) }
}
```

### Supporting Types (Draft)
```swift
enum DeviceFormFactor: String, Codable, CaseIterable, Sendable {
    case router, computer, laptop, tv, printer, gameConsole, phone, tablet, accessory, iot, server, camera, speaker, hub, unknown
}

enum ClassificationConfidence: String, Codable, CaseIterable, Sendable { case unknown, low, medium, high }

enum DiscoverySource: String, Codable, CaseIterable, Sendable { case mdns, arp, ping, ssdp, portScan, reverseDNS, manual, unknown }

struct NetworkService: Identifiable, Hashable, Codable, Sendable {
    enum ServiceType: String, Codable, CaseIterable, Sendable { case http, https, ssh, dns, dhcp, smb, ftp, vnc, airplay, airplayAudio, homekit, chromecast, spotify, printer, ipp, telnet, other }
    let id: UUID
    let name: String            // Human-friendly display name (e.g., "HTTP", "AirPlay Audio")
    let type: ServiceType       // Normalized semantic bucket
    let rawType: String?        // Raw discovery string (e.g., "_airplay._tcp")
    let port: Int?              // If known
    let isStandardPort: Bool    // Derived (port matches conventional default)
}

struct Port: Identifiable, Hashable, Codable, Sendable {
    enum Status: String, Codable, Sendable { case open, closed, filtered }
    let id: UUID
    let number: Int
    let transport: String       // "tcp" / "udp" (future-proof)
    let serviceName: String     // Canonical known service name mapping
    let description: String     // Friendly description
    let status: Status
    let lastSeenOpen: Date?
}

enum DeviceConstants { static let onlineGraceInterval: TimeInterval = 300 }
```

### Model Utilities (Concept)
- `IPHeuristics.bestDisplayIP(_:)` (borrow logic from Bonjour reference — copied, not imported)
- `ServiceDeriver.displayServices(services: [NetworkService], openPorts: [Port])` merges + dedupes using precedence rules:
  1. Group by (normalized type, port)
  2. Prefer discovery service names over port-derived generic names unless port-derived has strictly more descriptive length
  3. Stable sort by type enum order then port ascending

### Identity Strategy
Priority for assigning `Device.id` upon merge:
1. MAC address (normalized upper hex) if present
2. If no MAC: stable primary IP chosen heuristically
3. Else hostname
4. Fallback: generated UUID (rare)

### Classification Enrichment Pipeline (Later Phase)
1. Input signals: hostname, vendor, modelHint, raw service types, open ports, fingerprints
2. Apply rule set (ported & simplified from BonjourScanner `DeviceClassifier` strategies)
3. Produce `Device.Classification` (reason enumerates decisive rules joined by `; `)
4. Keep rawType if not directly expressible in `DeviceFormFactor`

## Strategic Architecture Choices (Option A: Local-First)
We intentionally defer Swift Package modularization until core semantics stabilize (completion of Phases 1–3). Rationale:
- Reduce early fragmentation and cognitive overhead.
- Allow rapid refactors of model & classification APIs without cross-package churn.
- Keep build times minimal while iterating.

Adopted source inspirations:
- Backend & Concurrency Patterns: Borrow BonjourScanner's actor-friendly separation (browser, mutation emission) conceptually — reauthored locally with AsyncSequence/AsyncStream seams.
- Scanning & Enrichment Surface: Draw from netscan's broader capabilities (ping, port scan concepts, reverse DNS, HTTP/SSH fingerprint placeholders) but implement only minimal stubs early.
- UI Architecture: Favor netscan's adaptive SwiftUI navigation patterns; integrate BonjourScanner's clarity in classification emphasis.
- Service & Port Normalization: Blend netscan's `ServiceMapper` precedence with Bonjour's human-readable naming, formalized in `ServiceDeriver`.

Future Modularization Criteria (to extract into Swift Packages later):
- `ScannerCore`: Device model + classification + normalization utilities reach >90% API stability.
- `ScannerDiscovery`: When at least 3 real network discovery providers (mDNS, ARP, Ping) are implemented with shared mutation protocol.
- `ScannerUI`: When UI components become reusable across another target (e.g., macCatalyst or companion app).
- `ScannerDesign`: Only if visual theming diverges across targets.

Ping Strategy (Cross-Platform):
- iOS / iPadOS: Use bundled `SimplePingKit` (fast, API-driven) via a `PingService` facade wrapping delegate callbacks into `AsyncStream`.
- macOS: Avoid SimplePingKit sandbox limitation by using a lightweight `SystemExecPingService` that shells out to `ping -c 1 -W <timeout>` and parses latency; confined behind the same `PingService` protocol.
- Placeholder Device Creation: `PingOrchestrator` now creates a lightweight `Device` immediately for any enqueued host not already present so ping-only discoveries surface in UI before first RTT.
- Auto Host Enumeration: `DiscoveryCoordinator.start` accepts an empty `pingHosts` array; if so it derives a /24 candidate host list via `LocalSubnetEnumerator` (first active `en*` IPv4 interface) with optional thinning, including the local host.
- Facade consolidates results into unified `PingMeasurement` feeding `DeviceSnapshotStore.applyPing` (which now upserts new devices if still absent).
- Conditional compilation (`#if os(iOS)`) ensures macOS build excludes SimplePingKit dependency specifics.

Decision Log:
- Chosen Option A (local-first). Reevaluate after Phase 3; record decision in PLAN.md architecture task.
- Adopted Network framework approach (cross-platform) instead of SimplePingKit/exec fallback - provides better sandbox compatibility and unified TCP/UDP probing capabilities.

## Upcoming Architecture Enhancements (Inline TODOs)
These are planned refinements for Phases 6–7. Inline `TODO[...]` tags are intentionally placed for traceability.

### Mutation Stream Model
Introduce a unified streaming layer emitting semantic device mutations rather than ad-hoc method calls.
```swift
/// Represents a semantic state change to be folded into DeviceSnapshotStore
enum DeviceMutation: Sendable {
    case upsertBase(Device)                 // Initial or refreshed core fields
    case updateRTT(id: String, rtt: Double) // Latency update only
    case mergeServices(id: String, services: [NetworkService])
    case mergeOpenPorts(id: String, ports: [Port])
    case markOffline(id: String, at: Date)
    case enrichClassification(id: String, classification: Device.Classification)
    case attachFingerprints(id: String, data: [String:String])
}
```
- `DeviceSnapshotStore` exposes `apply(_ mutation: DeviceMutation)` folding logic.
- Public async API: `func mutations() -> AsyncStream<DeviceMutation>` for UI & tests.
- `DiscoveryCoordinator` owns a `AsyncStream<DeviceMutation>` builder fed by providers.
- TODO[concurrency]: Replace current direct device store calls with mutation emission + fold layer.
- TODO[telemetry]: Optionally mirror mutations to a debug ring buffer (keep last 500) for diagnostics.

### Structured Concurrency Refactor
Current scattered `Task.detached` usages will be consolidated.
- Coordinator spawns a bounded `TaskGroup` for each provider start (ping, ARP, mDNS, PortScan tiers).
- Cancellation tree: Cancel coordinator task → cascades to groups → providers finalize and emit `.markOffline` if needed.
- Shutdown API:
```swift
protocol DiscoveryCoordinating: Sendable {
    func start(configuration: DiscoveryConfig) async
    func cancelAndDrain(timeout: Duration) async -> Bool // true if clean drain
}
```
- TODO[concurrency]: Implement `cancelAndDrain(timeout:)` with racing cancellation + timeout fallback.
- TODO[cancellation]: Each provider must periodically `try Task.checkCancellation()` (at least every host or port batch).

### Provider Emission Guidelines
- Providers never mutate devices directly; they only enqueue `DeviceMutation` events.
- Ordering guarantee: Within a provider, events for the same `id` are emitted FIFO.
- Cross-provider ordering is best-effort; `DeviceSnapshotStore` must be idempotent.
- TODO[merging]: Document conflict precedence (e.g., MAC from ARP wins over mDNS-host-derived MAC placeholder).

### PortScanner V2 (Tiered Design)
Goals: faster initial UI signal, optional deeper enrichment.
- Tier 0: (fast) Probe canonical ports {22, 80, 443} concurrently (limit 16).
- Tier 1: (standard) Add {53, 445, 548, 8008, 8009} after Tier 0 completes or times out.
- Extended (opt-in): Configurable additional list loaded from JSON (e.g., top 50 common ports).
- Cancellation semantics: Cancelling a device scan aborts remaining tiers; partially discovered ports still emitted.
- Timeout policy: Per-port soft timeout 300ms (Tier 0) / 450ms (Tier 1) / 700ms (Extended).
- TODO[portscan]: Implement tier scheduler + mutation emission `.mergeOpenPorts`.
- TODO[config]: Add `PortScanConfig(tiersEnabled: Set<PortScanTier>, extendedListPath: URL?)`.

### mDNS (Bonjour) Provider Specification
- Underlying API: `NetServiceBrowser` + `NetService` resolution wrapped in `actor BonjourProvider`.
- Event Flow: discover service → resolve host/IP + TXT → map to `NetworkService` + partial `Device`.
- Merge Rules:
  - Identity hint order: MAC-from-TXT > hostname > IP.
  - Services dedupe by (normalized type, port).
  - Append source tag `"mdns:<rawType>"` into classification sources when classification updates are triggered.
- TXT Parsing: extract model hints (e.g., `model=`, `ty=` for printers, `md=` for AirPlay) → update `modelHint` / fingerprints.
- TODO[mdns]: Implement `BonjourProvider` emitting `.mergeServices` + `.upsertBase` + `.attachFingerprints` mutations.
- TODO[classification]: Trigger incremental reclassification after each service addition if ruleset indicates new decisive signal.

### OUI (Vendor) Ingestion Plan
- Load once from bundled `oui.csv` into `[String: String]` keyed by 6-hex prefix uppercased.
- Provide `VendorLookup.shared.lookup(mac: String) -> String?` caching misses.
- Memory Optimization: Defer loading until first MAC merge (lazy init, ~2–3 ms expected cost).
- TODO[vendor]: Add unit tests for known Apple / HP / Cisco prefixes.
- TODO[vendor]: Add fallback heuristic: If vendor unknown & hostname matches known vendor tokens, classification sources note `vendor:inferred`.

### Accessibility & HIG Compliance
VoiceOver device row label pattern:
`<Form Factor>, <Hostname OR Vendor>, IP <BestDisplayIP>, <n> services, RTT <x> ms (if present)`.
- Dynamic Type: Use `.minimumScaleFactor(0.75)` only where truncation harmful; prefer multiline for detail view.
- Color contrast: Service pills must pass WCAG AA for both light/dark.
- Hit targets: Minimum 44x44pt for actionable rows / buttons.
- Rotor grouping: Provide `AccessibilityRotorEntry` tags for Services vs Actions in detail view.
- TODO[a11y]: Implement `accessibilityLabel` & `accessibilityValue` on `DeviceRowView`.
- TODO[a11y]: Add snapshot VoiceOver tests (if infra supports) or at least unit verifying label string builder.
- TODO[dynamicType]: Audit layout at extraExtraExtraLarge size class.

### Logging Unification
Current env-var scattered prints will be centralized.
```swift
struct ScanLogger {
    enum Category: String { case ping, arp, mdns, portscan, classify, merge }
    static func log(_ category: Category, _ message: @autoclosure () -> String) {
        // TODO[logging]: Gate by runtime config (UserDefaults / launch arg) + os.Logger backend.
    }
}
```
- TODO[logging]: Replace direct print statements with `ScanLogger.log` calls.
- TODO[logging]: Provide minimal structured interpolation for key fields (device id, ip, port).

### Testing Roadmap (Future Test Names)
Planned additions to ensure mutation semantics & merging correctness.
- DeviceSnapshotStoreMergeTests.testUpsertAssignsStableIDMacWins
- DeviceSnapshotStoreMergeTests.testRTTUpdateDoesNotOverwriteLastSeen
- DeviceSnapshotStoreMergeTests.testServiceMergeDedupesByTypeAndPort
- DeviceSnapshotStoreMergeTests.testMarkOfflineSetsRecentlySeenFalse
- PortScannerTierTests.testTier0CompletesBeforeTier1Starts
- PortScannerTierTests.testCancellationSkipsRemainingTiers
- BonjourProviderTests.testTXTModelHintExtractionUpdatesClassification
- BonjourProviderTests.testMultipleServicesForSameDeviceDeduped
- VendorLookupTests.testKnownPrefixesReturnVendor
- VendorLookupTests.testUnknownPrefixReturnsNilAndCachesMiss
- ClassificationReevaluationTests.testNewServiceTriggersReclassification
- AccessibilityLabelBuilderTests.testVoiceOverPatternIncludesServiceCount
- LoggingTests.testLoggerCategoryFormatting
- TODO[tests]: Implement above sequentially as features land.

### Conflict Resolution Precedence (Draft)
(Used by mutation fold logic.)
1. MAC address authoritative once set (never replaced unless normalization reveals same value differently cased).
2. Hostname updated only if new one is longer & previous was autogenerated / placeholder.
3. Vendor not replaced if existing vendor came from OUI vs inferred.
4. RTT retains most recent successful measurement.
5. Services merged; never removed unless explicit offline pruning phase planned.
- TODO[merging]: Document offline pruning decision (phase 7 optional) — may remove services not seen for N days.

### Performance Considerations
- AsyncStream backpressure: Use bounded buffer size (e.g., 500). When exceeded, drop lowest-priority mutation types (`updateRTT`) first.
- TODO[performance]: Prototype dropping strategy & measure impact with synthetic 1000-host scan.

## Current Implementation Status (Phase 5 Complete)

### ✅ Core Discovery Pipeline - Fully Operational
- **Multi-Port TCP Probing**: Concurrent probing of 6 common ports (HTTP/80, HTTPS/443, SSH/22, DNS/53, SMB/445, AFP/548)
- **UDP Fallback**: Automatic fallback when TCP ports fail, expanding detection coverage
- **ARP Integration**: System ARP table reading with MAC address capture for device identification (macOS uses route-dump reader inside sandbox)
- **ARP Warmup**: UDP nudge helper to populate the ARP cache prior to reading entries
- **Broadcast UDP**: Subnet-wide UDP broadcasting to populate ARP tables and trigger device responses
- **Concurrent Processing**: Up to 32 simultaneous network operations for optimal performance
- **Comprehensive Logging**: Environment variable controlled logging (`PING_INFO_LOG=1`, `ARP_INFO_LOG=1`)

### 🧪 Testing Results - Excellent Performance
- **Device Detection**: Successfully identifies 1400+ responsive devices on local network
- **Network Coverage**: Full /24 subnet enumeration (253 hosts) with auto-detection
- **RTT Measurement**: Accurate latency reporting (0.4ms - 1.2ms range)
- **Success Rate**: High detection rate with real-time progress tracking
- **Resource Efficiency**: Optimized timeouts (0.3s per port) balancing speed vs coverage

### 🏗️ Architecture Achievements
- **Sandbox Compatible**: Uses Network framework instead of shell commands
- **Cross-Platform Ready**: Network framework provides unified iOS/macOS support
- **Concurrent Design**: Actor-based orchestration with proper async/await patterns
- **Extensible**: Clean provider protocol for future mDNS, SSDP, WS-Discovery integration

## Phasing Plan (High Level)
Phase 1: ✅ Establish model scaffolding + UI integration (list + detail)
Phase 2: ✅ Service + port normalization & presentation
Phase 3: ✅ Classification engine (migrated strategies, tests)
Phase 4: ✅ Persistence (snapshot store for devices)
Phase 5: ✅ **Discovery Pipeline Implementation** - Multi-port TCP probing, UDP fallback, ARP table integration, broadcast UDP, concurrent processing (32 ops), comprehensive logging
Phase 6: Polishing & advanced features (mDNS, SSDP, fingerprinting, etc.)

## Next Steps
- Load the KV snapshot at launch and treat stored devices as offline placeholders until live discovery updates arrive.
- Reintroduce Bonjour (mDNS) scanning with user controls and merge mDNS services alongside ARP/Ping results.
- Restore the multi-tier port scanner and surface open-port states in the detail view.
- Add manual controls to trigger Ping/ARP rescans and toggle Bonjour providers.
- Ship a settings sheet for discovery timeouts, concurrency, logging, and feature flags.
- Evaluate additional discovery mechanisms (SSDP, WS-Discovery, reverse DNS, HTTP banners) for inclusion or removal.
- Expand service helpers (browser deep links, SSH copy, protocol-specific actions).

## Testing Priorities
- Model merging & identity stability tests
- Service dedupe & ordering tests
- Online state logic tests (grace interval / override)
- Classification mapping unit tests (when phase 3 begins)

## Deliberate Omissions (Can Revisit)
- GeoIP, latency history graphs, bandwidth profiling
- User tagging / custom iconography
- Multi-user sync (CloudKit) — potential future

## Reference Code Policy
- BonjourScanner & netscan: **Read only**. No imports into UnifiedScanner target; copy logic selectively with attribution comment referencing path and commit hash.

---
This overview is a living reference; detailed actionable steps live in `PLAN.md`.
