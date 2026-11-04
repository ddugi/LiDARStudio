# Testing and evidence policy

Copyright © 2026 Dugi Selmanaj. All rights reserved.

## Evidence levels

| Level | Meaning |
| --- | --- |
| Build verified | The selected target compiled and linked successfully |
| Automated test verified | A named non-hardware test executed and passed |
| Device integration verified | The workflow executed on a named supported physical device |
| Acceptance verified | Representative input produced a validated, reopenable output |

Lower evidence levels must not be reported as higher ones.

## Automated coverage

Automated tests cover models, local storage boundaries, USDZ rejection,
workflow transitions, retry serialization, cancellation, screen-awake lifecycle,
and RGB-D dataset structure. They do not prove camera delivery, LiDAR depth,
tracking quality, texture fidelity, reconstruction accuracy, thermal stability,
or framework crash freedom.

## Hardware test record

Every physical test report must record:

- source commit and dirty/clean status;
- Xcode and iOS build versions;
- device model and support checks;
- exact configuration and duration;
- actual callback/file counts;
- CPU, memory, and thermal observations when relevant;
- failure logs without private camera or depth payloads;
- PASS, FAIL, or NOT TESTED for each acceptance criterion.

## Privacy rules

Use a non-sensitive test object and environment. Never commit or attach private
photos, RGB-D frames, scan originals, device backups, certificates, provisioning
profiles, or sysdiagnose archives to the public repository. Sanitize logs before
sharing them.

## Current baseline

- Signed physical-device build on 2026-11-04: passed.
- Last complete physical-device automated suite: 27/30 passed.
- RGB-D structural tests: 4/4 passed.
- Live normal tracking and live depth: failed/unverified; see Known Issues.
