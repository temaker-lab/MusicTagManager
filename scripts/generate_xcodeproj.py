#!/usr/bin/env python3
"""MusicTagManager.xcodeproj 생성기.

앱 타깃은 Sources/MusicTagManager 폴더를 그대로 동기화(파일 추가·삭제 자동 반영)하고,
핵심 로직은 같은 폴더의 Swift 패키지(Package.swift)의 MTMCore 라이브러리를 링크한다.
SwiftPM 빌드(scripts/build_app.sh)와 같은 번들 ID·아이콘·fpcalc·권한 설정·ad-hoc 서명을 쓴다.

사용: python3 scripts/generate_xcodeproj.py
단위 테스트(MTMCoreTests)는 패키지 테스트라 `swift test`로 실행한다
(같은 폴더의 로컬 패키지 테스트는 이 프로젝트의 스킴에서 실행되지 않음).
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(ROOT, "MusicTagManager.xcodeproj")


def oid(name: str) -> str:
    """항상 같은 24자리 ID (다시 생성해도 diff가 생기지 않게)"""
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


ids = {k: oid(k) for k in [
    "project", "mainGroup", "productsGroup", "resourcesGroup", "sources", "app", "appProduct",
    "infoPlist", "entitlements", "icon", "fpcalc", "readme", "scriptsGroup", "onboarding",
    "buildIcon", "buildFpcalc", "buildCore", "buildOnboarding",
    "phaseSources", "phaseFrameworks", "phaseResources", "phaseCopyBin",
    "projectConfigs", "projectDebug", "projectRelease", "appConfigs", "appDebug", "appRelease",
    "package", "coreDependency",
]}

common_debug = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_TESTABILITY": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "ONLY_ACTIVE_ARCH": "YES",
    "SDKROOT": "macosx",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}
common_release = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "ENABLE_NS_ASSERTIONS": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "SDKROOT": "macosx",
    "SWIFT_COMPILATION_MODE": "wholemodule",
}
app_settings = {
    "PRODUCT_NAME": "MusicTagManager",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.temzzang.MusicTagManager",
    "MARKETING_VERSION": "1.0.1",
    "CURRENT_PROJECT_VERSION": "2",
    "INFOPLIST_FILE": "Resources/Info.plist",
    "GENERATE_INFOPLIST_FILE": "NO",
    "CODE_SIGN_ENTITLEMENTS": "Resources/MusicTagManager.entitlements",
    # 개발자 계정 없이 ad-hoc 서명 (scripts/build_app.sh와 동일)
    "CODE_SIGN_IDENTITY": '"-"',
    "CODE_SIGN_STYLE": "Manual",
    "DEVELOPMENT_TEAM": '""',
    "ENABLE_HARDENED_RUNTIME": "NO",
    "COMBINE_HIDPI_IMAGES": "YES",
    "LD_RUNPATH_SEARCH_PATHS": '"@executable_path/../Frameworks"',
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
    # 패키지(Swift 5 언어 모드)와 같은 모드로 컴파일
    "SWIFT_VERSION": "5.0",
}


def settings_block(values: dict, indent: str) -> str:
    return "".join(f"{indent}\t{k} = {v};\n" for k, v in sorted(values.items()))


pbxproj = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 77;
	objects = {{

/* Begin PBXBuildFile section */
		{ids['buildIcon']} /* AppIcon.icns in Resources */ = {{isa = PBXBuildFile; fileRef = {ids['icon']} /* AppIcon.icns */; }};
		{ids['buildOnboarding']} /* Onboarding in Resources */ = {{isa = PBXBuildFile; fileRef = {ids['onboarding']} /* Onboarding */; }};
		{ids['buildFpcalc']} /* fpcalc in Copy fpcalc */ = {{isa = PBXBuildFile; fileRef = {ids['fpcalc']} /* fpcalc */; settings = {{ATTRIBUTES = (CodeSignOnCopy, ); }}; }};
		{ids['buildCore']} /* MTMCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids['coreDependency']} /* MTMCore */; }};
/* End PBXBuildFile section */

/* Begin PBXCopyFilesBuildPhase section */
		{ids['phaseCopyBin']} /* Copy fpcalc */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = bin;
			dstSubfolderSpec = 7;
			files = (
				{ids['buildFpcalc']} /* fpcalc in Copy fpcalc */,
			);
			name = "Copy fpcalc";
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
		{ids['appProduct']} /* MusicTagManager.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MusicTagManager.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{ids['infoPlist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{ids['entitlements']} /* MusicTagManager.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = MusicTagManager.entitlements; sourceTree = "<group>"; }};
		{ids['icon']} /* AppIcon.icns */ = {{isa = PBXFileReference; lastKnownFileType = image.icns; path = AppIcon.icns; sourceTree = "<group>"; }};
		{ids['onboarding']} /* Onboarding */ = {{isa = PBXFileReference; lastKnownFileType = folder; path = Onboarding; sourceTree = "<group>"; }};
		{ids['fpcalc']} /* fpcalc */ = {{isa = PBXFileReference; lastKnownFileType = "compiled.mach-o.executable"; path = bin/fpcalc; sourceTree = "<group>"; }};
		{ids['readme']} /* README.md */ = {{isa = PBXFileReference; lastKnownFileType = net.daringfireball.markdown; path = README.md; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		{ids['sources']} /* MusicTagManager */ = {{isa = PBXFileSystemSynchronizedRootGroup; name = "App (Sources/MusicTagManager)"; path = Sources/MusicTagManager; sourceTree = "<group>"; }};
		{ids['scriptsGroup']} /* scripts */ = {{isa = PBXFileSystemSynchronizedRootGroup; path = scripts; sourceTree = "<group>"; }};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		{ids['phaseFrameworks']} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{ids['buildCore']} /* MTMCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{ids['mainGroup']} = {{
			isa = PBXGroup;
			children = (
				{ids['readme']} /* README.md */,
				{ids['sources']} /* MusicTagManager */,
				{ids['resourcesGroup']} /* Resources */,
				{ids['scriptsGroup']} /* scripts */,
				{ids['productsGroup']} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{ids['productsGroup']} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{ids['appProduct']} /* MusicTagManager.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{ids['resourcesGroup']} /* Resources */ = {{
			isa = PBXGroup;
			children = (
				{ids['infoPlist']} /* Info.plist */,
				{ids['entitlements']} /* MusicTagManager.entitlements */,
				{ids['icon']} /* AppIcon.icns */,
				{ids['onboarding']} /* Onboarding */,
				{ids['fpcalc']} /* fpcalc */,
			);
			path = Resources;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{ids['app']} /* MusicTagManager */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {ids['appConfigs']} /* Build configuration list for PBXNativeTarget "MusicTagManager" */;
			buildPhases = (
				{ids['phaseSources']} /* Sources */,
				{ids['phaseFrameworks']} /* Frameworks */,
				{ids['phaseResources']} /* Resources */,
				{ids['phaseCopyBin']} /* Copy fpcalc */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{ids['sources']} /* MusicTagManager */,
			);
			name = MusicTagManager;
			packageProductDependencies = (
				{ids['coreDependency']} /* MTMCore */,
			);
			productName = MusicTagManager;
			productReference = {ids['appProduct']} /* MusicTagManager.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{ids['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2600;
				LastUpgradeCheck = 2600;
			}};
			buildConfigurationList = {ids['projectConfigs']} /* Build configuration list for PBXProject "MusicTagManager" */;
			developmentRegion = ko;
			hasScannedForEncodings = 0;
			knownRegions = (
				ko,
				Base,
			);
			mainGroup = {ids['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{ids['package']} /* XCLocalSwiftPackageReference "." */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {ids['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{ids['app']} /* MusicTagManager */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{ids['phaseResources']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{ids['buildIcon']} /* AppIcon.icns in Resources */,
				{ids['buildOnboarding']} /* Onboarding in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{ids['phaseSources']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{ids['projectDebug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{settings_block(common_debug, chr(9) * 3)}			}};
			name = Debug;
		}};
		{ids['projectRelease']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{settings_block(common_release, chr(9) * 3)}			}};
			name = Release;
		}};
		{ids['appDebug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{settings_block(app_settings, chr(9) * 3)}			}};
			name = Debug;
		}};
		{ids['appRelease']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{settings_block(app_settings, chr(9) * 3)}			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{ids['projectConfigs']} /* Build configuration list for PBXProject "MusicTagManager" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['projectDebug']} /* Debug */,
				{ids['projectRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{ids['appConfigs']} /* Build configuration list for PBXNativeTarget "MusicTagManager" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{ids['appDebug']} /* Debug */,
				{ids['appRelease']} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{ids['package']} /* XCLocalSwiftPackageReference "." */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = .;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{ids['coreDependency']} /* MTMCore */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {ids['package']} /* XCLocalSwiftPackageReference "." */;
			productName = MTMCore;
		}};
/* End XCSwiftPackageProductDependency section */
	}};
	rootObject = {ids['project']} /* Project object */;
}}
"""

scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['app']}" BuildableName = "MusicTagManager.app" BlueprintName = "MusicTagManager" ReferencedContainer = "container:MusicTagManager.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['app']}" BuildableName = "MusicTagManager.app" BlueprintName = "MusicTagManager" ReferencedContainer = "container:MusicTagManager.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{ids['app']}" BuildableName = "MusicTagManager.app" BlueprintName = "MusicTagManager" ReferencedContainer = "container:MusicTagManager.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

os.makedirs(os.path.join(PROJECT, "xcshareddata", "xcschemes"), exist_ok=True)
with open(os.path.join(PROJECT, "project.pbxproj"), "w") as f:
    f.write(pbxproj)
with open(os.path.join(PROJECT, "xcshareddata", "xcschemes", "MusicTag Manager.xcscheme"), "w") as f:
    f.write(scheme)
print(f"생성: {PROJECT}")
