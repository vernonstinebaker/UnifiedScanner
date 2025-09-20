# UnifiedScanner Project Overview

## Purpose
UnifiedScanner is a greenfield consolidation UI drawing on *reference-only* legacy projects **BonjourScanner** and **netscan**. Those codebases remain frozen; this app selectively adapts their strongest concepts into a cohesive, extensible network scanning and device intelligence experience.

## Vision (Pragmatic Scope)
Create a single experience that:
- Discovers devices via currently implemented mechanisms (ICMP ping + ARP on macOS) and future planned mechanisms (mDNS/Bonjour, port scan enrichment, reverse DNS, SSDP, WS-Discovery) added incrementally.
- Normalizes heterogeneous discovery signals into a canonical `Device` model (multi-IP, services, ports, vendor, classification).
- Classifies devices (form factor + confidence + rationale) using multi-signal heuristics (hostname, vendor, model hints, services, ports when available).
- Surfaces actionable service endpoints (HTTP(S), SSH, AirPlay, printer, etc.) with contextual actions.
- Persists device timeline (first/last seen) and core attributes for continuity across launches.

## Non‑Goals (Early Phases)
- Full immediate parity with every experimental feature from netscan / BonjourScanner.
- Live user annotations (nicknames, tagging) — may come later.
- Broad cross‑platform beyond macOS + iOS/iPadOS targets.
- Heavy analytics or telemetry pipelines.

## Guiding Principles
1. Single Source of Truth: Unified `Device` model; no parallel production structs.  
2. Extensibility Over Exhaustiveness: Enums + raw fallback keep evolving network signatures from blocking releases.  
3. Deterministic Presentation: Centralized service/port dedupe & sorting rules.  
4. Explicit Semantics: Derived states (e.g., `isOnline`) document assumptions (recent activity window).  
5. Reference Isolation: Only copy logic with attribution; never import legacy modules.  
6. Test Intent: Unit tests focus on merging, classification, normalization invariants.  

## Core Domain Model (Implemented)
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
    public var fingerprints: [String:String]?
    public var firstSeen: Date?
    public var lastSeen: Date?
    public var isOnlineOverride: Bool?
    public var isOnline: Bool { isOnlineOverride ?? recentlySeen }
    public var recentlySeen: Bool { guard let ls = lastSeen else { return false }; return Date().timeIntervalSince(ls) < DeviceConstants.onlineGraceInterval }
    public var displayServices: [NetworkService] { ServiceDeriver.displayServices(services: services, openPorts: openPorts) }
    public var bestDisplayIP: String? { primaryIP ?? IPHeuristics.bestDisplayIP(ips) }
}
```
(See source for supporting enums and structs.)

### Identity Strategy
Priority for assigning `Device.id` when merging:
1. MAC address (normalized)  
2. Primary IP  
3. Hostname  
4. Generated UUID fallback  

### Classification Pipeline (Current)
- Signals: hostname, vendor, modelHint, normalized service types, open ports (currently empty until scanner implemented), fingerprints (future).
- Rule set (ported & simplified) yields: form factor, confidence, reason string (semi-colon joined), rawType fallback.
- Re-evaluated automatically when material classification inputs change in `SnapshotService`.

## Architecture Choices (Option A: Local-First)
Delay Swift package modularization until after multiple real discovery providers exist and APIs stabilize. Benefits: faster iteration, simpler refactors, reduced cognitive load.

Adopted inspirations:
- BonjourScanner: classification strategy structuring & multi-signal reasoning, multi-IP device representation.  
- netscan: service/port normalization concepts, ping orchestration pattern (adapted), model richness for ports/fingerprints (structure kept; engine pending).  

## Current Discovery Implementation (Accurate as of this revision)
Implemented:
- ICMP Ping via `SimplePingKitService` wrapped in async stream.  
- `PingOrchestrator` actor throttling concurrency (32 active hosts).  
- Auto /24 host enumeration using `LocalSubnetEnumerator` when no explicit host list provided.  
- ARP (macOS): route table dump + UDP warmup + MAC merge into existing devices.  
- Mutation stream: `SnapshotService.mutationStream` yields snapshots and fine-grained `DeviceChange` events.  
- Persistence: iCloud KVS + UserDefaults mirror at startup (optional clearing via env var).  

Not Yet Implemented (Previously Overstated in Docs):
- Port scanning engine (no TCP multi-port probing active).  
- UDP fallback logic (beyond ARP cache warm UDP nudge).  
- Real mDNS / Bonjour provider (only mock exists).  
- Reverse DNS, SSDP, WS-Discovery providers.  
- HTTP banner / SSH fingerprint extraction.  
- Alternate PingService (Network framework / exec fallback).  
- Structured logging facade (using ad-hoc `print`).  
- Provider → mutation event bus abstraction (providers currently upsert directly).  

## Planned Enhancements (Roadmap Extract)
Short-term (Phase 6): logging abstraction, provider event bus, mDNS provider, tier-0/1 port scanner, OUI ingestion, FeatureFlag system, accessibility labels, theming extraction, initial reverse DNS, basic HTTP/SSH fingerprint capture.
Longer-term (Phase 7+): extended port tiers, SSDP & WS-Discovery, mutation backpressure tuning, offline service pruning policy, internationalization, advanced accessibility (rotor grouping), performance benchmarking, light/high-contrast themes.

## Concurrency & Cancellation (Planned Improvements)
- Replace ad-hoc `Task {}` launches in `PingOrchestrator` with structured task groups & cancellation tokens.  
- Introduce DiscoveryCoordinator shutdown API (cancel & drain).  
- Provider emission shift: producers emit `DeviceMutation` values; store folds and persists.  

## Logging Direction
Introduce `ScanLogger` with categories (`ping`, `arp`, `mdns`, `merge`, `portscan`, `classify`) gating output via FeatureFlag/env, migrating away from scattered prints.

## Accessibility Direction
VoiceOver device row label pattern: `<FormFactor>, <Hostname|Vendor>, IP <BestDisplayIP>, <n> services, RTT <x> ms`.  
Service pills & port list entries to gain descriptive accessibility labels + rotor grouping.  
Dynamic Type stress testing up to XXXL & macOS Large Content Viewer considered in Phase 6.

## Testing Priorities (Next)
- Merge semantics: multi-source union (ping + ARP), RTT update path, classification re-run triggers.  
- mDNS provider tests (service/TXT parsing) once implemented.  
- Port scanner tier scheduling & cancellation tests (future).  
- Vendor/OUI lookup correctness tests after ingestion.  

## Removed / Corrected Prior Claims
- Removed statements asserting multi-port TCP probing & UDP fallback engine — not implemented.  
- Removed claim of Network framework-based unified ping — current implementation exclusively SimplePingKit.  
- Removed large-scale performance claim ("1400+ devices"); no such benchmark present in code/tests.  

## Reference Code Policy
Legacy projects remain read-only; copy/adapt logic with attribution where essential. Future modularization triggered by stable APIs + multiple consumer targets.

## Next Steps Snapshot
1. Introduce logging facade & feature flag scaffolding.  
2. Implement provider → mutation bus (decouple upserts).  
3. Add mDNS provider (NetServiceBrowser) + TXT parsing + classification triggers.  
4. Tier-0 port scanner (22,80,443) feeding `openPorts`.  
5. OUI ingestion service + vendor enrichment tests.  

---
This overview stays synchronized with `PLAN.md` and `FEATURE_COMPARISON.md`; discrepancies should be resolved immediately when features land.
