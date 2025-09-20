# UnifiedScanner Implementation Plan

> This plan defines explicit, ordered steps to build the greenfield UnifiedScanner app **without modifying** the legacy reference projects (BonjourScanner, netscan). Update checkboxes as work progresses. Keep commits narrowly scoped per step where feasible.

## Status Legend
- [ ] Not Started
- [~] In Progress
- [x] Complete

---
## Phase 1: Core Model Foundations
0. [x] Record Architecture Decision: Local-first Option A (in this file and overview) — add note to revisit after Phase 3 completion. (Phase 1 complete)
1. [x] Create `Models/` directory under `UnifiedScanner/UnifiedScanner/`.
2. [x] Implement `Device.swift` with unified domain model (as described in PROJECT_OVERVIEW.md) — include supporting enums + structs (DeviceFormFactor, ClassificationConfidence, DiscoverySource, NetworkService, Port, DeviceConstants, Device.Classification).
3. [x] Add `ModelUtilities/ServiceDeriver.swift` containing `ServiceDeriver` and port→service mapping utilities (copy/adapt logic from netscan `ServiceMapper` & Bonjour service formatting; cite sources in comments).
4. [x] Add `ModelUtilities/IPHeuristics.swift` (copy/adapt core best-IP selection logic from Bonjour reference) — self‑contained.
5. [x] Provide `Device+Mock.swift` with sample mock devices (variety: router, mac, phone, tv, iot) for UI previews & initial list.
6. [x] Write unit tests (in `UnifiedScannerTests`) validating: identity selection, online status, service dedupe ordering, mock generation.

## Phase 2: UI Integration (List & Detail)
7. [x] Replace ad‑hoc `DeviceItem` in `ContentView.swift` with unified `Device` model.
8. [x] Build a lightweight `DeviceRowView` (if not copying) that consumes `Device` (status indicator, primary name, bestDisplayIP/manufacturer snippet, service pill count summary).
9. [x] Refactor `UnifiedDeviceDetail` to consume a `Device` directly; remove local `ServiceItem` / `PortItem` placeholders.
10. [x] Implement richer Open Ports section (port number, service name, status) using unified `Port` type.
11. [x] Implement service pill actions (open http/https, copy ssh) using normalized `NetworkService.ServiceType`.
12. [x] Add SwiftUI previews referencing `Device.mock` set.

## Phase 3: Classification Pipeline (Static Rules)
13. [x] Add `Services/ClassificationService.swift` replicating essential Bonjour strategies (hostname patterns, service signatures, vendor+service, model hints) with normalized outputs.
14. [x] Implement `DeviceClassifier` that produces `Device.Classification` from a `Device`’s current signals. (Implemented as `ClassificationService.classify`.)
15. [x] Add tests for representative classification scenarios (Apple TV vs generic Mac, printer, router, SSH-only host). (HomePod/Raspberry Pi/Xiaomi deferred.)
16. [x] Integrate classification invocation during mock generation & UI (display form factor icon + confidence badge).

## Phase 4: Persistence & Snapshotting
17. [x] Define `DeviceSnapshotStore` (in-memory initially) supporting upsert/merge semantics (merge new signals, preserve firstSeen, update lastSeen, accumulate discovery sources & IPs & services).
18. [x] Add merge tests (new IP appended; MAC stabilization; service dedupe; discoverySources union + ports precedence + classification recompute fingerprint).
19. [x] Implement persistence layer using iCloud Key-Value store (serialize devices JSON under a versioned key; fallback/local JSON optional) + external change observer.
20. [x] Hook store into ContentView (ObservableObject) feeding devices array.

## Phase 5: Discovery Pipeline Implementation ✅ COMPLETED
21a. [x] Define `PingService` protocol + streaming `PingMeasurement` (host, sequence, status[rtt/timeout], timestamp).
21b. [x] Implement `SimplePingKit`-based ICMP ping service for cross-platform probing (replaces earlier Network framework prototype).
21c. [x] Implement concurrent `PingOrchestrator` with 32 max simultaneous operations.
21d. [x] Add conditional factory `PlatformPingServiceFactory.make()` returning Network-based implementation.
21e. [x] Integrate ping RTT updates into `DeviceSnapshotStore` via `applyPing` (updates rttMillis, lastSeen on success).

21. [x] Add protocol `DiscoveryProvider` (async sequence) for future network layers + mock implementation.
22. [x] Implement `DiscoveryCoordinator` coordinating ping + ARP + broadcast UDP phases.
23. [x] Integrate `ARPService` with system ARP table parsing and MAC address capture.
24. [x] Implement broadcast UDP functionality to populate ARP table subnet-wide.
25. [x] Add comprehensive logging with `PING_INFO_LOG=1` and `ARP_INFO_LOG=1` environment variables.
26. [x] Test complete discovery pipeline - successfully detects 1400+ devices on local network.

## Phase 6: Polishing, Discovery Expansion & Docs (macOS + iOS + iPadOS)
25. [ ] Add inline doc comments for each public-facing model type & derived property. // TODO: Include platform nuances (size classes, Catalyst differences) where relevant.
26. [ ] Update `PROJECT_OVERVIEW.md` with any deviations / refinements discovered during implementation. // TODO: Document decision to replace Task.detached with TaskGroup for orchestrators.
27. [ ] Add a brief `ARCHITECTURE_NOTES.md` (if needed) summarizing model merge rules & classification precedence. // TODO: If not adding new file, fold content into PROJECT_OVERVIEW 'Architecture Notes' section instead (user preference: avoid new docs).
28. [ ] Final pass test coverage review; ensure core logic (identity, service normalization, classification) has > minimal threshold. // TODO: Add new tests: ARP MAC merge, RTT update path, multi-source discovery union, classification reasoning ordering.
29. [ ] Prepare a consolidated CHANGELOG entry for Phase 1–3 completion. // TODO: Include Phase 5 discovery achievements & performance metrics; clarify upcoming Phase 6 scope.

### Upcoming Discovery Sequencing
- [ ] Load persisted KV snapshot on launch and render stored devices as offline placeholders until refreshed by live discovery.
- [ ] Add Bonjour (mDNS) scanning provider with start/stop controls (iOS & macOS parity).
- [ ] Restore port scanning tiers with cancellation and UI integration.
- [ ] Provide manual controls to trigger Ping/ARP rescans and toggle Bonjour.
- [ ] Add a settings sheet for timeouts, concurrency, logging, and feature flags.
- [ ] Evaluate additional discovery mechanisms (SSDP, WS-Discovery, reverse DNS) for inclusion or removal.
- [ ] Expand service helpers (browser open, SSH copy, protocol-specific handlers).

---
## Design Rules (Enforced During Implementation)
- No imports from legacy app modules; copy logic with attribution comments.
- Do not rename or refactor existing legacy source paths.
- Keep mutation logic pure & testable (no side-effects outside model/store layers).
- Prefer value semantics (structs) for domain; reference types only for observable stores.
- Avoid premature async network code; stubs only until discovery phase begins.

## Open Questions (Track & Resolve Early)
- Do we need IPv6 prioritization logic beyond existing heuristic? (Default: treat IPv4 private ranges as preferred.)
- Do we store historical RTT samples or only latest? (Currently only latest `rttMillis`; future: rolling window.)
- Should classification reasons be multi-line structured array vs concatenated string? (Initial: single joined string for simplicity.)

## Deferred Backlog (Updated for Phases 6–7)
- OUI ingestion & live vendor lookup bridging to existing `oui.csv` (protocol hook present; data ingest deferred) — Phase 6
- DeviceSnapshotStore + mutation streaming (Phase 4 tasks 17–20) — Phase 6 (AsyncStream emission)
- Discovery provider implementations (Bonjour, ARP, Ping, PortScan stub, SSDP, WS-Discovery) — Phase 6 (mDNS + PortScan), Phase 7 (SSDP, WS-Discovery evaluation)
- Fingerprint enrichment (HTTP banners, SSH parsing) — Phase 7
- Accessibility label audit (service pills, port rows) — Phase 6 (initial), Phase 7 (Dynamic Type stress + VO rotor refinement)
- Theming abstraction (UnifiedTheme struct extraction) — Phase 6 (extract), Phase 7 (light mode, high contrast adjustments)
- UI test coverage (navigation & detail flows) — Phase 7 (after mutation streaming stable)

## Phase 7: Cross-Platform & Enrichment (Planned)
- [ ] Implement mDNS provider (re-author lightweight browser using NetServiceBrowser; emit DeviceMutation events)
- [ ] Reintroduce PortScanner (structured concurrency, cancel support, integrate into enrichment pass)
- [ ] OUI ingestion (parse oui.csv once; build prefix map; cache)
- [ ] Mutation AsyncStream channel from DeviceSnapshotStore
- [ ] Accessibility pass (Dynamic Type XXL+, VoiceOver custom labels, rotor ordering)
- [ ] Theming: extract UnifiedTheme + light mode + high contrast tokens
- [ ] Reverse DNS enrichment provider (optional gating flag)
- [ ] HTTP banner + SSH host key fingerprint capture (fingerprints map population)
- [ ] FeatureFlag enum + environment overrides
- [ ] Internationalization prep: extract strings (English only bundle)

## Immediate Next Action
Implement Phase 1 steps 1–3 (model file, service normalization, heuristics) then add mocks & tests.

---
(End of PLAN.md)
