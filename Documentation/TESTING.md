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

Automated tests cover models, repository CRUD, rename, favorites, search,
sorting, local storage boundaries, USDZ rejection, metadata migration,
navigation state, empty/error states, workflow transitions, retry serialization,
cancellation, Object Capture pause/resume and early-finish serialization,
manual/automatic capture gates, preferred-target persistence, overlay
hit-testing, failed-draft image preservation, screen-awake lifecycle, and RGB-D
dataset structure. They do not
prove camera delivery, LiDAR depth, tracking quality, texture fidelity,
reconstruction accuracy, thermal stability, or framework crash freedom.

## Public CI

The `iOS CI` GitHub Actions workflow runs an unsigned simulator build on the
official `xcode-27` runner for pull requests and pushes to `main`. It has
read-only repository permissions and receives no signing credentials.

The required check is named `iOS Simulator Build`. It verifies compilation and
linking only. The complete 47-test suite passes locally on the iOS 27.0 iPhone
18 Pro simulator, but is not yet part of the required hosted check. Promoting
tests into CI should preserve the existing check name or update the repository
ruleset in the same pull request.

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
- Product Experience simulator suite on 2026-11-04: 39/39 passed.
- Full simulator suite after user-controlled capture changes on 2026-11-04:
  47/47 passed.
- Product Experience signed build, install, and launch on Dösti: passed.
- Product Experience manual device interaction: not tested.
- User-controlled Object Capture signed build, install, and launch on Dösti:
  passed; live pause/resume/manual/automatic/finish capture is not tested.
- RGB-D structural tests: 4/4 passed.
- Live normal tracking and live depth: failed/unverified; see Known Issues.
