#!/bin/bash
# Unified script to run UI tests locally
# Usage: 
#   ./run-ui-tests.sh                    # Full mode (auto-detect simulator, diagnostics)
#   ./run-ui-tests.sh --quick            # Quick mode (use default simulator)
#   ./run-ui-tests.sh "platform=iOS Simulator,name=iPhone 16,OS=18.5"  # Custom destination

set -euo pipefail

# Parse arguments
QUICK_MODE=false
MANUAL_DESTINATION=""

for arg in "$@"; do
    case $arg in
        --quick|-q)
            QUICK_MODE=true
            shift
            ;;
        *)
            if [[ "$arg" == platform=* ]]; then
                MANUAL_DESTINATION="$arg"
            fi
            ;;
    esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🚀 Running UI tests locally"
if [ "$QUICK_MODE" = true ]; then
    echo "⚡ Quick mode enabled"
fi
echo "⏱️  Start time: $(date)"
echo ""

# Check if we're in the right directory
if [ ! -d "Example" ]; then
    echo -e "${RED}❌ Error: Example directory not found. Please run this script from the project root.${NC}"
    exit 1
fi

# Step 1: Verify project structure
echo "📋 Verifying project structure..."
if [ -f "Example/DemoApp.xcworkspace/contents.xcworkspacedata" ]; then
    BUILD_TYPE="-workspace"
    BUILD_PATH_RELATIVE="DemoApp.xcworkspace"
    echo -e "${GREEN}✅ Found workspace: Example/DemoApp.xcworkspace${NC}"
elif [ -d "Example/DemoApp.xcodeproj" ]; then
    BUILD_TYPE="-project"
    BUILD_PATH_RELATIVE="DemoApp.xcodeproj"
    echo -e "${GREEN}✅ Found project: Example/DemoApp.xcodeproj${NC}"
else
    echo -e "${RED}❌ Project/workspace not found in Example/ directory${NC}"
    exit 1
fi

SCHEME="DemoAppSwift"
CI_DEPLOYMENT_TARGET="${CI_DEPLOYMENT_TARGET:-18.0}"
echo ""

# Step 2: Set destination
if [ "$QUICK_MODE" = true ] || [ -n "$MANUAL_DESTINATION" ]; then
    # Quick mode or manual destination provided
    if [ -n "$MANUAL_DESTINATION" ]; then
        DESTINATION_SPEC="$MANUAL_DESTINATION"
        echo "🎯 Using provided destination: $DESTINATION_SPEC"
    else
        # Quick mode default
        DESTINATION_SPEC="platform=iOS Simulator,name=iPhone 16,OS=18.5"
        echo "🎯 Quick mode: Using default destination: $DESTINATION_SPEC"
    fi
    NAME=$(echo "$DESTINATION_SPEC" | sed -n 's/.*name=\([^,]*\).*/\1/p' | xargs || echo "")
else
    # Full mode: Auto-detect simulator
    echo "🔍 Xcode Diagnostics:"
    echo "===== XCODE SELECT ====="
    xcode-select -p
    echo ""
    echo "===== XCODE VERSION ====="
    xcodebuild -version
    echo ""
    
    echo "📱 Available iOS Simulators:"
    xcrun simctl list devices available 2>/dev/null | grep -E "iPhone|iPad" | head -20 || echo "   (Could not list simulators, will try xcodebuild destinations)"
    echo ""
    
    echo "🎯 Auto-detecting simulator destination..."
    cd Example
    
    OUT=$(xcodebuild -showdestinations $BUILD_TYPE "$BUILD_PATH_RELATIVE" -scheme "$SCHEME" 2>&1 || echo "")
    
    if echo "$OUT" | grep -q "platform:iOS Simulator"; then
        echo "   ✅ Found iOS Simulator destinations"
        OUT=$(echo "$OUT" | grep -E "platform:iOS Simulator")
    else
        echo -e "${YELLOW}⚠️ No iOS Simulator destinations found${NC}"
        echo ""
        echo -e "${YELLOW}💡 Tip: Use --quick flag or specify destination manually:${NC}"
        echo "   ./run-ui-tests.sh 'platform=iOS Simulator,name=iPhone 16,OS=18.5'"
        cd ..
        exit 1
    fi
    
    # Prefer iPhone 16 or newer with iOS 18.0+
    LINE=$(echo "$OUT" | grep -E "platform:iOS Simulator, id:.*name:iPhone (1[6-9]|[2-9][0-9])" | grep -E "OS:1[89]\.[0-9]" | head -1 || true)
    
    # If not found, try any iPhone with iOS 18.0+
    if [ -z "$LINE" ]; then
        LINE=$(echo "$OUT" | grep -E "platform:iOS Simulator, id:.*name:iPhone" | grep -E "OS:1[89]\.[0-9]" | head -1 || true)
    fi
    
    # If still not found, try any iPhone with iOS 17.0+ (fallback)
    if [ -z "$LINE" ]; then
        LINE=$(echo "$OUT" | grep -E "platform:iOS Simulator, id:.*name:iPhone" | grep -E "OS:1[7-9]\.[0-9]" | head -1 || true)
    fi
    
    # Last resort: any iPhone simulator
    if [ -z "$LINE" ]; then
        LINE=$(echo "$OUT" | grep -E "platform:iOS Simulator, id:.*name:iPhone" | head -1 || true)
    fi
    
    if [ -z "$LINE" ]; then
        echo -e "${RED}❌ No iPhone simulator destination found${NC}"
        cd ..
        exit 1
    fi
    
    NAME=$(echo "$LINE" | sed -n 's/.*name:\([^,}]*\).*/\1/p' | xargs)
    OS=$(echo "$LINE" | sed -n 's/.*OS:\([^,}]*\).*/\1/p' | xargs)
    
    if [ -z "$NAME" ] || [ -z "$OS" ]; then
        echo -e "${RED}❌ Failed to parse destination${NC}"
        cd ..
        exit 1
    fi
    
    DESTINATION_SPEC="platform=iOS Simulator,name=$NAME,OS=$OS"
    echo -e "${GREEN}✅ Selected simulator: $NAME ($OS)${NC}"
    echo "🎯 Destination spec: $DESTINATION_SPEC"
    cd ..
fi
echo ""

# Step 3: Boot simulator (only in full mode)
if [ "$QUICK_MODE" = false ] && [ -n "${NAME:-}" ] && [ "$DESTINATION_SPEC" != *"id="* ]; then
    echo "📱 Ensuring simulator is booted and ready..."
    xcrun simctl boot "$NAME" 2>/dev/null || echo "   Simulator already booted or booting..."
    sleep 3
    
    BOOTED=$(xcrun simctl list devices booted 2>/dev/null | grep -i "iPhone" | head -1 || echo "")
    if [ -z "$BOOTED" ]; then
        echo -e "${YELLOW}   ⚠️ No booted iPhone simulator found, but continuing...${NC}"
    else
        echo -e "${GREEN}   ✅ Booted simulator: $BOOTED${NC}"
    fi
    echo ""
fi

# Step 4: Generate required files
echo "📝 Checking required files..."
cd Example

if [ ! -f "envs.swift" ]; then
    PUBLIC_KEY="${DEMOAPP_API_KEY:-LOCAL_DUMMY_KEY}"
    printf 'import Foundation\n\npublic enum Envs: String {\n    case PUBLIC_KEY = "%s"\n    case PROXY_URL = "https://schema-validator-latest.onrender.com/logs"\n}\n' "$PUBLIC_KEY" > envs.swift
    echo -e "${GREEN}✅ Generated envs.swift${NC}"
else
    if [ "$QUICK_MODE" = false ]; then
        echo -e "${GREEN}✅ envs.swift already exists${NC}"
    fi
fi

if [ "$QUICK_MODE" = false ]; then
    if [ ! -f "GoogleService-Info.plist" ]; then
        echo "   Creating placeholder GoogleService-Info.plist..."
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n  <key>CLIENT_ID</key>\n  <string>LOCAL_DUMMY_CLIENT_ID</string>\n  <key>REVERSED_CLIENT_ID</key>\n  <string>LOCAL_DUMMY_REVERSED_CLIENT_ID</string>\n  <key>API_KEY</key>\n  <string>LOCAL_DUMMY_API_KEY</string>\n  <key>GCM_SENDER_ID</key>\n  <string>123456789</string>\n  <key>PLIST_VERSION</key>\n  <string>1</string>\n  <key>BUNDLE_ID</key>\n  <string>com.coralogix.DemoAppSwift</string>\n  <key>PROJECT_ID</key>\n  <string>local-dummy-project</string>\n  <key>STORAGE_BUCKET</key>\n  <string>local-dummy-project.appspot.com</string>\n  <key>IS_ADS_ENABLED</key>\n  <false/>\n  <key>IS_ANALYTICS_ENABLED</key>\n  <false/>\n  <key>IS_APPINVITE_ENABLED</key>\n  <true/>\n  <key>IS_GCM_ENABLED</key>\n  <true/>\n  <key>IS_SIGNIN_ENABLED</key>\n  <true/>\n  <key>GOOGLE_APP_ID</key>\n  <string>1:123456789:ios:abcdef123456</string>\n</dict>\n</plist>\n' > GoogleService-Info.plist
        echo -e "${GREEN}✅ Created placeholder GoogleService-Info.plist${NC}"
    else
        echo -e "${GREEN}✅ GoogleService-Info.plist already exists${NC}"
    fi
fi

cd ..
echo ""

# Step 5: Check/Install Fastlane
if [ "$QUICK_MODE" = false ]; then
    echo "🔧 Checking Fastlane installation..."
fi

if ! command -v fastlane &> /dev/null; then
    echo "⚠️  Fastlane not found. Installing..."
    gem install fastlane 2>&1 || {
        echo -e "${YELLOW}⚠️  Failed to install Fastlane automatically.${NC}"
        echo "   Falling back to direct xcodebuild..."
        USE_FASTLANE=false
    }
    USE_FASTLANE=true
else
    USE_FASTLANE=true
    if [ "$QUICK_MODE" = false ]; then
        fastlane --version
    fi
fi

if [ "$QUICK_MODE" = false ]; then
    echo ""
fi

# Step 6: Build for testing
echo "🔨 Building for testing (deployment target: $CI_DEPLOYMENT_TARGET)..."
BUILD_START=$(date +%s)

CPU_COUNT=$(sysctl -n hw.ncpu 2>/dev/null || echo "4")

cd Example

if [ "$QUICK_MODE" = false ] && command -v xcpretty &> /dev/null; then
    xcodebuild build-for-testing \
      $BUILD_TYPE "$BUILD_PATH_RELATIVE" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION_SPEC" \
      -derivedDataPath ../DerivedData \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGN_IDENTITY="" \
      IPHONEOS_DEPLOYMENT_TARGET="$CI_DEPLOYMENT_TARGET" \
      -jobs "$CPU_COUNT" \
      | xcpretty --color || cat
else
    xcodebuild build-for-testing \
      $BUILD_TYPE "$BUILD_PATH_RELATIVE" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION_SPEC" \
      -derivedDataPath ../DerivedData \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGN_IDENTITY="" \
      IPHONEOS_DEPLOYMENT_TARGET="$CI_DEPLOYMENT_TARGET" \
      -jobs "$CPU_COUNT"
fi

BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))
echo -e "${GREEN}✅ Build completed in ${BUILD_DURATION}s ($(($BUILD_DURATION / 60))m $(($BUILD_DURATION % 60))s)${NC}"
cd ..
echo ""

# Step 7: Run UI Tests
echo "🧪 Running UI tests via Fastlane (deployment target: $CI_DEPLOYMENT_TARGET)..."
TEST_START=$(date +%s)

if [ "$USE_FASTLANE" = true ] && command -v fastlane &> /dev/null; then
    fastlane ui_tests \
      workspace:"Example/$BUILD_PATH_RELATIVE" \
      scheme:"$SCHEME" \
      destination:"$DESTINATION_SPEC" \
      derived_data_path:"DerivedData" \
      test_class:"DemoAppUITests/SanityUITests/testAppSanity_mainViewAppearsOnLaunch" \
      deployment_target:"$CI_DEPLOYMENT_TARGET" \
      skip_build:true \
      working_directory:"Example"
    EXIT_CODE=$?
else
    echo "   Using xcodebuild directly (Fastlane not available)..."
    cd Example
    xcodebuild test-without-building \
      $BUILD_TYPE "$BUILD_PATH_RELATIVE" \
      -scheme "$SCHEME" \
      -destination "$DESTINATION_SPEC" \
      -derivedDataPath ../DerivedData \
      -only-testing:DemoAppUITests/SanityUITests/testAppSanity_mainViewAppearsOnLaunch \
      -resultBundlePath ../DerivedData/TestResults.xcresult \
      IPHONEOS_DEPLOYMENT_TARGET="$CI_DEPLOYMENT_TARGET"
    EXIT_CODE=$?
    cd ..
fi

TEST_END=$(date +%s)
TEST_DURATION=$((TEST_END - TEST_START))
echo "⏱️  Test duration: ${TEST_DURATION}s ($(($TEST_DURATION / 60))m $(($TEST_DURATION % 60))s)"
echo ""

# Step 8: Handle results
if [ "$EXIT_CODE" -ne 0 ]; then
    if [ "$QUICK_MODE" = false ]; then
        echo ""
        echo "==================== ❌ TEST FAILURE DETAILS ===================="
        echo "Exit code: $EXIT_CODE"
        echo ""
        
        # Extract test logs
        if [ -f test-output.log ]; then
            echo "📋 Test Logs (print statements from test):"
            grep -E "🕐|📱|🔍|✅|❌|👆|⏳|📄|🚀" test-output.log | tail -50 || echo "   No test logs found"
            echo ""
            
            echo "🔎 Last 150 lines of test output:"
            tail -n 150 test-output.log
            echo ""
            
            echo "🔎 Key error patterns:"
            grep -iE "error|fail|timeout|assert|unable|not found|did not appear" test-output.log | tail -30 || echo "   No error patterns found"
        fi
        
        # Extract from xcresult if available
        if [ -d DerivedData/TestResults.xcresult ]; then
            echo ""
            echo "📦 Extracting test failure details from xcresult..."
            TEMP_JSON=$(mktemp)
            if xcrun xcresulttool get --format json --path DerivedData/TestResults.xcresult > "$TEMP_JSON" 2>/dev/null; then
                if command -v jq &> /dev/null; then
                    echo "   Test failures:"
                    jq -r '
                      .. | select(.testFailureSummaries? != null) | 
                      .testFailureSummaries[]? | 
                      "   ❌ \(.message._value // .message.value // .message // "Unknown error")\n   📄 \(.fileName._value // .fileName.value // "Unknown"):\(.lineNumber._value // .lineNumber.value // "?")"
                    ' "$TEMP_JSON" 2>/dev/null || echo "   Could not parse failures"
                else
                    echo "   (jq not available, skipping JSON parsing)"
                fi
            fi
            rm -f "$TEMP_JSON"
        fi
        
        echo "============================================================="
    fi
    
    echo -e "${RED}❌ Tests failed with exit code: $EXIT_CODE${NC}"
    exit "$EXIT_CODE"
fi

echo -e "${GREEN}✅ Tests passed!${NC}"
echo "⏱️  End time: $(date)"
echo ""

if [ "$QUICK_MODE" = false ]; then
    echo -e "${GREEN}🎉 All UI tests completed successfully!${NC}"
fi

