# Feature & Capability Comparison: BonjourScanner vs netscan vs UnifiedScanner

> Purpose: Authoritative reference matrix mapping legacy capabilities to UnifiedScanner design decisions. Legacy projects are **read-only**. This document reflects **current, actually implemented** state plus clearly scoped future work.

Legend: ✅ = Present, ❌ = Absent, ⏳ = Planned / Not Yet Implemented, ☑️ = Partially Implemented

| Feature / Capability | BonjourScanner | netscan | UnifiedScanner Decision | Implementation Notes / Rationale | Location (Lib vs App) | Status |
|----------------------|----------------|---------|-------------------------|----------------------------------|-----------------------|--------|
| Core Device Model (multi-IP) | ✅ `Device.ips:Set` | ❌ (single ip) | ➕ Unified uses `Set<String>` + `primaryIP` | Implemented Phase 1 | App Models | ✅ |
| Primary IP Heuristic | ✅ Bonjour logic | Trivial (single ip) | ✅ Adapt Bonjour heuristic | `IPHeuristics.bestDisplayIP` | App Models | ✅ |
| Multi-source Discovery Tracking | Limited (single source) | ✅ single enum | ➕ `Set<DiscoverySource>` | Merge logic working | App Models | ✅ |
| RTT / Latency Metric | ❌ | ✅ `rttMillis` | ✅ Optional Double | Updated on successful ping | App Models | ✅ |
| MAC Address Capture | ✅ | ✅ | ✅ Unified `macAddress` | ARP (macOS) only; iOS path pending | App Models | ☑️ |
| Vendor / OUI Field | ✅ `vendor` | ✅ `manufacturer` | ✅ Single `vendor` + alias mapping | Field present; lookup ingestion deferred | App Models | ✅ |
| Device Type Enum | String + confidence | Strong enum | ➕ `DeviceFormFactor` + `rawType` | Implemented | App Models | ✅ |
| Device Type Confidence | ✅ | Approx numeric | ✅ `ClassificationConfidence` | Implemented | App Models | ✅ |
| Classification Reason | ✅ stored | ❌ | ✅ `Classification.reason` | Implemented | App Models | ✅ |
| Fingerprints Map | ❌ | ✅ | ✅ `[String:String]?` | Field present; population deferred | App Models | ☑️ |
| First/Last Seen | ✅ | ✅ | ✅ Preserve both | Implemented | App Models | ✅ |
| Online State Derivation | Computed heuristic | Explicit flag | ✅ Heuristic + override | `recentlySeen` window | App Models | ✅ |
| Services Representation | Set raw types | Normalized enum | ➕ Enum + rawType | Implemented | App Models | ✅ |
| Service Display Name Formatting | Label compiler | Mapper | ✅ Merge approaches | `ServiceDeriver` utility | App Models Utility | ✅ |
| Service Deduplication | Limited | Port/service merge | ✅ Enhanced dedupe | Implemented (type+port) | App Models Utility | ✅ |
| Port Scanning Engine | ❌ | ✅ Engine + model | Rebuild later | Model fields only; no scanner yet | Future Utility | ⏳ |
| Port Model Richness | ❌ | ✅ | ✅ Keep richness | Struct present | App Models | ✅ |
| Service Pills UI | ✅ | ✅ | ✅ Simplified | Implemented | App UI | ✅ |
| Device Row UI | ✅ | ✅ | ✅ Local rebuild | Implemented Phase 2 | App UI | ✅ |
| Device Detail UI | ✅ Rich | Basic + ports | ✅ Hybrid detail | Implemented Phase 2 | App UI | ✅ |
| Theme / Design Tokens | Package theme | Simple theme | ✅ Inline start | Basic styling only | App UI | ☑️ |
| Classification Strategies | Multi-rule | Simpler | ✅ Port + hostname + vendor + service | Core & extended patterns in place | App Models Utility | ✅ |
| Xiaomi / Vendor Parsing | ✅ | ❌ | ✅ Include selective rules | Implemented | App Models Utility | ✅ |
| OUI Lookup (data ingest) | ✅ File-based | ✅ File-based | ✅ Single `oui.csv` asset | Loader not wired yet | Future Utility | ⏳ |
| ARP Discovery | ✅ | ✅ | ✅ Route dump + MAC capture | macOS only (iOS returns empty) + UDP warmup | App Utility | ☑️ |
| Ping / Reachability | Light | ✅ SimplePing + orchestrator | ➕ Orchestrated concurrent ICMP | SimplePingKitService + PingOrchestrator + /24 auto enumeration | App Utility | ✅ |
| Bonjour / mDNS Discovery | Strong | Basic | Re-implement later | Only mock provider exists | Future Utility | ⏳ |
| SSDP / UPnP | ❌ | ✅ | Evaluate later | Deferred | Future Utility | ⏳ |
| WS-Discovery | ❌ | ✅ | Evaluate later | Deferred | Future Utility | ⏳ |
| Reverse DNS | ❌ | ✅ | Plan later | Deferred | Future Utility | ⏳ |
| HTTP Service Fingerprinting | ❌ | ✅ | Plan later | Deferred | Future Utility | ⏳ |
| SSH Fingerprinting | ❌ | ✅ | Plan later | Deferred | Future Utility | ⏳ |
| MAC Vendor Source File | ✅ `oui.csv` | ✅ `oui.csv` | ✅ Single copy bundled | Not yet parsed | App Resource | ⏳ |
| Persistence (Snapshot Store) | Partial | ✅ KV store | ✅ Unified snapshot store | iCloud KVS + UserDefaults | App Models | ✅ |
| Mutation Event Stream | ✅ Events | Partial | ✅ Async mutation stream | `SnapshotService.mutationStream` implemented | App Models | ✅ |
| Logging Infrastructure | LoggingService | Debug prints | Minimal cohesive logger | Still ad-hoc `print` + env flags | App Utility | ⏳ |
| Concurrency (actors) | Light | Mixed | ✅ Actor store + orchestrators | Store + PingOrchestrator + ARP route dump bridging | App Models/Utility | ✅ |
| Provider Architecture (decoupled) | Browser + streams | Mixed | Move to mutation bus | Providers still upsert directly; bus planned | App Models/Utility | ⏳ |
| Adaptive Navigation (SplitView) | Basic | ✅ | ✅ Adopt netscan pattern | Implemented | App UI | ✅ |
| ARP Strategy (iOS Workaround) | Scheduled polling | Direct read | Hybrid plan | iOS portion not yet implemented | Future Utility | ⏳ |
| Package Modularization Strategy | N/A | Partial | ✅ Local-first Option A | Completed (collapsed external packages) | Docs / Plan | ✅ |
| Unit Tests Scope | Classification + some | Broad | ✅ High-value logic | Core tests present | Tests | ✅ |
| UI Tests | Basic | Smoke | Basic later | Deferred | Tests | ⏳ |
| Dark Mode / Theming | Dark only | Dark oriented | Keep dark baseline | Light / token extraction deferred | App UI | ⏳ |
| Accessibility Labels | Partial | Partial | Audit later | Pending audit | App UI | ⏳ |
| Internationalization | ❌ | ❌ | Defer | English only | App | ❌ |
| Analytics / Telemetry | ❌ | ❌ | Defer | Not planned early | App | ❌ |
| Configuration Flags | Minimal | Minimal | Simple env flags | Needs FeatureFlag enum | App Utility | ⏳ |

### Partial (☑️) Clarifications
- MAC Address Capture: Implemented via ARP on macOS; iOS path currently returns empty result set (no alternative implemented yet).
- Fingerprints Map: Structure exists; no active population layer (HTTP / SSH) yet.
- Theme / Design Tokens: Inline styling only; no extracted token system or light mode.
- ARP Discovery: Includes route dump + UDP warmup on macOS, absent on iOS.

## Deferred / Backlog Items (Updated)
- Port scanning engine reimplementation (tiered design, mutation emission)
- OUI ingestion + live vendor lookup service
- Real mDNS / Bonjour provider (NetServiceBrowser) + service/TXT parsing
- SSDP / WS-Discovery evaluation & possible providers
- Reverse DNS enrichment
- HTTP banner + SSH host key fingerprint extraction (populate `fingerprints`)
- Unified logging abstraction (`ScanLogger` facade) replacing ad-hoc prints
- Provider → mutation bus refactor (providers emit `DeviceMutation` events instead of direct store upserts)
- Accessibility audit (Dynamic Type, VoiceOver labeling, rotor grouping)
- Theming abstraction (UnifiedTheme + light / high-contrast variants)
- UI tests (navigation + detail flows)
- Configuration: FeatureFlag enum & runtime toggles (logging, discovery providers, port tiers)

## Feature Adoption Notes
- Preference always for richer semantics when overlapping (e.g., netscan port model + Bonjour multi-IP, merged normalization logic).
- Some netscan utilities (port scanner, HTTP/SSH fingerprinting) are intentionally **not** copied yet; they will be slimmed and reauthored if still needed.
- Classification constrained to high-signal heuristics to minimize early complexity while retaining strong identification.

## Libraries vs In-App Modules
Local-first approach keeps prior package concepts (design/UI) collapsed into local Swift files for rapid iteration. Extraction criteria will be revisited only after multiple independent targets require reuse.

## Complement to PLAN.md
- `PLAN.md` owns ordered execution tasks.
- This matrix is a progress & decision ledger; update statuses when implementations land.

## Current Accuracy Audit vs Previous Version
Removed or corrected prior overstatements:
- (REMOVED) Claims of multi-port TCP probing & UDP fallback layer — no port scanning engine implemented yet.
- (REMOVED) Network framework ping replacement — current implementation uses SimplePingKit only.
- (REMOVED) Unverified performance claim of detecting "1400+ devices".
- (UPDATED) Mutation event stream now marked ✅ (implemented in store) instead of planned.
- (UPDATED) ARP feature marked partial (macOS-only) rather than fully complete.

## Immediate Adjustments Recommended for PLAN.md
- Mark Phase 5 as "Partial" (ping + ARP implemented; port scan, mDNS, logger pending).
- Add explicit task for provider → mutation bus refactor.
- Remove unverified large-scale performance test claim or move to future validation task.

## Concurrency Improvement TODOs (Still Outstanding)
- Replace ad-hoc `Task {}` launches in `PingOrchestrator` with structured task groups & cancellation.
- DiscoveryCoordinator shutdown / cancellation API.
- Provider emission refactor (mutation bus) for better decoupling & testability.

## Accessibility TODOs
- DeviceRowView: Compose VoiceOver label (classification, vendor/hostname, IP, service count, RTT if available).
- Service pills: Add explicit accessibility label (service name + "service").
- Port list: Provide descriptive labels (e.g., "Port 22 SSH open").
- Dynamic Type stress testing (XXXL) & macOS pointer Large Content Viewer.

## Testing Gaps TODOs
- Snapshot merge tests for multi-source discovery (ping + arp) rtt + MAC union.
- RTT update path (ensure lastSeen updates only on success).
- Classification reasoning ordering & reclassification trigger.
- (Future) integration test with synthetic ping + mock mDNS + arp events.

*End of FEATURE_COMPARISON.md*
