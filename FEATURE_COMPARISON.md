# Feature & Capability Comparison: BonjourScanner vs netscan vs UnifiedScanner

> Purpose: Authoritative reference matrix mapping legacy capabilities to UnifiedScanner design decisions. Legacy projects are **read-only**. This document guides what we adopt, adapt, or defer. Completion status initially unchecked; update as implementation progresses.

Legend: ✅ = Present / Chosen, ❌ = Absent, ⏳ = Planned / In Progress, ➕ = Enhanced/New

| Feature / Capability | BonjourScanner | netscan | UnifiedScanner Decision | Implementation Notes / Rationale | Location (Lib vs App) | Status |
|----------------------|----------------|---------|-------------------------|----------------------------------|-----------------------|--------|
| Core Device Model (multi-IP) | ✅ `Device.ips:Set` | ❌ (single `ipAddress`) | ➕ Unified uses Set of IPs + primaryIP | Implemented Phase 1 (multi-IP + primary) | App Models | ✅ |
| Primary IP Heuristic | ✅ `bestDisplayIP` via `IPHeuristics` | Partial (single ip means trivial) | ✅ Copy & adapt Bonjour heuristic | Implemented Phase 1 (`ModelUtilities/IPHeuristics.swift`) | App Models | ✅ |
| Multi-source Discovery Tracking | Limited (`discoveryMethod: single`) | ✅ `discoverySource` (single) | ➕ Set<DiscoverySource> | Implemented (model field; merge logic later Phase 4) | App Models | ✅ |
| RTT / Latency Metric | ❌ | ✅ `rttMillis` | ✅ Use optional Double | Field present; live updates deferred (Phase 5) | App Models | ✅ |
| MAC Address Capture | ✅ `mac` | ✅ `macAddress` | ✅ `macAddress` unified naming | Implemented (normalization helper) | App Models | ✅ |
| Vendor / OUI | ✅ `vendor` | ✅ `manufacturer` | ✅ `vendor` primary; alias mapping | Vendor field present; OUI loader deferred | App Models | ✅ |
| Device Type Enum | String + confidence | Strong enum `DeviceType` | ➕ `DeviceFormFactor` + rawType | Implemented; rawType retained for nuances | App Models | ✅ |
| Device Type Confidence | ✅ `DeviceTypeConfidence` | Approx via `confidence: Double?` | ✅ `ClassificationConfidence` enum | Implemented Phase 1 | App Models | ✅ |
| Classification Reason | ✅ `classificationReason` | ❌ | ✅ Stored in `Device.Classification.reason` | Implemented Phase 3 | App Models | ✅ |
| Fingerprints Map | ❌ | ✅ `fingerprints` | ✅ Keep `[String:String]?` | Field present (population deferred) | App Models | ✅ |
| First/Last Seen | ✅ | ✅ | ✅ Preserve both | Implemented | App Models | ✅ |
| Online State Derivation | Computed (5m window) | Explicit `isOnline` flag | ✅ Computed + optional override | Implemented (`recentlySeen` heuristic) | App Models | ✅ |
| Services Representation | `Set<ServiceInfo>` raw types (`_ssh._tcp`) | `[NetworkService]` normalized enum | ➕ Unified `NetworkService` keeps enum + rawType | Implemented Phase 1 | App Models | ✅ |
| Service Display Name Formatting | `ServiceNameFormatter` & pill label compiler | `ServiceMapper` + manual naming | ✅ Merge both: normalization + formatting | Implemented (`ModelUtilities/ServiceDeriver.swift`) | App Models Utility | ✅ |
| Service Deduplication | Limited grouping by display name | `displayServices` logic with port mapping | ✅ Use enhanced netscan logic + improvements | Implemented (displayServices) | App Models Utility | ✅ |
| Port Scanning | ❌ | ✅ `PortScanner`, `openPorts` | ✅ Adopt netscan approach | Model support only; engine deferred (Phase 5+) | Future Library (maybe) | ⏳ |
| Port Model Richness | ❌ | ✅ number/description/status | ✅ Preserve + lastSeenOpen + transport | Implemented | App Models | ✅ |
| Service Pills UI | ✅ (label compiler) | ✅ `ServiceTag` | ✅ Use simplified pills (uppercase text) | Implemented (detail view pills) | App UI | ✅ |
| Device Row UI | ✅ Distinct style | ✅ Provided in ScannerUI | ✅ Rebuild minimal row (avoid package) | Implemented Phase 2 | App UI | ✅ |
| Device Detail UI | ✅ Rich classification emphasis | ✅ Basic + extended ports in netscan | ✅ Unified richer hybrid | Implemented Phase 2 | App UI | ✅ |
| Theme / Design Tokens | `ScannerDesign.Theme` | `Theme` variant in netscan | ✅ Inline `UnifiedTheme` | Basic inline styling; theming file deferred | App UI | ⏳ |
| Classification Strategies | ✅ Multi-strategy classifier | Partial (simpler) | ✅ Port core + advanced vendor/service patterns | Core + extended patterns implemented (Phase 3 expansion) | App Models Utility | ✅ |
| Xiaomi / Vendor Parsing | ✅ Specialized patterns | ❌ | ✅ Included (hostname + vendor heuristics) | Implemented in expanded rules (plug/smart + vendor) | App Models Utility | ✅ |
| OUI Lookup | ✅ (Vendor via file) | ✅ `OUILookupService` | ✅ Protocol hook in place; ingestion later | Hook present (`ClassificationService.ouiLookup`); data ingest deferred | Future Utility | ⏳ |
| ARP Discovery | ✅ (`ARPService/Worker`) | ✅ separate parsers/services | ✅ Reference netscan parsing + Bonjour scheduling concepts | `ARPTableReader` + system ARP table parsing + MAC capture | App Utility | ✅ |
| Ping / Network Reachability | ❌ (light) | ✅ `PingScanner`, `SimplePing` | ➕ Network framework + auto /24 enumeration + concurrent processing | `NetworkPinger` + `PingOrchestrator` + `LocalSubnetEnumerator` + 32 concurrent ops | App Utility | ✅ |
| Bonjour / mDNS Discovery | ✅ Strong | ✅ Basic `BonjourDiscoverer` | ✅ Port BonjourBrowser concepts | Deferred (Phase 5 provider abstraction) | Future Utility | ⏳ |
| SSDP / UPnP | ❌ | ✅ `SSDPDiscoverer` | ✅ Optional later (Phase 5) | Deferred | Future Utility | ⏳ |
| WS-Discovery | ❌ | ✅ `WSDiscoveryDiscoverer` | ⏳ Decide later | Deferred decision | Future Utility | ⏳ |
| Reverse DNS | ❌ | ✅ `DNSReverseLookupService` | ⏳ Candidate for enrichment | Deferred | Future Utility | ⏳ |
| HTTP Service Fingerprinting | ❌ | ✅ `HTTPInfoGatherer` | ⏳ Later enrichment | Deferred | Future Utility | ⏳ |
| SSH Fingerprinting | ❌ | ✅ `SSHFingerprintService` | ⏳ Later enrichment | Deferred | Future Utility | ⏳ |
| MAC Vendor Lookup Source File | ✅ `oui.csv` | ✅ `oui.csv` | ✅ Single copy inside UnifiedScanner Resources | Not yet imported (deferred) | App Resource | ⏳ |
| Persistence (KV / Snapshot) | Partial in-memory | ✅ `DeviceKVStore`, `SnapshotStore` | ✅ Fresh `DeviceSnapshotStore` | Core store & merge logic + iCloud KV persistence implemented (Phase 4 complete) | App Models | ✅ |
| Mutation Event Stream | ✅ `DeviceMutation` | Partial (store events) | ✅ Provide `DeviceMutation` unified | Planned Phase 4 | App Models | ⏳ |
| Logging Infrastructure | ✅ LoggingService | ✅ Debug.swift | ✅ Minimal cohesive logger | Planned Phase 4+ | App Utility | ⏳ |
| Concurrency (actors) | Light | Mixed (actors in some services) | ✅ Actor-based store + scanners | Planned Phase 4 store implementation | App Models/Utility | ⏳ |
| Backend Architecture Pattern | Distinct browser + classification streams | Monolithic services mix | ✅ Adopt decoupled mutation emission (AsyncStream) | Planned Phase 4+ | App Models/Utility | ⏳ |
| Adaptive Navigation (SplitView) | Basic stack | ✅ NavigationSplitView patterns | ✅ Use netscan adaptive approach | Implemented Phase 2 | App UI | ✅ |
| ARP Strategy (iOS Limit Workaround) | Scheduled sysctl polling | Parser + direct read | ✅ Hybrid (Bonjour scheduling + netscan parser) | Deferred (after ARP Discovery impl) | Future Utility | ⏳ |
| Package Modularization Strategy | N/A (single app) | Partial (separate local modules) | ✅ Local-first (Option A) | Completed (removed ScannerDesign/ScannerUI) | Docs / Plan | ✅ |
| Unit Tests Scope | Classification + mutation + IP heuristics | Broad (scanners, heuristics) | ✅ High-value logic first (model, classification, services) | Core tests done (Phases 1–3) | Tests | ✅ |
| UI Tests | Basic list/detail | Basic smoke | ⏳ Basic navigation + detail | Deferred (after Phase 4) | Tests | ⏳ |
| Dark Mode / Theming | Single dark aesthetic | Dark-focused | ✅ Keep dark baseline first | Light theme OOS; theming later | App UI | ⏳ |
| Accessibility Labels | Partial | Partial | ✅ Audit component labels | Deferred audit | App UI | ⏳ |
| Internationalization | ❌ | ❌ | ❌ (Defer) | English only initial | App | ❌ |
| Analytics / Telemetry | ❌ | ❌ | ❌ (Defer) | Potential future instrumentation | App | ❌ |
| Configuration Flags | Minimal | Minimal | ✅ Environment-based simple flags | Future gating (not started) | App Utility | ⏳ |

## Deferred / Backlog Items
- OUI loader integration (single `oui.csv` ingest) — Phase 5 (protocol hook already present)
- Snapshot persistence external change listener + mutation stream (DeviceSnapshotStore + DeviceMutation) — Phase 4 (remaining)
- Discovery providers (Bonjour abstraction, ARP, Ping, PortScan, SSDP, WS-Discovery) — Phase 5
- Fingerprint enrichment (HTTP banners, SSH host key parsing) — Phase 5/6
- Accessibility audit (labels for pills, port rows) — Phase 6
- Theming abstraction (UnifiedTheme) — Phase 6
- UI tests (navigation + detail) — After store integration (Phase 4)

## Feature Adoption Notes
- When both implementations exist, preference was chosen based on richer semantics (e.g., netscan ports + Bonjour multi-IP).
- Some netscan utilities (ServiceMapper, PortScanner) are conceptually adopted but **not copied verbatim yet** — they’ll be reauthored with only necessary surface area to reduce legacy baggage.
- For classification, we intentionally limit early scope to high-signal strategies (hostname patterns, model hints, service signatures, vendor+service) to keep implementation lean while preserving major wins.

## Libraries vs In-App Modules
Given your directive to avoid premature packages, previously separate design/UI packages (`ScannerDesign`, `ScannerUI`) will **not** be retained as external packages. Their concepts (theme tokens, row styles, service tags) will be collapsed into local Swift files inside `UnifiedScanner/UnifiedScanner/` under:
- `UI/Theme/UnifiedTheme.swift`
- `UI/Components/DeviceRowView.swift`, `ServiceTagView.swift`

This prevents fragmentation and eases coherent iteration.

## Complement to PLAN.md
- `PLAN.md` drives execution order.
- This matrix serves as: (a) scoping audit, (b) decision log, (c) progress tracker.
- Update the Status column alongside commits.

## Immediate Adjustments to PLAN.md (Needed)
No structural phase changes required. Add explicit tasks:
- Phase 1: Add step after model creation — "Collapse ScannerDesign/ScannerUI concepts locally (Theme + DeviceRow + ServiceTag)".
- Phase 2: Remove dependency on external packages; confirm local UI components.

(These edits will be applied upon confirmation.)

---
*End of FEATURE_COMPARISON.md*