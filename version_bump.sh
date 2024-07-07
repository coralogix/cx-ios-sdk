#!/bin/bash
# usage (update the sdk version in keys.swift under global)
# ./version_bump.sh patch  -> will bump x.x.1 
# ./version_bump.sh minor  -> will bump x.1.1
# ./version_bump.sh major  -> will bump 1.x.x

# Function to increment version
increment_version() {
  local version=$1
  local part=$2
  local major=$(echo $version | cut -d. -f1)
  local minor=$(echo $version | cut -d. -f2)
  local patch=$(echo $version | cut -d. -f3)
 
  case $part in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      echo "Unknown part: $part"
      exit 1
      ;;
  esac

  echo "$major.$minor.$patch"
}

# Function to update version in the Swift file
update_version_in_swift_file() {
  local new_version=$1
  local swift_file=$2
  echo "Updating Swift file: $swift_file"
  sed -i '' "s/sdk = \".*\"/sdk = \"$new_version\"/" "$swift_file"
}

# Function to update version in the podspec file
update_version_in_podspec() {
  local new_version=$1
  local podspec_file=$2
  echo "Updating podspec file: $podspec_file"
  sed -i '' "s/spec.version.*=.*\"[0-9]*\.[0-9]*\.[0-9]*\"/spec.version      = \"$new_version\"/" "$podspec_file"
}

# Main script logic
if [ $# -ne 1 ]; then
  echo "Usage: $0 {major|minor|patch}"
  exit 1
fi

part=$1

# Get the absolute path of the script directory
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Combine the script directory with the relative path to get the absolute path of the Swift file
swift_file="$script_dir/Coralogix/Sources/Utils/Keys.swift"
podspec_file="$script_dir/Coralogix.podspec"

if [ ! -f "$swift_file" ]; then
  echo "File not found: $swift_file"
  exit 1
fi

if [ ! -f "$podspec_file" ]; then
  echo "File not found: $podspec_file"
  exit 1
fi

# Extract current version from the Swift file
current_version=$(grep -oE 'sdk = "[0-9]+\.[0-9]+\.[0-9]+"' "$swift_file" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
echo "Current version: $current_version"

if [ -z "$current_version" ]; then
  echo "Current version not found in $swift_file"
  exit 1
fi

# Increment the version
new_version=$(increment_version "$current_version" "$part")
echo "New version: $new_version"

# Update the version in the Swift file
update_version_in_swift_file "$new_version" "$swift_file"

# Update the version in the podspec file
update_version_in_podspec "$new_version" "$podspec_file"

# Check if the sed command was successful for the Swift file
if [ $? -eq 0 ]; then
    echo "Version updated successfully to $new_version in $swift_file"
else
    echo "Failed to update the version in $swift_file"
    exit 1
fi

# Check if the sed command was successful for the podspec file
if [ $? -eq 0 ]; then
    echo "Version updated successfully to $new_version in $podspec_file"
else
    echo "Failed to update the version in $podspec_file"
    exit 1
fi