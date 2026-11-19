# ICC Plate Planner

A macOS app for planning immunocytochemistry (ICC) plates: stain sets, antibody volumes, blocking buffer, a panel compatibility check backed by manufacturer data, and Excel export.

## Build

Needs only the Xcode Command Line Tools (macOS 13 or later).

```bash
./build.sh
```

This makes a universal (Apple silicon + Intel) `ICC Plate Planner.app` in this folder.

## Folders

- `Sources/` – the app's Swift source
- `Resources/` – images bundled into the app
- `Tools/check_exports.py` – independent check of workbooks written by `--selftest`
- `Tools/dmg-background.swift` – draws the installer window background for the DMG
- `Tools/release.sh` – builds and zips a release for the updater

## Updates

The app updates itself from this repository's GitHub Releases (**ICC Plate Planner → Check for Updates…**, and automatically once a day). It looks for the newest release, downloads the attached `.zip`, checks it (GitHub's SHA-256, the size, the app's identity, a newer version and an intact code signature), then replaces itself and relaunches. Plates and settings are kept.

`UpdateRepository` in `Info.plist` names the repository (`owner/repo`). The repository must be public so the app can read its releases without a token.

### Publishing an update

```bash
Tools/release.sh 1.4.0
```

This sets the version, builds, and writes `release/ICC-Plate-Planner-1.4.0.zip`. Then on GitHub: **Releases → Draft a new release**, tag `icc-v1.4.0`, write what changed (shown to users in the update window), attach the `.zip`, and publish.

Built `.app`, `.dmg` and `.zip` files are never committed; they go on Releases.

Created by Joey Russell, Department of Regenerative Medicine Research, Kobe City Medical Center General Hospital.
