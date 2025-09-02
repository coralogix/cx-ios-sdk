#!/bin/bash

set -e

# Podspecs
INTERNAL="CoralogixInternal.podspec"
MAIN="Coralogix.podspec"
SESSION_REPLAY="SessionReplay.podspec"

# Lint all podspecs (INTERNAL, SESSION_REPLAY, MAIN)
echo "🔍 Linting $INTERNAL..."
pod lib lint "$INTERNAL" --verbose --no-clean --allow-warnings
echo "✅ $INTERNAL passed lint."

echo "🔍 Linting $SESSION_REPLAY with dependency on $INTERNAL..."
pod lib lint "$SESSION_REPLAY" --include-podspecs="$INTERNAL" --verbose --no-clean --allow-warnings
echo "✅ $SESSION_REPLAY passed lint."

echo "🔍 Linting $MAIN with dependency on $INTERNAL..."
pod lib lint "$MAIN" --include-podspecs="$INTERNAL" --verbose --no-clean --allow-warnings
echo "✅ $MAIN passed lint."

# Push INTERNAL
read -p "🟡 Do you want to push $INTERNAL to CocoaPods trunk? (y/n): " push_internal
if [[ "$push_internal" =~ ^[Yy]$ ]]; then
  echo "🚀 Pushing $INTERNAL..."
  pod trunk push "$INTERNAL" --allow-warnings --verbose
  echo "✅ $INTERNAL pushed!"
  
  # Wait for CoralogixInternal to become available
  echo "⏳ Waiting for $INTERNAL to be available in CocoaPods Specs..."
  until pod search CoralogixInternal | grep -q "CoralogixInternal"; do
    echo "⏳ $INTERNAL not yet available, waiting 30 seconds..."
    sleep 30
  done
  echo "✅ $INTERNAL is now available!"
else
  echo "⏭️ Skipping $INTERNAL push."
fi

# Push SESSION_REPLAY
read -p "🟡 Do you want to push $SESSION_REPLAY to CocoaPods trunk? (y/n): " push_sr
if [[ "$push_sr" =~ ^[Yy]$ ]]; then
  echo "🚀 Pushing $SESSION_REPLAY..."
  pod trunk push "$SESSION_REPLAY" --allow-warnings --verbose
  echo "✅ $SESSION_REPLAY pushed!"
else
  echo "⏭️ Skipping $SESSION_REPLAY push."
fi

# Push MAIN
read -p "🟡 Do you want to push $MAIN to CocoaPods trunk? (y/n): " push_main
if [[ "$push_main" =~ ^[Yy]$ ]]; then
  echo "🚀 Pushing $MAIN..."
  pod trunk push "$MAIN" --allow-warnings --verbose
  echo "🎉 $MAIN pushed successfully! 🎉"
else
  echo "⏭️ Skipping … push."
fi

