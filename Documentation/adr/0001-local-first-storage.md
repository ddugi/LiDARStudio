# ADR 0001: Local-first scan storage

- Status: Accepted
- Date: 2026-11-04
- Owner: Dugi Selmanaj

## Context

Scan photographs, depth, poses, models, and metadata may be sensitive and large.
Sprint requirements also require local persistence and explicit export.

## Decision

Store scan artifacts inside the application container by default. Do not add
automatic upload, analytics, or cloud synchronization. Export occurs only after
an explicit user action through supported system UI.

## Consequences

- Failed reconstruction can preserve originals for recovery.
- App deletion may remove unexported data.
- Backup behavior follows iOS container policy unless individual files are
  explicitly excluded.
- A future cloud feature requires a new privacy review, threat model, dependency
  review, and ADR.
