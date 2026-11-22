// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ScreenshotPro",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ScreenshotPro",
            path: "Sources/ScreenshotPro",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
