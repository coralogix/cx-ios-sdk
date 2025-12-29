#!/bin/bash
# Unified script to parse test results from log and xcresult bundle
# Usage:
#   ./parse-test-results.sh                    # Full mode (parses log + xcresult)
#   ./parse-test-results.sh --quick            # Quick mode (log only)
#   ./parse-test-results.sh [result-bundle] [log-file]  # Custom paths

set -euo pipefail

# Parse arguments
QUICK_MODE=false
RESULT_BUNDLE=""
LOG_FILE=""

for arg in "$@"; do
    case $arg in
        --quick|-q)
            QUICK_MODE=true
            shift
            ;;
        *)
            if [ -z "$RESULT_BUNDLE" ]; then
                RESULT_BUNDLE="$arg"
            elif [ -z "$LOG_FILE" ]; then
                LOG_FILE="$arg"
            fi
            ;;
    esac
done

# Set defaults
RESULT_BUNDLE="${RESULT_BUNDLE:-DerivedData/TestResults.xcresult}"
LOG_FILE="${LOG_FILE:-test-output.log}"

echo "📊 Parsing Test Results"
if [ "$QUICK_MODE" = true ]; then
    echo "⚡ Quick mode (log only)"
fi
echo "============================================================"
echo ""

# Parse log file
if [ -f "$LOG_FILE" ]; then
    echo "📄 From test-output.log:"
    
    if grep -qi "TEST EXECUTE SUCCEEDED" "$LOG_FILE"; then
        echo "   ✅ TEST EXECUTION: SUCCEEDED"
        OVERALL_STATUS="PASSED"
    elif grep -qi "TEST EXECUTE FAILED" "$LOG_FILE"; then
        echo "   ❌ TEST EXECUTION: FAILED"
        OVERALL_STATUS="FAILED"
    else
        echo "   ⚠️  TEST EXECUTION: UNKNOWN"
        OVERALL_STATUS="UNKNOWN"
    fi
    
    # Extract test suite info
    TEST_SUITE=$(grep -i "Test suite" "$LOG_FILE" | head -1 | sed 's/.*Test suite //' | sed "s/ started.*//" || echo "Unknown")
    echo "   📋 Test Suite: $TEST_SUITE"
    
    # Extract test duration
    DURATION=$(grep -iE "elapsed|duration" "$LOG_FILE" | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "Unknown")
    if [ "$DURATION" != "Unknown" ]; then
        echo "   ⏱️  Duration: ${DURATION}s"
    fi
    
    if [ "$QUICK_MODE" = false ]; then
        # Look for specific test results
        echo ""
        echo "🔍 Test case results:"
        TEST_CASES=$(grep -iE "test.*\(|testCase|test method" "$LOG_FILE" | head -10 || echo "")
        if [ -n "$TEST_CASES" ]; then
            echo "$TEST_CASES" | sed 's/^/   /'
        else
            echo "   (Detailed results in xcresult bundle)"
        fi
    fi
    
    echo ""
else
    echo "⚠️  Log file not found: $LOG_FILE"
    OVERALL_STATUS="UNKNOWN"
fi

# Try to extract from xcresult bundle (only in full mode)
if [ "$QUICK_MODE" = false ] && [ -d "$RESULT_BUNDLE" ]; then
    echo "📦 From xcresult bundle:"
    
    # Try to get summary using xcresulttool (try legacy API)
    TEMP_OUTPUT=$(mktemp)
    # Try legacy API (required in newer Xcode versions)
    if xcrun xcresulttool get object --legacy --path "$RESULT_BUNDLE" --format json > "$TEMP_OUTPUT" 2>/dev/null; then
        # Try to extract test failures and statistics
        if command -v python3 &> /dev/null; then
            python3 << EOF
import json
import sys

try:
    with open("$TEMP_OUTPUT", 'r') as f:
        data = json.load(f)
    
    # Find test failure summaries
    def find_failures(obj, path=""):
        failures = []
        if isinstance(obj, dict):
            # Look for testFailureSummaries
            if 'testFailureSummaries' in obj:
                for summary in obj['testFailureSummaries']:
                    if isinstance(summary, dict):
                        failures.append(summary)
            if 'issues' in obj:
                for issue in obj['issues']:
                    if isinstance(issue, dict) and 'testFailureSummaries' in issue:
                        failures.extend(issue['testFailureSummaries'])
            
            # Recursively search
            for key, value in obj.items():
                if isinstance(value, (dict, list)):
                    failures.extend(find_failures(value, f"{path}.{key}"))
                    
        elif isinstance(obj, list):
            for i, item in enumerate(obj):
                failures.extend(find_failures(item, f"{path}[{i}]"))
        
        return failures
    
    # Find test statistics
    def find_stats(obj):
        stats = {}
        if isinstance(obj, dict):
            for key in ['testsCount', 'testCount', 'passedCount', 'failedCount', 'totalTests']:
                if key in obj:
                    val = obj[key]
                    if isinstance(val, dict) and '_value' in val:
                        stats[key] = val['_value']
                    elif isinstance(val, (int, str)):
                        stats[key] = val
            
            for key, value in obj.items():
                if isinstance(value, (dict, list)):
                    sub_stats = find_stats(value)
                    stats.update(sub_stats)
        elif isinstance(obj, list):
            for item in obj:
                sub_stats = find_stats(item)
                stats.update(sub_stats)
        
        return stats
    
    failures = find_failures(data)
    stats = find_stats(data)
    
    # Print failure details
    if failures:
        print("   ❌ Test Failures:")
        for i, failure in enumerate(failures[:10], 1):
            print(f"      Failure {i}:")
            
            # Extract message
            if 'message' in failure:
                msg = failure['message']
                if isinstance(msg, dict):
                    msg_text = msg.get('_value', msg.get('value', str(msg)))
                else:
                    msg_text = str(msg)
                print(f"         Message: {msg_text}")
            
            # Extract file name
            if 'fileName' in failure:
                file_name = failure['fileName']
                if isinstance(file_name, dict):
                    file_text = file_name.get('_value', file_name.get('value', 'Unknown'))
                else:
                    file_text = str(file_name)
                print(f"         File: {file_text}")
            
            # Extract line number
            if 'lineNumber' in failure:
                line_num = failure['lineNumber']
                if isinstance(line_num, dict):
                    line_text = line_num.get('_value', line_num.get('value', '?'))
                else:
                    line_text = str(line_num)
                print(f"         Line: {line_text}")
            
            print()
    elif stats:
        print("   ℹ️  No detailed failure messages found in bundle")
        print("   (Failure details may be in a different format)")
        print()
    
    # Print statistics
    if stats:
        print("   📊 Test Statistics:")
        for key, value in stats.items():
            print(f"      {key}: {value}")
    else:
        print("   ℹ️  Detailed statistics not available")
        print("   (Open the xcresult bundle in Xcode for full details)")
        
except json.JSONDecodeError:
    print("   ⚠️  Could not parse JSON from xcresult bundle")
    print("   (The bundle may be empty or corrupted)")
except Exception as e:
    print(f"   ⚠️  Error parsing xcresult: {e}")
EOF
        else
            echo "   ⚠️  python3 not available - cannot parse JSON"
        fi
    else
        echo "   ⚠️  Could not extract JSON from xcresult bundle"
        echo "   (Try opening it in Xcode: open $RESULT_BUNDLE)"
    fi
    
    rm -f "$TEMP_OUTPUT"
    echo ""
fi

# Check for errors and assertion failures (only in full mode)
if [ "$QUICK_MODE" = false ] && [ -f "$LOG_FILE" ]; then
    # Look for assertion failure messages in the log
    ASSERTION_FAILURES=$(grep -iE "XCTAssert|assertion failed|button not found|not found|did not appear" "$LOG_FILE" 2>/dev/null | head -5 || echo "")
    if [ -n "$ASSERTION_FAILURES" ]; then
        echo "🔍 Assertion Failures Found:"
        echo "$ASSERTION_FAILURES" | sed 's/^/   /'
        echo ""
    fi
    
    ERROR_COUNT=$(grep -ciE "error|fail|exception" "$LOG_FILE" 2>/dev/null | grep -v "SUCCEEDED" || echo "0")
    if [ -n "$ERROR_COUNT" ] && [ "$ERROR_COUNT" != "0" ] 2>/dev/null; then
        echo "⚠️  Found potential error/failure mentions in log"
        echo "   Recent errors:"
        grep -iE "error|fail|exception" "$LOG_FILE" | grep -v "SUCCEEDED" | tail -5 | sed 's/^/   /' || echo "   (none found)"
        echo ""
    fi
fi

# Final summary
echo "============================================================"
echo "📊 FINAL RESULT:"
echo ""

if [ "$OVERALL_STATUS" = "PASSED" ]; then
    echo "   ✅ ALL TESTS PASSED!"
    echo ""
    if [ "$QUICK_MODE" = false ]; then
        echo "   The test 'testAppSanity_mainViewAppearsOnLaunch' completed successfully."
        echo "   You can view detailed results in Xcode by opening:"
        echo "   $RESULT_BUNDLE"
    fi
    exit 0
elif [ "$OVERALL_STATUS" = "FAILED" ]; then
    echo "   ❌ TESTS FAILED!"
    echo ""
    
    # Try to provide helpful context based on test name
    if grep -q "testAppSanity_mainViewAppearsOnLaunch" "$LOG_FILE" 2>/dev/null; then
        echo "   📝 Test: testAppSanity_mainViewAppearsOnLaunch"
        echo ""
        echo "   💡 Expected Failure Details:"
        echo "      The test is looking for 'Network instrumentations' (plural)"
        echo "      but the actual button text is 'Network instrumentation' (singular)."
        echo "      This causes XCTAssertTrue on line 36 to fail with:"
        echo "      \"❌ 'Network instrumentation' button not found\""
        echo ""
        echo "   📄 File: Example/DemoAppUITests/SanityUITests.swift"
        echo "   📍 Line: 36"
        echo ""
    fi
    
    echo "   For detailed failure messages, open the xcresult bundle in Xcode:"
    echo "   open $RESULT_BUNDLE"
    echo ""
    echo "   Or check the test output log:"
    echo "   $LOG_FILE"
    exit 1
else
    echo "   ⚠️  Could not determine test status"
    echo ""
    echo "   Check the files manually:"
    echo "   - Log: $LOG_FILE"
    if [ "$QUICK_MODE" = false ]; then
        echo "   - Results: $RESULT_BUNDLE"
    fi
    exit 2
fi
