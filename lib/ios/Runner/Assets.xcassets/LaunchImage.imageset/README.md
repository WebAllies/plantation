# iOS Launch Image Assets

This folder contains the iOS launch image set used by the Flutter iOS target.

## Path In This Repository
This project stores iOS files under `lib/ios` (not `ios` at repo root).

Launch image asset path:
- `lib/ios/Runner/Assets.xcassets/LaunchImage.imageset`

## Files To Replace
- `LaunchImage.png` (1x)
- `LaunchImage@2x.png` (2x)
- `LaunchImage@3x.png` (3x)

Keep filenames unchanged unless you also update `Contents.json`.

## Recommended Workflow
1. Prepare three PNG files with matching aspect ratio and good visual quality.
2. Replace the files in this folder.
3. Open iOS workspace:

```bash
open lib/ios/Runner.xcworkspace
```

4. In Xcode, confirm the LaunchImage set resolves without missing asset warnings.
5. Run on simulator/device and verify launch screen appearance.

## Notes
- iOS launch screens should be static (no animation/code).
- If image looks stretched, re-export with the correct canvas/aspect ratio for all scales.

