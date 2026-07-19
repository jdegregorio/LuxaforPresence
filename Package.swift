// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "LuxaforPresence",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LuxaforPresence", targets: ["LuxaforPresence"])
    ],
    targets: [
        .executableTarget(
            name: "LuxaforPresence",
            path: "LuxaforPresence",
            exclude: ["Tests", "Info.plist", "LuxaforPresence.entitlements"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "LuxaforPresence/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "LuxaforPresenceTests",
            dependencies: ["LuxaforPresence"],
            path: "LuxaforPresence/Tests"
        )
    ]
)
