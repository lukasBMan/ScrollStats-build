# ScrollStats iPhone build

SwiftUI/SwiftData prototype, iOS 17+. Automatic cross-app video detection is not connected. The portable Swift counting/analytics engine has automated tests; iPhone compilation and runtime validation are pending.

This source-only snapshot has no private development history, account credentials, user viewing records or developer billing notes.

Run Actions → iPhone build manually. The workflow refuses to run in private repositories and uses a standard macOS runner. It tests the core, builds the simulator/device apps and packages an unsigned IPA. Artifacts expire after one day.

For personal testing from Windows, the unsigned IPA needs signing with your own free Apple account using Sideloadly (https://sideloadly.io/). Free provisioning expires after seven days and requires refreshing. Enter account credentials only in the signing tool on your own PC, never in GitHub. An unsigned IPA cannot be installed directly. This does not provide App Store/TestFlight distribution or restricted entitlements.

App content is local-first. Backup import/export uses the ScrollStats format, not native social-media exports. No backend or screen recording is included. Free building/signing does not grant access to other apps' video transitions.
