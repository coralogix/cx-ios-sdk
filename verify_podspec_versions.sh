#!/bin/bash
set -euo pipefail

# Usage:
#   ./verify_podspec_versions.sh v1.2.3
# or
#   TAG=v1.2.3 ./verify_podspec_versions.sh

# Resolve TAG
if [ $# -gt 0 ]; then
  TAG_RAW="$1"
else
  TAG_RAW="${TAG:-}"
fi

if [ -z "$TAG_RAW" ]; then
  echo "❌ No tag provided. Usage: ./verify_podspec_versions.sh v1.2.3"
  exit 1
fi

# Strip leading v if present
TAG="${TAG_RAW#v}"

echo "Release tag: $TAG"

SPECS=(CoralogixInternal.podspec SessionReplay.podspec Coralogix.podspec)

for SPEC in "${SPECS[@]}"; do
  echo "Checking $SPEC..."
  if [ ! -f "$SPEC" ]; then
    echo "❌ $SPEC not found"
    exit 1
  fi

  # Extract the version string (handles spec.version = "1.2.3" or '1.2.3')
  VERSION_LINE="$(grep -E 'version\s*=' "$SPEC" | head -1)"
  V="$(echo "$VERSION_LINE" | sed -E 's/.*["'\'']([^"'\'']+)["'\''].*/\1/')"

  if [ -z "$V" ]; then
    echo "❌ Failed to parse version from $SPEC"
    exit 1
  fi

  echo "$SPEC -> $V"

  if [ "$V" != "$TAG" ]; then
    echo "❌ $SPEC version ($V) does not match release tag ($TAG)"
    exit 1
  fi
done

echo "✅ All podspec versions match release tag $TAG"
