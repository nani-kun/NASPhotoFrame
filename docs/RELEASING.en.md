# GitHub Release Checklist

## Before the First Public Release

- Confirm that the name and license choice in `LICENSE` match your intent.
- Confirm the repository visibility, default branch, and GitHub Security settings.
- Enable private vulnerability reporting on GitHub.
- Confirm that no `.env` files, private keys, public keys, real private-network addresses, device logs, or personal photos are committed.
- Confirm that no Apple SDKs, Xcode disk images, Theos toolchains, or `.deb` packages are tracked by Git.
- Review `THIRD_PARTY_NOTICES.en.md` and the third-party license files.

Run the following before pushing:

```sh
git status --short
git ls-files | grep -E '(\.env$|\.dmg$|\.xip$|\.deb$|\.p12$|\.mobileprovision$|id_rsa)'
git grep -n -E '(BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|ADMIN_PASSWORD=.+)'
```

The last two commands should produce no output, except for placeholders in `.env.example`.

## Creating the GitHub Repository

Create an empty repository on GitHub without generating another README, `.gitignore`, or LICENSE file. Then run:

```sh
git remote add origin git@github.com:<your-account>/NASPhotoFrame.git
git push -u origin main
```

You can also use GitHub CLI:

```sh
gh repo create NASPhotoFrame --public --source=. --remote=origin --push
```

## Publishing a Version

1. Update `Version` in `control`.
2. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
3. Run the static checks and `make clean package`.
4. Verify installation, SMB connectivity, caching, screen sleep/wake, and charging policies on a test device.
5. Commit the version changes, create an annotated tag, and push it:

```sh
git tag -a v1.2.5 -m 'NAS Photo Frame 1.2.5'
git push origin main v1.2.5
```

6. Record features, fixes, compatibility, upgrade instructions, and rollback steps in the GitHub release.

Whether to upload a `.deb` is the maintainer's decision. If a binary package is published, ensure that the corresponding source, build instructions, libsmb2 LGPL license, and local modifications are available from the same release. Never include an Apple SDK in the attachment.
