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
    echo "new_version: $new_version"
    echo "swift_file: $swift_file"

  sed -i '' "s/iosSdk = \".*\"/iosSdk = \"$new_version\"/" $swift_file
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
swift_file="$script_dir/Sources/Utils/Keys.swift"

if [ ! -f "$swift_file" ]; then
  echo "File not found: $swift_file"
  exit 1
fi

# Extract current version from the Swift file
 echo "swift_file $swift_file"

current_version=$(grep -oE 'case iosSdk = "[0-9]+\.[0-9]+\.[0-9]+"' "$swift_file" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
echo "current_version $current_version"

if [ -z "$current_version" ]; then
  echo "Current version not found in $swift_file"
  exit 1
fi
 
new_version=$(increment_version $current_version $part)
echo "new_version $new_version"

# Use sed to update the version only where iosSdk = "x.x.x"
sed -i '' -E "s/(case iosSdk = \")$current_version(\")/\1$new_version\2/" "$swift_file"

# Check if the sed command was successful
if [ $? -eq 0 ]; then
    echo "Version updated successfully to $NEW_VERSION in $FILE_PATH"
else
    echo "Failed to update the version"
    exit 1
fi
