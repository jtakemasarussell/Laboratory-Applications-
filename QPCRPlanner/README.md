# qPCR Planner

A macOS app for qPCR runs on the analytik jena qTOWER.

- **Plan:** genes, samples, replicates and plate layouts. Exports a protocol workbook and a melt-curve sheet ready for screenshots, as a folder or as single files.
- **Results:** imports qTOWER result files and calculates ΔCt / ΔΔCt. Makes graphs, writes Prism-ready data, and keeps melt-curve sheets with their pictures.

## Build

Needs only the Xcode Command Line Tools (macOS 13 or later).

```bash
./build.sh
```

This makes a universal (Apple silicon + Intel) `qPCR Planner.app` in this folder.

## Folders

- `Sources/` – the app's Swift source
- `Resources/` – the department logo and the bench page served to an iPad
- `Tools/dmg-background.swift` – draws the installer window background for the DMG
- `Tools/release.sh` – builds and zips a release for the updater

## Updates

The app updates itself from this repository's GitHub Releases tagged `qpcr-v…` (**qPCR Planner → Check for Updates…**, and automatically once a day). It downloads the release's `.zip` and checks it before installing: GitHub's SHA-256, the size, the app's identity, a newer version and an intact code signature. Then it replaces itself and relaunches. Plans, results and settings are kept.

### Publishing an update

```bash
Tools/release.sh 1.8.0
```

This sets the version, builds, and writes `release/qPCR-Planner-1.8.0.zip`. Then on GitHub: **Releases → Draft a new release**, tag `qpcr-v1.8.0`, write what changed (shown to users in the update window), attach the `.zip`, and publish.

Created by Joey Russell, Department of Regenerative Medicine Research, Kobe City Medical Center General Hospital.
