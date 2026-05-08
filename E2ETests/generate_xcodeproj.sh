#!/bin/bash
# VM 内で実行: XCUITest 用 Xcode プロジェクトを生成する
# 前提: Xcode がインストール済みの環境（TartVM の Xcode イメージ）
#
# Usage: cd ~/Desktop/E2ETests && ./generate_xcodeproj.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_NAME="kobaamdE2E"
TARGET_NAME="kobaamdE2ETests"
BUNDLE_ID="com.kobaamd.e2e-tests"

echo "🔧 Generating $PROJECT_NAME.xcodeproj..."

# Ruby スクリプトで xcodeproj を生成（Xcode 付属の Ruby に xcodeproj gem がない場合のフォールバック）
# 最小限の pbxproj を直接生成する

PROJECT_DIR="$SCRIPT_DIR/$PROJECT_NAME.xcodeproj"
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/xcshareddata/xcschemes"

# --- UUIDs (固定値で再現性を確保) ---
ROOT_OBJ="E2E000000000000000000001"
MAIN_GROUP="E2E000000000000000000002"
SOURCES_GROUP="E2E000000000000000000003"
PRODUCTS_GROUP="E2E000000000000000000004"
NATIVE_TARGET="E2E000000000000000000010"
BUILD_CONFIG_LIST_P="E2E000000000000000000020"
BUILD_CONFIG_LIST_T="E2E000000000000000000021"
BUILD_CONFIG_DEBUG_P="E2E000000000000000000030"
BUILD_CONFIG_RELEASE_P="E2E000000000000000000031"
BUILD_CONFIG_DEBUG_T="E2E000000000000000000032"
BUILD_CONFIG_RELEASE_T="E2E000000000000000000033"
SOURCES_PHASE="E2E000000000000000000040"
FRAMEWORKS_PHASE="E2E000000000000000000041"
PRODUCT_REF="E2E000000000000000000050"

# Collect Swift files
FILE_REFS=""
BUILD_FILES=""
FILE_COUNTER=100
for swift_file in kobaamdE2ETests/*.swift; do
    FNAME=$(basename "$swift_file")
    FILE_REF="E2E0000000000000000${FILE_COUNTER}0"
    BUILD_FILE="E2E0000000000000000${FILE_COUNTER}1"

    FILE_REFS="${FILE_REFS}
		${FILE_REF} /* ${FNAME} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"${FNAME}\"; sourceTree = \"<group>\"; };
"
    BUILD_FILES="${BUILD_FILES}
		${BUILD_FILE} /* ${FNAME} in Sources */ = {isa = PBXBuildFile; fileRef = ${FILE_REF} /* ${FNAME} */; };
"
    FILE_COUNTER=$((FILE_COUNTER + 1))
done

# Source group children
CHILDREN=""
FILE_COUNTER=100
for swift_file in kobaamdE2ETests/*.swift; do
    FNAME=$(basename "$swift_file")
    FILE_REF="E2E0000000000000000${FILE_COUNTER}0"
    CHILDREN="${CHILDREN}
				${FILE_REF} /* ${FNAME} */,"
    FILE_COUNTER=$((FILE_COUNTER + 1))
done

# Build file refs for sources phase
SOURCE_FILES=""
FILE_COUNTER=100
for swift_file in kobaamdE2ETests/*.swift; do
    FNAME=$(basename "$swift_file")
    BUILD_FILE="E2E0000000000000000${FILE_COUNTER}1"
    SOURCE_FILES="${SOURCE_FILES}
				${BUILD_FILE} /* ${FNAME} in Sources */,"
    FILE_COUNTER=$((FILE_COUNTER + 1))
done

cat > "$PROJECT_DIR/project.pbxproj" << PBXEOF
// !\$*UTF8*\$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
${BUILD_FILES}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		${PRODUCT_REF} /* ${TARGET_NAME}.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = "${TARGET_NAME}.xctest"; sourceTree = BUILT_PRODUCTS_DIR; };
${FILE_REFS}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		${FRAMEWORKS_PHASE} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		${MAIN_GROUP} = {
			isa = PBXGroup;
			children = (
				${SOURCES_GROUP} /* ${TARGET_NAME} */,
				${PRODUCTS_GROUP} /* Products */,
			);
			sourceTree = "<group>";
		};
		${SOURCES_GROUP} /* ${TARGET_NAME} */ = {
			isa = PBXGroup;
			children = (${CHILDREN}
			);
			path = "${TARGET_NAME}";
			sourceTree = "<group>";
		};
		${PRODUCTS_GROUP} /* Products */ = {
			isa = PBXGroup;
			children = (
				${PRODUCT_REF} /* ${TARGET_NAME}.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		${NATIVE_TARGET} /* ${TARGET_NAME} */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${BUILD_CONFIG_LIST_T} /* Build configuration list for PBXNativeTarget "${TARGET_NAME}" */;
			buildPhases = (
				${SOURCES_PHASE} /* Sources */,
				${FRAMEWORKS_PHASE} /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = "${TARGET_NAME}";
			productName = "${TARGET_NAME}";
			productReference = ${PRODUCT_REF} /* ${TARGET_NAME}.xctest */;
			productType = "com.apple.product-type.bundle.ui-testing";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		${ROOT_OBJ} /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
			};
			buildConfigurationList = ${BUILD_CONFIG_LIST_P} /* Build configuration list for PBXProject "${PROJECT_NAME}" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = ja;
			hasScannedForEncodings = 0;
			knownRegions = (
				ja,
				Base,
			);
			mainGroup = ${MAIN_GROUP};
			productRefGroup = ${PRODUCTS_GROUP} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				${NATIVE_TARGET} /* ${TARGET_NAME} */,
			);
		};
/* End PBXProject section */

/* Begin PBXSourcesBuildPhase section */
		${SOURCES_PHASE} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (${SOURCE_FILES}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		${BUILD_CONFIG_DEBUG_P} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				SDKROOT = macosx;
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		${BUILD_CONFIG_RELEASE_P} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				SDKROOT = macosx;
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
		${BUILD_CONFIG_DEBUG_T} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				INFOPLIST_FILE = "";
				PRODUCT_BUNDLE_IDENTIFIER = "${BUNDLE_ID}";
				PRODUCT_NAME = "\$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TEST_TARGET_NAME = "";
			};
			name = Debug;
		};
		${BUILD_CONFIG_RELEASE_T} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				INFOPLIST_FILE = "";
				PRODUCT_BUNDLE_IDENTIFIER = "${BUNDLE_ID}";
				PRODUCT_NAME = "\$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TEST_TARGET_NAME = "";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		${BUILD_CONFIG_LIST_P} /* Build configuration list for PBXProject "${PROJECT_NAME}" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${BUILD_CONFIG_DEBUG_P} /* Debug */,
				${BUILD_CONFIG_RELEASE_P} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
		${BUILD_CONFIG_LIST_T} /* Build configuration list for PBXNativeTarget "${TARGET_NAME}" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${BUILD_CONFIG_DEBUG_T} /* Debug */,
				${BUILD_CONFIG_RELEASE_T} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
/* End XCConfigurationList section */

	};
	rootObject = ${ROOT_OBJ} /* Project object */;
}
PBXEOF

# --- Scheme ---
cat > "$PROJECT_DIR/xcshareddata/xcschemes/${TARGET_NAME}.xcscheme" << 'SCHEME_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "E2E000000000000000000010"
               BuildableName = "kobaamdE2ETests.xctest"
               BlueprintName = "kobaamdE2ETests"
               ReferencedContainer = "container:kobaamdE2E.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
</Scheme>
SCHEME_EOF

echo "✅ $PROJECT_NAME.xcodeproj generated successfully"
echo "   Run: xcodebuild test -project $PROJECT_NAME.xcodeproj -scheme $TARGET_NAME -destination 'platform=macOS'"
