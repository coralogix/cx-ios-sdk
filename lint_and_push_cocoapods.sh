#!/bin/bash

set -e

# Podspecs
INTERNAL="CoralogixInternal.podspec"
MAIN="Coralogix.podspec"
SESSION_REPLAY="SessionReplay.podspec"

echo "🔍 Linting $INTERNAL..."
pod lib lint "$INTERNAL" --verbose --no-clean --allow-warnings
echo "✅ $INTERNAL passed lint."

echo "🔍 Linting $MAIN with dependency on $INTERNAL..."
pod lib lint "$MAIN" --include-podspecs="$INTERNAL" --verbose --no-clean --allow-warnings
echo "✅ $MAIN passed lint."

echo "🔍 Linting $SESSION_REPLAY with dependency on $INTERNAL..."
pod lib lint "$SESSION_REPLAY" --include-podspecs="$INTERNAL" --verbose --no-clean --allow-warnings
echo "✅ $SESSION_REPLAY passed lint."

# Ask before pushing
read -p "🟡 All lint checks passed. Do you want to push $MAIN to CocoaPods trunk? (y/n): " should_push

if [[ "$should_push" == "y" || "$should_push" == "Y" ]]; then
  echo "🚀 Pushing $MAIN to CocoaPods trunk..."
  pod trunk push "$MAIN" --allow-warnings --verbose
  echo "🎉 Done!"
else
  echo "🚫 Push canceled."
fi

