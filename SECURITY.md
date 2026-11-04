# Security policy

Copyright © 2026 Dugi Selmanaj. All rights reserved.

## Supported versions

LiDARStudio is a pre-release development project. Security fixes are applied to
the latest `main` branch only. No production or App Store release is currently
declared supported.

## Reporting a vulnerability

Do not post sensitive vulnerability details, credentials, certificates, private
photographs, scan datasets, depth data, sysdiagnose archives, or personal data in
a public issue.

Use GitHub's private **Report a vulnerability** flow when it is available for
this repository. If no private reporting channel is displayed, contact the
repository owner through the verified GitHub profile without including exploit
details and request a private channel.

Include only the minimum information needed to reproduce the issue:

- affected commit and app version;
- device/iOS and Xcode versions;
- sanitized steps and expected/actual result;
- sanitized exception, termination reason, and relevant stack frames;
- whether camera, scan, or local user data may be exposed.

## Scope

Reports about path traversal, unsafe file validation, unintended data export,
credential exposure, session lifecycle races, or privacy-sensitive logging are
in scope. General feature requests and known framework failures belong in the
public issue templates when they contain no sensitive data.

The proprietary license remains in force. Security review does not grant a
license to redistribute, commercialize, or create derivative products.
