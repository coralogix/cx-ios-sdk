#!/bin/bash

set -e

# Podspecs
MAIN="Coralogix.podspec"

# Ask if user wants to run lint
read -p "🟡 Do you want to run lint on the podspec? (y/n): " run_lint
if [[ "$run_lint" =~ ^[Yy]$ ]]; then
  echo "🔍 Linting $MAIN..."
  pod lib lint "$MAIN" --verbose --no-clean --allow-warnings
  echo "✅ $MAIN passed lint."
else
  echo "⏭️ Skipping lint, proceeding to upload phase."
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

