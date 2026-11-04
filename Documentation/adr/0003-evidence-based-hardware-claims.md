# ADR 0003: Evidence-based hardware claims

- Status: Accepted
- Date: 2026-11-04
- Owner: Dugi Selmanaj

## Context

Compilation and simulated state transitions cannot prove that camera, LiDAR,
tracking, photogrammetry, texture, or mesh output works on physical hardware.

## Decision

Report implementation, automated verification, physical integration, and
acceptance as separate evidence levels. Never fabricate coverage, progress,
quality, sensor readings, or successful output. A hardware capability check is
not proof that live sensor data was received.

## Consequences

- Public documentation includes known failures and NOT TESTED states.
- UI progress is driven by real framework state or verified file output.
- Hardware acceptance reports record versions, counts, performance, and exact
  limitations.
- Product claims advance only after a representative device test passes.
