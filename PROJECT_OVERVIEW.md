# UnifiedScanner Project Overview

## Purpose
UnifiedScanner is a greenfield consolidation of network scanning capabilities from legacy reference projects **BonjourScanner** and **netscan**. The legacy codebases remain frozen and read-only; this app selectively adapts their strongest concepts into a cohesive, extensible experience for device discovery and network intelligence on Apple platforms.

## Vision (Pragmatic Scope)
Build a single app that:
- Discovers devices using implemented mechanisms (ICMP ping via SimplePingKit on iOS, ARP table on macOS, mDNS/Bonjour browsing) and planned extensions (port scanning, reverse DNS, SSDP, WS-Discovery). macOS deliberately omits ICMP because sandboxed apps cannot issue raw pings without elevated entitlements.
- Normalizes discovery signals into a canonical `Device` model supporting multi-IP, services, ports, vendor info, and classification.
- Classifies devices (form factor, confidence, rationale) using heuristics from hostname, vendor, services, and ports.
- Provides actionable views of services (HTTP/SSH/AirPlay) with contextual interactions.
- Persists device history (first/last seen, attributes) for session continuity via iCloud Key-Value Store.

## Non-Goals (Early Phases)
- Immediate full parity with all experimental features from legacy projects.
- User annotations (nicknames, tags) — deferred.
- Broad platform support beyond macOS, iOS, iPadOS.
- Telemetry or analytics.

## Guiding Principles
1. **Single Source of Truth:** Unified `Device` model; no duplicate production structs.
2. **Extensibility:** Enums with raw fallbacks for evolving network data.
3. **Determinism:** Centralized deduplication and sorting for services/ports.
4. **Explicitness:** Derived states (e.g., `isOnline`) with documented assumptions.
5. **Isolation:** Copy logic from references with attribution; no direct imports.
6. **Test Focus:** Unit tests target merge logic, classification, normalization.

## Core Domain Model
```swift
public struct Device: Identifiable, Hashable, Codable, Sendable {
    public struct Classification: Hashable, Codable, Sendable {
        public let formFactor: DeviceFormFactor?
        public let rawType: String?
        public let confidence: ClassificationConfidence
        public let reason: String
        public let sources: [String]
    }
    public let id: String
    public var primaryIP: String?
    public var ips: Set<String>
    public var hostname: String?
    public var macAddress: String?
    public var vendor: String?
    public var modelHint: String?
    public var classification: Classification?
    public var discoverySources: Set<DiscoverySource>
    public var rttMillis: Double?
    public var services: [NetworkService]
    public var openPorts: [Port]
    public var fingerprints: [String: String]?
    public var firstSeen: Date?
    public var lastSeen: Date?
    public var isOnlineOverride: Bool?
    public var isOnline: Bool { isOnlineOverride ?? recentlySeen }
    public var recentlySeen: Bool { Date().timeIntervalSince(lastSeen ?? .distantPast) < DeviceConstants.onlineGraceInterval }
    public var displayServices: [NetworkService] { ServiceDeriver.displayServices(services: services, openPorts: openPorts) }
    public var bestDisplayIP: String? { primaryIP ?? IPHeuristics.bestDisplayIP(ips) }
}
```
(See source for enums/structs like `NetworkService`, `Port`, `DiscoverySource`.)

Vendor enrichment pulls from multiple signals: explicit vendor values, fingerprint extraction (TXT records), and OUI prefix lookup via `OUILookupService` (default-initialised at app launch).

### Identity Resolution
Merge priority for `Device.id`:
1. Normalized MAC address
2. Primary IP
3. Hostname
4. UUID fallback

### Classification (Implemented)
- Inputs: hostname, vendor, modelHint, service types, open ports, fingerprints.
- Outputs: form factor (e.g., .router), confidence (.high/.medium), reason (e.g., "hostname: linksys; services: _http._tcp"), sources.
- Auto-recomputed on relevant field changes in `SnapshotService`.

## Architecture (Local-First)
No premature SPM modularization; iterate locally until discovery providers stabilize. Inspirations:
- BonjourScanner: Multi-signal classification, multi-IP models.
- netscan: Service/port normalization, ping orchestration.

## Implemented Discovery
- **ICMP Ping:** SimplePingKitService in async stream with PingOrchestrator throttling (iOS builds). macOS intentionally omits ICMP (sandboxed apps lack the required entitlements) and instead relies on ARP presence.
- **Auto-Enumeration:** LocalSubnetEnumerator for /24 hosts when no list provided.
- **ARP (macOS):** Route table dump + UDP warmup; merges MACs into devices.
- **Bonjour / mDNS:** `BonjourBrowseService` + `BonjourResolveService` feed `BonjourDiscoveryProvider`, emitting devices through the mutation bus.
- **Mutation Bus & Store:** Discovery providers emit `DeviceMutation` events via `DeviceMutationBus`; `SnapshotService` applies them and exposes `mutationStream`.
- **Persistence:** iCloud KVS + UserDefaults mirror with environment flag for clearing on launch.
- **Port Scanning (Tier 0):** `PortScanService` listens to mutation events and probes ports 22/80/443, adding services/open ports and marking hosts online when responsive.

Not Implemented (Planned):
- SSDP / WS-Discovery.
- Reverse DNS enrichment.
- HTTP/SSH fingerprinting pipeline.
- Logging runtime toggles & category controls (logger exists).
- Feature flags for discovery/logging toggles.

## Planned Enhancements
**Short-Term:**
- Logging runtime controls + feature flag surface.
- Accessibility improvements (VoiceOver labels, Dynamic Type audit).
- Port scanning tier expansion & cancellation controls.

**Medium-Term:**
- SSDP/WS-Discovery.
- HTTP/SSH fingerprints.
- Light theme.
- UI tests.

**Long-Term:**
- Snapshot export (JSON/CSV).
- Annotations.
- HomeKit/AirPlay integration.
- Benchmarks (>1000 hosts).

## Concurrency & Cancellation (Planned)
- Structured task groups in PingOrchestrator.
- DiscoveryCoordinator shutdown / cancellation polish.

## Logging (Next Improvements)
- Extend `LoggingService` with runtime category toggles & persisted minimum level.
- Align logging categories with discovery services (ping / arp / mdns).

## Accessibility (Planned)
- Row labels: "<FormFactor>, <Hostname/Vendor>, IP <BestIP>, <n> services, RTT <x>ms".
- Pills/ports: Descriptive labels, rotor grouping.
- Dynamic Type to XXXL; macOS Large Content Viewer.

## Testing Priorities
- DeviceMutationBus buffering/backpressure (multi-subscriber + late subscriber scenarios).
- Bonjour browse/resolve integration with simulated NetServiceBrowser streams.
- Classification regression for OUI + fingerprint vendor inference combinations.
- Port scanner tier scheduling/cancellation (beyond tier 0).

## Reference Policy
Legacy projects read-only; adapt with attribution. Modularize post-stabilization.

## Next Steps
1. Add runtime logging controls (categories, minimum level persistence) & expose as feature flags.
2. Expand port scanning to additional tiers with cancellation/backoff controls.
3. Expand tests for DeviceMutationBus buffering & Bonjour browse/resolve integration.
4. Kick off accessibility audit (VoiceOver labels, Dynamic Type stress).

---
Synchronized with PLAN.md and FEATURE_COMPARISON.md; resolve discrepancies on feature landing.
