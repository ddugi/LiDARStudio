# LiDARStudio privacy and local data

Copyright © 2026 Dugi Selmanaj. All rights reserved.

This document describes the current source implementation. It is not an App
Store privacy label, legal privacy notice for a released service, or a promise
about future versions.

## Data accessed

Depending on the selected workflow and device support, LiDARStudio may access:

- camera images;
- ARKit camera pose, intrinsics, timestamps, and tracking state;
- LiDAR-derived scene depth and confidence maps;
- ARKit mesh anchors;
- Object Capture photographs and framework checkpoints;
- reconstructed local USDZ models;
- scan names and local metadata.

LiDAR scene depth is processed Apple API output, not raw time-of-flight returns.

## Local-first storage

The current application contains no app-managed analytics, advertising SDK,
cloud database, or automatic upload implementation. Object scans and metadata
are stored in the app's local Documents container. RGB-D proof-of-concept data
is stored separately under Application Support.

Files leave the app only when the user explicitly invokes a system share action
or otherwise accesses the app container using supported device tooling. The
chosen share destination may have its own privacy policy and network behavior.

## Retention and deletion

Capture drafts and original photographs are intentionally preserved so a failed
reconstruction does not silently destroy user work. App restarts preserve local
metadata and completed artifacts.

My Scans removes data only after the user confirms the destructive action. The
selected scan's validated model, preview, capture workspace, original
photographs, checkpoints, and metadata are then removed from the app container.
Independent RGB-D diagnostic datasets are not scan-library entries and are not
removed by deleting a scan. Deleting the application through iOS removes the
entire app container, including independent diagnostic data.

## Logs

Lifecycle diagnostics use `OSLog` and are designed to contain state names,
counts, framework error domains/codes, and timing—not image pixels, depth maps,
or captured datasets. Logs and sysdiagnose archives may still contain device or
system information and must be reviewed before external sharing.

## Repository privacy

The public Git repository must not contain:

- captured photos or private preview images;
- USDZ models or RGB-D datasets;
- raw depth or mesh exports;
- Apple certificates, private keys, or provisioning profiles;
- developer user state, device backups, or sysdiagnose archives;
- credentials, tokens, or personal contact information.

`.gitignore` provides a safety boundary but does not replace review before every
commit and public release.
