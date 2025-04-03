#!/bin/bash

PODSPEC="Coralogix.podspec"

echo "🔍 Running pod lib lint..."
pod lib lint "$PODSPEC" --allow-warnings --verbose

if [ $? -eq 0 ]; then
  echo "✅ Lint passed. Pushing to CocoaPods trunk..."
  pod trunk push "$PODSPEC" --allow-warnings --verbose
else
  echo "❌ Lint failed. Aborting push."
  exit 1
fi
