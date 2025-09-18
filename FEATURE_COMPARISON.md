# Feature & Capability Comparison: BonjourScanner vs netscan vs UnifiedScanner

> Purpose: Authoritative reference matrix mapping legacy capabilities to UnifiedScanner design decisions. Legacy projects are **read-only**. This document guides what we adopt, adapt, or defer. Completion status initially unchecked; update as implementation progresses.

Legend: ✅ = Present / Chosen, ❌ = Absent, ⏳ = Planned / Not yet implemented, ➕ = Enhanced/New

| Feature / Capability | BonjourScanner | netscan | UnifiedScanner Decision | Implementation Notes / Rationale | Location (Lib vs App) | Status |
|----------------------|----------------|---------|-------------------------|----------------------------------|-----------------------|--------|
| Core Device Model (multi-IP) | ✅ `Device.ips:Set` | ❌ (single `ipAddress`) | ➕ Unified uses Set of IPs + primaryIP | Combines flexibility of Bonjour multi-IP with netscan primary address heuristics | App Models | ⏳ |
| Primary IP Heuristic | ✅ `bestDisplayIP` via `IPHeuristics` | Partial (single ip means trivial) | ✅ Copy & adapt Bonjour heuristic | Preserve heuristics; isolate in `IPHeuristics.swift` | App Models | ⏳ |
| Multi-source Discovery Tracking | Limited (`discoveryMethod: single`) | ✅ `discoverySource` (single) | ➕ Set<DiscoverySource> | Devices often discovered by multiple channels; keep union | App Models | ⏳ |
| RTT / Latency Metric | ❌ | ✅ `rttMillis` | ✅ Use optional Double | Keep latest only initially | App Models | ⏳ |
| MAC Address Capture | ✅ `mac` | ✅ `macAddress` | ✅ `macAddress` unified naming | Normalized uppercase, colon separated | App Models | ⏳ |
| Vendor / OUI | ✅ `vendor` | ✅ `manufacturer` | ✅ `vendor` primary; alias mapping | Prefer neutral term vendor | App Models | ⏳ |
| Device Type Enum | String + confidence | Strong enum `DeviceType` | ➕ `DeviceFormFactor` + rawType | Combine enumeration for UI icons + raw fallback string | App Models | ⏳ |
| Device Type Confidence | ✅ `DeviceTypeConfidence` | Approx via `confidence: Double?` | ✅ `ClassificationConfidence` enum | Use discrete levels; map old float if needed later | App Models | ⏳ |
| Classification Reason | ✅ `classificationReason` | ❌ | ✅ Stored in `Device.Classification.reason` | Preserve explanability | App Models | ⏳ |
| Fingerprints Map | ❌ | ✅ `fingerprints` | ✅ Keep `[String:String]?` | Future enrichment (banners, headers) | App Models | ⏳ |
| First/Last Seen | ✅ | ✅ | ✅ Preserve both | Needed for online state & timeline | App Models | ⏳ |
| Online State Derivation | Computed (5m window) | Explicit `isOnline` flag | ✅ Computed + optional override | Provide `isOnlineOverride` for manual control; else derive | App Models | ⏳ |
| Services Representation | `Set<ServiceInfo>` raw types (`_ssh._tcp`) | `[NetworkService]` normalized enum | ➕ Unified `NetworkService` keeps enum + rawType | Best of both: normalized + raw preservation | App Models | ⏳ |
| Service Display Name Formatting | `ServiceNameFormatter` & pill label compiler | `ServiceMapper` + manual naming | ✅ Merge both: normalization + formatting | Deduplicate precedence logic: discovery > port-derived if more descriptive | App Models Utility | ⏳ |
| Service Deduplication | Limited grouping by display name | `displayServices` logic with port mapping | ✅ Use enhanced netscan logic + improvements | Precedence tie-break by name length | App Models Utility | ⏳ |
| Port Scanning | ❌ | ✅ `PortScanner`, `openPorts` | ✅ Adopt netscan approach | Provide `Port` model + optional scan stub | Future Library (maybe) | ⏳ |
| Port Model Richness | ❌ | ✅ number/description/status | ✅ Preserve + lastSeenOpen + transport | Minimal extension for timeline | App Models | ⏳ |
| Service Pills UI | ✅ (label compiler) | ✅ `ServiceTag` | ✅ Use simplified pills (uppercase text) | Complexity of overflow counting optional later | App UI | ⏳ |
| Device Row UI | ✅ Distinct style | ✅ Provided in ScannerUI | ✅ Rebuild minimal row (avoid package) | Direct inclusion; adapt style tokens | App UI | ⏳ |
| Device Detail UI | ✅ Rich classification emphasis | ✅ Basic + extended ports in netscan | ✅ Unified richer hybrid | Include classification, services, ports | App UI | ⏳ |
| Theme / Design Tokens | `ScannerDesign.Theme` | `Theme` variant in netscan | ✅ Inline `UnifiedTheme` | Packages unnecessary; unify naming | App UI | ⏳ |
| Classification Strategies | ✅ Multi-strategy classifier | Partial (simpler) | ✅ Port core strategies | Implement subset; pluggable expansion | App Models Utility | ⏳ |
| Xiaomi / Vendor Parsing | ✅ Specialized patterns | ❌ | ✅ Include (modular) | Keep in separate strategy file | App Models Utility | ⏳ |
| OUI Lookup | ✅ (Vendor via file) | ✅ `OUILookupService` | ✅ Provide adapter later | Phase 5+; not critical early UI | Future Utility | ⏳ |
| ARP Discovery | ✅ (`ARPService/Worker`) | ✅ separate parsers/services | ✅ Reference netscan parsing + Bonjour scheduling concepts | Unified pipeline stub uses parsed table | Future Utility | ⏳ |
| Ping / Network Reachability | ❌ (light) | ✅ `PingScanner`, `NetworkPingScanner`, `SimplePing` | ✅ Dual strategy: SimplePingKit (iOS) + system exec (macOS) via `Pinger` facade | Unified RTT feed, platform-appropriate implementation | Future Utility | ⏳ |
| Bonjour / mDNS Discovery | ✅ Strong | ✅ Basic `BonjourDiscoverer` | ✅ Port BonjourBrowser concepts | Keep logic pluggable behind protocol | Future Utility | ⏳ |
| SSDP / UPnP | ❌ | ✅ `SSDPDiscoverer` | ✅ Optional later (Phase 5) | Lower priority | Future Utility | ⏳ |
| WS-Discovery | ❌ | ✅ `WSDiscoveryDiscoverer` | ⏳ Decide later | Defer until core flows stable | Future Utility | ⏳ |
| Reverse DNS | ❌ | ✅ `DNSReverseLookupService` | ⏳ Candidate for enrichment | Not core to MVP | Future Utility | ⏳ |
| HTTP Service Fingerprinting | ❌ | ✅ `HTTPInfoGatherer` | ⏳ Later enrichment | Adds banners/fingerprints | Future Utility | ⏳ |
| SSH Fingerprinting | ❌ | ✅ `SSHFingerprintService` | ⏳ Later enrichment | Feeds fingerprints map | Future Utility | ⏳ |
| MAC Vendor Lookup Source File | ✅ `oui.csv` | ✅ `oui.csv` | ✅ Single copy inside UnifiedScanner Resources | Avoid duplication; note attribution | App Resource | ⏳ |
| Persistence (KV / Snapshot) | Partial in-memory | ✅ `DeviceKVStore`, `SnapshotStore` | ✅ Fresh `DeviceSnapshotStore` | Merges concepts; simpler API | App Models | ⏳ |
| Mutation Event Stream | ✅ `DeviceMutation` | Partial (store events) | ✅ Provide `DeviceMutation` unified | Supports incremental UI updates | App Models | ⏳ |
| Logging Infrastructure | ✅ LoggingService | ✅ Debug.swift | ✅ Minimal cohesive logger | Keep structured categories | App Utility | ⏳ |
| Concurrency (actors) | Light | Mixed (actors in some services) | ✅ Actor-based store + scanners | Safety for mutation concurrency | App Models/Utility | ⏳ |
| Backend Architecture Pattern | Distinct browser + classification streams | Monolithic services mix | ✅ Adopt decoupled mutation emission (AsyncStream) | Facilitates testable discovery providers | App Models/Utility | ⏳ |
| Adaptive Navigation (SplitView) | Basic stack | ✅ NavigationSplitView patterns | ✅ Use netscan adaptive approach | Better large-screen UX early | App UI | ⏳ |
| ARP Strategy (iOS Limit Workaround) | Scheduled sysctl polling | Parser + direct read | ✅ Hybrid (Bonjour scheduling + netscan parser) | Resilient to partial data | Future Utility | ⏳ |
| Package Modularization Strategy | N/A (single app) | Partial (separate local modules) | ✅ Local-first (Option A) | Extract packages post Phase 3 criteria | Docs / Plan | ✅ |
| Unit Tests Scope | Classification + mutation + IP heuristics | Broad (scanners, heuristics) | ✅ High-value logic first (model, classification, services) | Defer network integration tests | Tests | ⏳ |
| UI Tests | Basic list/detail | Basic smoke | ⏳ Basic navigation + detail | After Phase 2 | Tests | ⏳ |
| Dark Mode / Theming | Single dark aesthetic | Dark-focused | ✅ Keep dark baseline first | Light theme later OOS | App UI | ⏳ |
| Accessibility Labels | Partial | Partial | ✅ Audit component labels | Add a11y to service pills, ports | App UI | ⏳ |
| Internationalization | ❌ | ❌ | ❌ (Defer) | English only initial | App | ⏳ |
| Analytics / Telemetry | ❌ | ❌ | ❌ (Defer) | Potential future instrumentation | App | ⏳ |
| Configuration Flags | Minimal | Minimal | ✅ Environment-based simple flags | For feature gating later | App Utility | ⏳ |

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
