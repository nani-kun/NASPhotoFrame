# Contributing Guide

Thank you for helping improve NAS Photo Frame.

## Before You Start

1. Search existing issues to avoid duplicating work.
2. Open an issue to discuss substantial features or architectural changes before implementing them.
3. Do not commit Apple SDKs, Xcode disk images, `.deb` packages, device logs, photos, passwords, private keys, or real `.env` files.
4. Changes to third-party code must identify the upstream version, the reason for the change, and any licensing impact.

## Local Development

Prepare Theos and the iPhoneOS 8.4 SDK according to `docs/BUILDING.en.md`. At minimum, run the following before submitting a change:

```sh
python3 -m py_compile nas-manager/server.py
sh -n nas-manager/entrypoint.sh layout/DEBIAN/postinst layout/DEBIAN/prerm
git diff --check
```

If you have a complete legacy SDK environment, also run:

```sh
make clean package
```

For changes that affect device behavior, describe the tested iPad model, iOS version, jailbreak environment, and recovery plan in the pull request. Root components that control charging, waking, or locking must be tested on a restorable device.

## Commits and Pull Requests

- Keep each commit focused on one clear topic and use an imperative commit message.
- Preserve compatibility with iOS 8 and its Objective-C runtime; do not introduce newer system APIs unintentionally.
- UI changes must account for the iPad 4's 1 GB of memory and `armv7` performance constraints.
- Pull requests must explain the problem, solution, verification, risks, and any necessary rollback steps.
- When changing the version, update `control`, `Resources/Info.plist`, and the release notes together.

## Code Style

- Follow the existing Objective-C style and ARC configuration.
- Perform UIKit updates only on the main thread; keep networking, SQLite, image downloads, and decoding on background queues.
- Prefer writing to a temporary file followed by an atomic replacement so that a power loss does not leave corrupted data.
- Error messages should help users of old devices diagnose network, authentication, or storage problems.
