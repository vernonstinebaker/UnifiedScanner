# UnifiedScanner Implementation Plan

> This plan defines explicit, ordered steps to build the greenfield UnifiedScanner app **without modifying** the legacy reference projects (BonjourScanner, netscan). Update checkboxes as work progresses. Keep commits narrowly scoped per step where feasible.

## Status Legend
- [ ] Not Started
- [~] In Progress
- [x] Complete

---
## Phase 1: Core Model Foundations
0. [ ] Record Architecture Decision: Local-first Option A (in this file and overview) — add note to revisit after Phase 3 completion.
1. [ ] Create `Models/` directory under `UnifiedScanner/UnifiedScanner/`.
2. [ ] Implement `Device.swift` with unified domain model (as described in PROJECT_OVERVIEW.md) — include supporting enums + structs (DeviceFormFactor, ClassificationConfidence, DiscoverySource, NetworkService, Port, DeviceConstants, Device.Classification).
3. [ ] Add `ServiceNormalization.swift` containing `ServiceDeriver` and port→service mapping utilities (copy/adapt logic from netscan `ServiceMapper` & Bonjour service formatting; cite sources in comments).
4. [ ] Add `IPHeuristics.swift` (copy/adapt core best-IP selection logic from Bonjour reference) — self‑contained.
5. [ ] Provide `Device+Mock.swift` with sample mock devices (variety: router, mac, phone, tv, iot) for UI previews & initial list.
6. [ ] Write unit tests (in `UnifiedScannerTests`) validating: identity selection, online status, service dedupe ordering, mock generation.

## Phase 2: UI Integration (List & Detail)
7. [ ] Replace ad‑hoc `DeviceItem` in `ContentView.swift` with unified `Device` model.
8. [ ] Build a lightweight `DeviceRowView` (if not copying) that consumes `Device` (status indicator, primary name, bestDisplayIP/manufacturer snippet, service pill count summary).
9. [ ] Refactor `UnifiedDeviceDetail` to consume a `Device` directly; remove local `ServiceItem` / `PortItem` placeholders.
10. [ ] Implement richer Open Ports section (port number, service name, status) using unified `Port` type.
11. [ ] Implement service pill actions (open http/https, copy ssh) using normalized `NetworkService.ServiceType`.
12. [ ] Add SwiftUI previews referencing `Device.mock` set.

## Phase 3: Classification Pipeline (Static Rules)
13. [ ] Add `ClassificationRules.swift` replicating essential Bonjour strategies (hostname patterns, service signatures, vendor+service, model hints) with normalized outputs.
14. [ ] Implement `DeviceClassifier` that produces `Device.Classification` from a `Device`’s current signals.
15. [ ] Add tests for representative classification scenarios (Apple TV vs HomePod vs generic Mac, Raspberry Pi, Xiaomi patterns, SSH-only host).
16. [ ] Integrate classification invocation during mock generation & UI (display form factor icon + confidence badge).

## Phase 4: Persistence & Snapshotting
17. [ ] Define `DeviceSnapshotStore` (in-memory initially) supporting upsert/merge semantics (merge new signals, preserve firstSeen, update lastSeen, accumulate discovery sources & IPs & services).
18. [ ] Add merge tests (new IP appended; MAC stabilization; service dedupe; discoverySources union).
19. [ ] Implement optional JSON persistence layer (serialize array of devices) for later sessions.
20. [ ] Hook store into ContentView (ObservableObject) feeding devices array.

## Phase 5: Discovery Pipeline Stubs
21a. [ ] Define `Pinger` protocol + `PingResult` struct (host, latencyMs, timestamp, success).
21b. [ ] Implement `SimplePingPinger` (iOS only) wrapping SimplePingKit into AsyncStream.
21c. [ ] Implement `SystemExecPinger` (macOS) invoking `/sbin/ping -c 1 -W <timeout>`; parse output latency.
21d. [ ] Add conditional factory `PlatformPinger.make()` returning appropriate implementation.
21e. [ ] Integrate ping RTT updates into `DeviceSnapshotStore` merge (update rttMillis, lastSeen).

21. [ ] Add protocol `DiscoveryProvider` (async sequence or callback) for future network layers.
22. [ ] Provide stub implementations (`MockMDNSProvider`, `MockARPProvider`, `MockPortScanProvider`) emitting synthetic mutations for demo.
23. [ ] Integrate stubs with snapshot store to showcase live updates.
24. [ ] UI: animate inserts/updates (optional polish).

## Phase 6: Polishing & Docs
25. [ ] Add inline doc comments for each public-facing model type & derived property.
26. [ ] Update `PROJECT_OVERVIEW.md` with any deviations / refinements discovered during implementation.
27. [ ] Add a brief `ARCHITECTURE_NOTES.md` (if needed) summarizing model merge rules & classification precedence.
28. [ ] Final pass test coverage review; ensure core logic (identity, service normalization, classification) has > minimal threshold.
29. [ ] Prepare a consolidated CHANGELOG entry for Phase 1–3 completion.

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

## Immediate Next Action
Implement Phase 1 steps 1–3 (model file, service normalization, heuristics) then add mocks & tests.

---
(End of PLAN.md)
