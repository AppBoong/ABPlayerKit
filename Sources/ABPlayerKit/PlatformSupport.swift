// This package is iOS only, and this file is how a build for anything else
// says so. Without it, `swift build` — which targets the host, i.e. macOS —
// opens with dozens of "no such module 'UIKit'" errors, which reads like the
// package is broken rather than like it was pointed at the wrong platform.
#if !os(iOS)
#error("""
ABPlayerKit supports iOS only — its core reaches UIKit and AVKit directly, so \
there is no other platform it can build for.

`swift build` targets the host platform (macOS) and will fail. Build for iOS:

    xcodebuild -scheme ABPlayerKit-Package -destination 'generic/platform=iOS' build
    xcodebuild -scheme ABPlayerKit-Package -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test

Adding the package to an iOS app in Xcode needs none of this — Xcode resolves \
the iOS platform on its own.
""")
#endif
