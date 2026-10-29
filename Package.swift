// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MusicTagManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MusicTagManager", targets: ["MusicTagManager"]),
        // Xcode 프로젝트(MusicTagManager.xcodeproj)의 앱 타깃이 링크하는 핵심 모듈
        .library(name: "MTMCore", targets: ["MTMCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        // 자동 업데이트 (Apple 개발자 계정 없이 EdDSA 서명으로 검증). 앱 타깃에만 링크.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "MTMCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            linkerSettings: [.linkedFramework("iTunesLibrary")]
        ),
        .executableTarget(name: "MusicTagManager", dependencies: [
            "MTMCore",
            .product(name: "Sparkle", package: "Sparkle"),
        ]),
        // 실제 보관함 대상 읽기 전용 성능 측정 도구
        .executableTarget(name: "MTMBench", dependencies: ["MTMCore"]),
        // 실제 데이터로 식별 결과 확인 (보관함 읽기 전용, 외부 API 호출)
        .executableTarget(name: "MTMIdentify", dependencies: ["MTMCore"]),
        // ⚠️ 테스트 보관함 전용: 적용·되돌리기·재개를 실제 Music으로 점검 (곡 3,000개 초과 보관함이면 중단)
        .executableTarget(name: "MTMApplyCheck", dependencies: ["MTMCore"]),
        .testTarget(name: "MTMCoreTests", dependencies: ["MTMCore"], resources: [.copy("Fixtures")]),
    ]
)
