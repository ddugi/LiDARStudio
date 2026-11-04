# Architecture decision records

Architecture decision records (ADRs) capture durable engineering constraints.
They supplement the current-state architecture and do not replace source tests
or physical-device evidence.

| ADR | Status | Decision |
| --- | --- | --- |
| [0001](0001-local-first-storage.md) | Accepted | Keep scans local by default |
| [0002](0002-single-camera-session-owner.md) | Accepted | One explicit owner per active camera session |
| [0003](0003-evidence-based-hardware-claims.md) | Accepted | Separate implementation from physical verification |

New ADRs should state context, decision, consequences, and superseded records.
