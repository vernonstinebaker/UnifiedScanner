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
5. [x] Provide `Device+Mock.swift` mock devices (in/for Tests and testing only).
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
Ping via SimplePingKit on iOS, ARP-only sweeps on macOS, and Bonjour browse/resolve now feed the store via the `DeviceMutationBus` with start/stop controls. Tier-0 port scanning runs for both platforms; richer logging controls and extended port tiers remain outstanding.
21a. [x] `PingService` protocol + `PingMeasurement` (iOS only)  
21b. [x] `SimplePingKitService` ICMP implementation.  
21c. [x] `PingOrchestrator` (32 concurrent hosts throttle).  
21d. [x] RTT updates via `SnapshotService.applyPing`.  
22. [x] Define `DiscoveryProvider` protocol (mock provider lives in tests only).  
23. [x] `DiscoveryCoordinator` (auto /24 enumeration, orchestrates ping + ARP).  
24. [x] `ARPService` route dump reader + MAC merge (macOS only).  
25. [x] UDP warmup / broadcast population (macOS) before ARP read.  
26. [x] Logging: `LoggingService` actor with level + category filtering (runtime toggles + persistence).  
27. [x] Port scanning engine (tier 0 ports 22/80/443 implemented; expand tiers + cancellation pending).  
28. [x] Real mDNS provider (NetServiceBrowser) — integrated with toolbar controls and sanitisation.  
29. [x] Mutation bus decoupling (providers emit `DeviceMutation` events via `DeviceMutationBus`).  
30. [ ] Large-scale performance validation (synthetic > /24) — NOT RUN.  
 
## Phase 6: Polishing, Expansion & Docs (macOS + iOS + iPadOS)
31. [x] Inline doc comments for public model types & derived properties.  
32. [x] Update `PROJECT_OVERVIEW.md` with concurrency + discovery corrections.  
33. [ ] (If needed) Add architecture notes section (no new file unless required).  
34. [x] Add tests: ARP MAC merge, RTT update path, multi-source discovery union, classification reasoning ordering.  
35. [ ] CHANGELOG style summary covering Phases 1–5 partial.  
36. [ ] Introduce `ScanLogger` abstraction (category-based, env/flag controlled).  
37. [x] Provider → mutation bus refactor (`DeviceMutation` events).  
38. [ ] Settings runtime toggles (logging, discovery providers, port tiers).  
39. [x] OUI ingestion (`OUILookupService` parses `oui.csv`, provides vendor prefixes).  
40. [x] mDNS provider (service discovery + TXT parsing).  
41. [x] Port scanner tier 0/1 implementation (22,80,443 first).  
42. [ ] Reverse DNS enrichment (optional).  
-33a. [ ] Document rationale for deferring SSDP / WS-Discovery / reverse DNS (low discovery value vs cost).  
-43. [x] HTTP fingerprint population implemented via `HTTPFingerprintService`; SSH host-key capture still pending.  
-44. [ ] Evaluate lightweight HTTP banner capture (if bodies provide additional vendor hints).  
44. [ ] Accessibility pass (labels for row/pills/ports, Dynamic Type audit).  
45. [ ] Theming extraction (UnifiedTheme struct + light mode tokens).  
46. [ ] UI tests (navigation + detail) — add regression test for first-tap device detail sheet (race fixed via snapshot-based `sheet(item:)`).  
47. [x] Comprehensive test coverage including `DeviceMutationBusTests`, `HTTPFingerprintServiceTests`, `AppleModelDatabaseTests`.

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
## September 25-26, 2025: Architecture Refactor Completion

### ✅ 1. Introduce Application Composition Layer (Completed September 25, 2025)
1.1 ✅ Created the `UnifiedScanner/AppEnvironment` module defining protocols for shared services.
1.2 ✅ Implemented adapters wrapping the existing singleton-backed services.
1.3 ✅ Updated `UnifiedScannerApp` to build and inject an `AppEnvironment` via `environmentObject`.
1.4 ✅ Adjusted unit tests to inject dependencies through the new environment where needed.
1.5 ✅ Verified clean build/tests, committed, and pushed to `main`.

### ✅ 2. Decompose SnapshotService (Completed September 25, 2025)
2.1 ✅ Created `DevicePersistenceCoordinator` to handle load/save operations and detect snapshot differences.
2.2 ✅ Introduced `DeviceClassificationCoordinator` plus an injectable `SnapshotClock` to manage classification triggers and timing.
2.3 ✅ Added a `DeviceMutationPublishing` protocol with a `DeviceMutationBusPublisher` adapter so `SnapshotService` no longer depends on the global singleton directly.
2.4 ✅ Refactored `SnapshotService` to consume the new collaborators while preserving actor isolation and existing behaviors.
2.5 ✅ Updated related tests to inject the new publisher/coordinators and rely on the refactored service.
2.6 ✅ Verified clean builds/tests, committed, and pushed on `main`.

### ✅ 3. Replace Global Singletons With Injected Dependencies (Completed September 25, 2025)
3.1 ✅ Updated services (notably `HTTPFingerprintService`) to drop static hooks and rely on injected dependencies.
3.2 ✅ Adjusted `AppEnvironment` and `UnifiedScannerApp` to configure lookup providers and supply concrete implementations explicitly.
3.3 ✅ Audited remaining global references, introducing adapters for mutation publishing and OUI lookup injection.
3.4 ✅ Updated relevant tests to consume the injected publishers/services.
3.5 ✅ Verified builds/tests, committed, and pushed to `main`.

### ✅ 4. Modularize Classification and Display Name Rules (Completed September 25, 2025)
4.1 ✅ Split `ClassificationService` by introducing `ClassificationRulePipeline` with discrete rule types (`FingerprintClassificationRule`, `HostnamePatternClassificationRule`, `VendorHostnameClassificationRule`, `ServiceCombinationClassificationRule`, `PortProfileClassificationRule`, `FallbackClassificationRule`).
4.2 ✅ Added an injectable pipeline registry (`ClassificationRulePipelineRegistry`) so the rule set can be overridden per environment/tests while defaulting to the production stack.
4.3 ✅ Scoped Apple-specific heuristics into the fingerprint rule helpers and expanded the Apple model database entry set (e.g., added `MacBookPro16,1`) instead of hard-coded form-factor strings in the service.
4.4 ✅ Extended `DeviceClassificationTests` with rule-focused regression coverage to validate each strategy independently and to guarantee the authoritative fingerprint short-circuit behaviour.
4.5 ✅ Ran the full `UnifiedScanner` test suite with a clean build prior to committing and pushing.

### ✅ 5. Consolidate UI Status Components and Interaction Logic (Completed September 25, 2025)
5.1 ✅ Replaced duplicated status/progress UI with `StatusDashboardViewModel` + `StatusSectionView`, wiring `ContentView` to consume the shared model.
5.2 ✅ Introduced `DeviceDetailViewModel` to encapsulate port interactions (open/copy), updating `UnifiedDeviceDetail` to route actions through the model.
5.3 ✅ Added dedicated SwiftUI previews for `StatusSectionView` and `UnifiedDeviceDetail`, plus created launch sanity UI coverage using `UNIFIEDSCANNER_DISABLE_NETWORK_DISCOVERY` for deterministic runs.
5.4 ✅ Executed full macOS test suite (unit + UI), committed, and pushed to `main`.

### ✅ 6. Final Integration Pass (Completed September 25, 2025)
6.1 ✅ Audited dependency injection wiring (`AppEnvironment`, rule pipelines, view models) and confirmed no residual singletons remain in production code paths.
6.2 ✅ Updated README/PROJECT_OVERVIEW with the dependency-injection summary, modular classification pipeline description, and roadmap refinements.
6.3 ✅ Executed the full macOS test suite (unit + UI), reviewed the final diff, committed, and pushed to `main`.

### ✅ 7. Actor Interaction Cleanup (Completed September 26, 2025)
7.1 ✅ Adjusted `UnifiedScannerApp` to call `PortScanService` actor APIs via `Task` hops and awaited shutdown on the background task queue to satisfy strict concurrency checks.
7.2 ✅ Marked `SSHHostKeyCollecting` as `Sendable` so host key collectors can safely execute off the main actor while keeping `SSHHostKeyService` actor-isolated updates intact.
7.3 ✅ Rebuilt the project to confirm warnings were eliminated, executed the full macOS test suite, and documented the maintenance outcome prior to commit/push.

---
## Design Rules (Enforced)
- No imports from legacy app modules; copy logic with attribution comments.  
- Keep merge logic deterministic & testable.  
- Prefer value semantics for domain (structs) & actor isolation for stateful services.  
- Avoid premature package modularization (revisit after stable discovery providers).  

## General logic and flow
- On launch the `SnapshotService` restores any persisted devices, forces them offline (`isOnlineOverride = false`), and begins listening to the `DeviceMutationBus` stream.
- `DiscoveryCoordinator` wires providers into the shared mutation bus so all discovery signals are merged asynchronously by the store.
- On macOS the `ARPService` seeds MAC data (and creates devices when none exist) using the route table and UDP warmups; ICMP is skipped entirely.
- On iOS the `PingOrchestrator` backed by `SimplePingKitService` enumerates hosts, emits RTT updates, and marks devices online when successful.
- `BonjourDiscoveryProvider` (browse + resolve) runs on both platforms and contributes service-annotated devices through the mutation bus.
- `PortScanService` probes tier-0 ports (22/80/443) as soon as devices are discovered, emitting mutations that add services/open ports and mark responsive devices online.

### Recently Resolved Issues
- First-tap compact detail sheet race (presented before selection state) resolved by capturing immutable device snapshot and binding via `sheet(item:)`.

## Open Questions (Still Relevant)
- IPv6 prioritization adjustments beyond current heuristic?  
- Historical RTT sample window vs latest-only field?  
- Classification reasons: single concatenated vs structured array (future)?  

- Large-scale performance validation (synthetic > /24) — NOT RUN (still optional).  
- Tiered port scanner expansion (additional tiers, cancellation) & mutation emission tuning.
- HTTP/SSH fingerprint enrichment.  
- Reverse DNS provider.  
- Structured logging runtime controls & feature flag surface.  
- Accessibility & theming improvements.  
- UI test coverage.  
- SnapshotService decomposition (DeviceStoreActor + DeviceMutationBroadcaster + facade).  
- DeviceBuilder / factory patterns for common construction cases.  
- Throwing/Result-based error surfaces for network/persistence services (starting with ARPService).  

### Follow-Up (Planned Cleanup)
- Prune or downgrade verbose debug logging added during sheet race investigation once stability is confirmed.

## Immediate Next Action
Add runtime logging controls (category toggles, persisted minimum level) and surface them via settings so discovery (ping/ARP/port scan) chatter can be tuned without rebuilds.

---
(End of PLAN.md)
