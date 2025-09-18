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

### Derivation Utilities (Concept)
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
- iOS / iPadOS: Use bundled `SimplePingKit` (fast, API-driven) via a `Pinger` facade wrapping delegate callbacks into `AsyncStream`.
- macOS: Avoid SimplePingKit sandbox limitation by using a lightweight `SystemExecPinger` that shells out to `ping -c 1 -W <timeout>` and parses latency; confined behind the same `Pinger` protocol.
- Facade consolidates results into unified `PingResult` (host, latencyMs, timestamp, success) and feeds RTT updates to `DeviceSnapshotStore`.
- Conditional compilation (`#if os(iOS)`) ensures macOS build excludes SimplePingKit dependency specifics.

Decision Log:
- Chosen Option A (local-first). Reevaluate after Phase 3; record decision in PLAN.md architecture task.
- Adopt dual ping implementation (SimplePingKit on iOS, exec fallback on macOS) hidden behind `Pinger` facade to insulate higher layers from platform constraints.

## Phasing Plan (High Level)
Phase 1: Establish model scaffolding + UI integration (list + detail)
Phase 2: Service + port normalization & presentation
Phase 3: Classification engine (migrated strategies, tests)
Phase 4: Persistence (snapshot store for devices)
Phase 5: Incremental discovery pipelines (stubs for mdns/arp/ping/port scan) — actual network code can be layered later

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
