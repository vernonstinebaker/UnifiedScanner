# UnifiedScanner Implementation Plan

> Ordered steps to build the UnifiedScanner app **without modifying** legacy reference projects. This revision corrects earlier overstatements (e.g. full discovery pipeline completion) and aligns with current source.

## Status Legend
- [ ] Not Started
- [~] In Progress / Partial
- [x] Complete

---
## Phase 1: Core Model Foundations
0. [x] Record Architecture Decision: Local-first Option A (revisit after Phase 3)  
1. [x] Create `Models/` directory.  
2. [x] Implement `Device.swift` unified model & supporting enums / structs.  
3. [x] Add `ServiceDeriver` & port/service normalization utilities.  
4. [x] Add `IPHeuristics` best display IP logic.  
5. [x] Provide `Device+Mock.swift` mock devices.  
6. [x] Unit tests: identity selection, online status, service dedupe ordering, mock generation.  

## Phase 2: UI Integration (List & Detail)
7. [x] Replace ad‑hoc types with unified `Device`.  
8. [x] `DeviceRowView` (status indicators, summary).  
9. [x] `UnifiedDeviceDetail` consumes `Device`.  
10. [x] Open Ports section using unified `Port`.  
11. [x] Service pill actions (open/copy).  
12. [x] SwiftUI previews use `Device.mock`.  

## Phase 3: Classification Pipeline (Static Rules)
13. [x] `ClassificationService` (hostname, services, vendor, model hints).  
14. [x] Classification integration during upsert + mock generation.  
15. [x] Classification tests (Apple TV vs Mac, printer, router, SSH-only).  
16. [x] UI shows form factor icon + confidence badge.  

## Phase 4: Persistence & Snapshotting
17. [x] `SnapshotService` (merge semantics, actor-backed; formerly DeviceSnapshotStore).  
18. [x] Merge tests (IPs, MAC, services, discoverySources, ports precedence).  
19. [x] Persistence via iCloud KVS + UserDefaults mirror.  
20. [x] Integrate store with ContentView observable state.  

## Phase 5: Discovery Pipeline (PARTIAL)
Earlier version marked this fully complete; correction: Only Ping + ARP (macOS) implemented. Port scanning, real mDNS, structured logging not yet present.
21a. [x] `PingService` protocol + `PingMeasurement`.  
21b. [x] `SimplePingKitService` ICMP implementation.  
21c. [x] `PingOrchestrator` (32 concurrent hosts throttle).  
21d. [ ] Network framework or exec-based alternate PingService (currently none; SimplePingKit only).  
21e. [x] RTT updates via `SnapshotService.applyPing`.  
22. [x] Define `DiscoveryProvider` protocol + mock mDNS provider.  
23. [x] `DiscoveryCoordinator` (auto /24 enumeration, orchestrates ping + ARP).  
24. [x] `ARPService` route dump reader + MAC merge (macOS only).  
25. [x] UDP warmup / broadcast population (macOS) before ARP read.  
26. [~] Logging: env-var gated prints (`PING_INFO_LOG`, `ARP_INFO_LOG`) — structured logger pending.  
27. [ ] Port scanning engine (tiered) — NOT IMPLEMENTED.  
28. [ ] Real mDNS provider (NetServiceBrowser) — NOT IMPLEMENTED.  
29. [ ] Mutation bus decoupling (providers emit events, not direct store upserts).  
30. [ ] Large-scale performance validation (synthetic > /24) — NOT RUN.  

## Phase 6: Polishing, Expansion & Docs (macOS + iOS + iPadOS)
31. [ ] Inline doc comments for public model types & derived properties.  
32. [ ] Update `PROJECT_OVERVIEW.md` with concurrency + discovery corrections.  
33. [ ] (If needed) Add architecture notes section (no new file unless required).  
34. [ ] Add tests: ARP MAC merge, RTT update path, multi-source discovery union, classification reasoning ordering.  
35. [ ] CHANGELOG style summary covering Phases 1–5 partial.  
36. [ ] Introduce `ScanLogger` abstraction (category-based, env/flag controlled).  
37. [ ] Provider → mutation bus refactor (`DeviceMutation` events).  
38. [ ] FeatureFlag enum & runtime toggles (logging, discovery providers, port tiers).  
39. [ ] OUI ingestion (parse `oui.csv`, build prefix map).  
40. [ ] mDNS provider (service discovery + TXT parsing).  
41. [ ] Port scanner tier 0/1 implementation (22,80,443 first).  
42. [ ] Reverse DNS enrichment (optional).  
43. [ ] HTTP / SSH fingerprint population (fill `fingerprints`).  
44. [ ] Accessibility pass (labels for row/pills/ports, Dynamic Type audit).  
45. [ ] Theming extraction (UnifiedTheme struct + light mode tokens).  
46. [ ] UI tests (navigation + detail).  

## Phase 7: Cross-Platform & Enrichment (Planned)
47. [ ] Extended port scanner tiers (configurable list + cancellation).  
48. [ ] SSDP provider evaluation / implementation.  
49. [ ] WS-Discovery provider evaluation / implementation.  
50. [ ] Mutation backpressure strategy (bounded buffer drop policy).  
51. [ ] Offline pruning (service / port aging policy).  
52. [ ] Internationalization prep (extract strings).  
53. [ ] Advanced accessibility (rotor grouping, VoiceOver snapshot tests).  
54. [ ] Light/high-contrast theme refinement & token documentation.  
55. [ ] Performance benchmarks (1000-host synthetic run, latency statistics).  

---
## Design Rules (Enforced)
- No imports from legacy app modules; copy logic with attribution comments.  
- Keep merge logic deterministic & testable.  
- Prefer value semantics for domain (structs) & actor isolation for stateful services.  
- Avoid premature package modularization (revisit after stable discovery providers).  

## Open Questions (Still Relevant)
- IPv6 prioritization adjustments beyond current heuristic?  
- Historical RTT sample window vs latest-only field?  
- Classification reasons: single concatenated vs structured array (future)?  

## Deferred Backlog (Refined)
- Tiered port scanner & mutation emission.  
- Real mDNS provider.  
- OUI ingestion + vendor lookup caching.  
- HTTP/SSH fingerprint enrichment.  
- Reverse DNS provider.  
- Provider → mutation bus & structured logger.  
- Accessibility & theming improvements.  
- UI test coverage.  

## Immediate Next Action
Implement Phase 6 logging + provider mutation bus before adding new discovery types (ensures consistent event pipeline).

---
(End of PLAN.md)
