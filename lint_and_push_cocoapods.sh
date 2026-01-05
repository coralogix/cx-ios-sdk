#!/bin/bash

set -e

# Podspecs
INTERNAL="CoralogixInternal.podspec"
MAIN="Coralogix.podspec"
SESSION_REPLAY="SessionReplay.podspec"

# Ask if user wants to run lint
read -p "🟡 Do you want to run lint on all podspecs? (y/n): " run_lint
if [[ "$run_lint" =~ ^[Yy]$ ]]; then
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
else
  echo "⏭️ Skipping lint, proceeding to upload phase."
fi

# Push INTERNAL
read -p "🟡 Do you want to push $INTERNAL to CocoaPods trunk? (y/n): " push_internal
if [[ "$push_internal" =~ ^[Yy]$ ]]; then
  echo "🚀 Pushing $INTERNAL..."
  set +e
  push_output=$(pod trunk push "$INTERNAL" --allow-warnings --verbose 2>&1)
  push_exit_code=$?
  set -e
  
  if [ $push_exit_code -eq 0 ]; then
    echo "✅ $INTERNAL pushed!"
    
    # Wait for CoralogixInternal to become available
    echo "⏳ Waiting for $INTERNAL to be available in CocoaPods Specs..."
    until pod search CoralogixInternal | grep -q "CoralogixInternal"; do
      echo "⏳ $INTERNAL not yet available, waiting 30 seconds..."
      sleep 30
    done
    echo "✅ $INTERNAL is now available!"
  else
    if echo "$push_output" | grep -q "Unable to accept duplicate entry"; then
      echo "⚠️ Duplicate entry detected for $INTERNAL, skipping to next phase..."
    else
      echo "❌ Error pushing $INTERNAL:"
      echo "$push_output"
      exit 1
    fi
  fi
else
  echo "⏭️ Skipping $INTERNAL push."
fi

# Push SESSION_REPLAY
read -p "🟡 Do you want to push $SESSION_REPLAY to CocoaPods trunk? (y/n): " push_sr
if [[ "$push_sr" =~ ^[Yy]$ ]]; then
  echo "🚀 Pushing $SESSION_REPLAY..."
  set +e
  push_output=$(pod trunk push "$SESSION_REPLAY" --allow-warnings --verbose 2>&1)
  push_exit_code=$?
  set -e
  
  if [ $push_exit_code -eq 0 ]; then
    echo "✅ $SESSION_REPLAY pushed!"
  else
    if echo "$push_output" | grep -q "Unable to accept duplicate entry"; then
      echo "⚠️ Duplicate entry detected for $SESSION_REPLAY, skipping to next phase..."
    else
      echo "❌ Error pushing $SESSION_REPLAY:"
      echo "$push_output"
      exit 1
    fi
  fi
else
  echo "⏭️ Skipping $SESSION_REPLAY push."
fi

# Push MAIN
read -p "🟡 Do you want to push $MAIN to CocoaPods trunk? (y/n): " push_main
if [[ "$push_main" =~ ^[Yy]$ ]]; then
  echo "🚀 Pushing $MAIN..."
  set +e
  push_output=$(pod trunk push "$MAIN" --allow-warnings --verbose 2>&1)
  push_exit_code=$?
  set -e
  
  if [ $push_exit_code -eq 0 ]; then
    echo "🎉 $MAIN pushed successfully! 🎉"
  else
    if echo "$push_output" | grep -q "Unable to accept duplicate entry"; then
      echo "⚠️ Duplicate entry detected for $MAIN, skipping..."
    else
      echo "❌ Error pushing $MAIN:"
      echo "$push_output"
      exit 1
    fi
  fi
else
  echo "⏭️ Skipping $MAIN push."
fi

