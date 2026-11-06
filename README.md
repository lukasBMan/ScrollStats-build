# ScrollStats iPhone build

SwiftUI/SwiftData prototype, iOS 17+. Automatic cross-app video detection is not connected. The portable Swift counting/analytics engine has automated tests; Simulator and iPhone compilation passed in Codemagic with all 32 core tests passing. Runtime validation remains pending.

This source-only snapshot has no private development history, account credentials, user viewing records or developer billing notes.

Download the unsigned IPA from https://github.com/lukasBMan/ScrollStats-build/releases/tag/v0.1.0-preview.1 . It requires local Apple signing before installation. The verified build used the personal Codemagic free M2 allowance with billing disabled. `codemagic.yaml` defines that manual build. Alternatively, run Actions → iPhone build manually. The workflow refuses to run in private repositories and uses a standard macOS runner. It tests the core, builds the simulator/device apps and packages an unsigned IPA. Artifacts expire after one day.

For personal testing from Windows, the unsigned IPA needs signing with your own free Apple account using Sideloadly (https://sideloadly.io/). Free provisioning expires after seven days and requires refreshing. Enter account credentials only in the signing tool on your own PC, never in GitHub. An unsigned IPA cannot be installed directly. This does not provide App Store/TestFlight distribution or restricted entitlements.

App content is local-first. Backup import/export uses the ScrollStats format, not native social-media exports. No backend or screen recording is included. Free building/signing does not grant access to other apps' video transitions.

