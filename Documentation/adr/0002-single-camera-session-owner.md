# ADR 0002: One owner per active camera session

- Status: Accepted
- Date: 2026-11-04
- Owner: Dugi Selmanaj

## Context

Object Capture, ARKit, RoomPlan, and AVFoundation can compete for camera and
sensor resources. Historical failures require deterministic lifecycle handling.

## Decision

Every camera workflow has one explicit coordinator that owns at most one active
framework session. Start operations are guarded, callbacks are scoped to the
current session, and cleanup is idempotent across stop, cancel, failure,
completion, navigation dismissal, and backgrounding. Competing sessions are not
allowed.

## Consequences

- Feature views must disable conflicting start actions.
- A framework session cannot be recreated in a retry loop.
- New camera engines require lifecycle and stale-callback tests.
- If simultaneous presentation becomes possible, introduce a process-wide
  capture arbiter before enabling it.
