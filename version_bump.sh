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

# Function to update version in the coralogix podspec file
update_version_in_c_podspec() {
  local new_version=$1
  local podspec_c_file=$2
  echo "Updating podspec file: $podspec_c_file"
  sed -i '' "s/spec.version.*=.*\"[0-9]*\.[0-9]*\.[0-9]*\"/spec.version      = \"$new_version\"/" "$podspec_c_file"
}

# Function to update version in the coralogix podspec file
update_version_in_ci_podspec() {
  local new_version=$1
  local podspec_ci_file=$2
  echo "Updating podspec file: $podspec_ci_file"
  sed -i '' "s/spec.version.*=.*\"[0-9]*\.[0-9]*\.[0-9]*\"/spec.version      = \"$new_version\"/" "$podspec_ci_file"
}

# Function to update version in the coralogix podspec file
update_version_in_sr_podspec() {
  local new_version=$1
  local podspec_sr_file=$2
  echo "Updating podspec file: $podspec_sr_file"
  sed -i '' "s/spec.version.*=.*\"[0-9]*\.[0-9]*\.[0-9]*\"/spec.version      = \"$new_version\"/" "$podspec_sr_file"
}

# Function to update CoralogixInternal dependency version in a podspec file
update_internal_dependency_version() {
  local new_version=$1
  local podspec_file=$2
  echo "Updating dependency version in: $podspec_file"
  sed -i '' "s/\(spec.dependency 'CoralogixInternal', '\)[0-9]*\.[0-9]*\.[0-9]*\('\)/\1$new_version\2/" "$podspec_file"
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
swift_file="$script_dir/CoralogixInternal/Sources/Utils.swift"
podspec_c_file="$script_dir/Coralogix.podspec"
podspec_ci_file="$script_dir/CoralogixInternal.podspec"
podspec_sr_file="$script_dir/SessionReplay.podspec"

if [ ! -f "$swift_file" ]; then
  echo "File not found: $swift_file"
  exit 1
fi

if [ ! -f "$podspec_c_file" ]; then
  echo "File not found: $podspec_c_file"
  exit 1
fi

if [ ! -f "$podspec_ci_file" ]; then
  echo "File not found: $podspec_ci_file"
  exit 1
fi

if [ ! -f "$podspec_sr_file" ]; then
  echo "File not found: $podspec_sr_file"
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
swift_result=$?

# Update the version in the coralogix podspec file
update_version_in_c_podspec "$new_version" "$podspec_c_file"
c_result=$?

# Update the version in the coralogix-internal podspec file
update_version_in_ci_podspec "$new_version" "$podspec_ci_file"
ci_result=$?

# Update the version in the session recording podspec file
update_version_in_sr_podspec "$new_version" "$podspec_sr_file"
sr_result=$?

# Update CoralogixInternal dependency version in Coralogix.podspec and SessionReplay.podspec
update_internal_dependency_version "$new_version" "$podspec_c_file";
dep_c_result=$?

update_internal_dependency_version "$new_version" "$podspec_sr_file";
dep_sr_result=$?


# Check if the sed command was successful for the Swift file
if [ $swift_result -eq 0 ]; then
    echo "✅ Version updated successfully to $new_version in $swift_file"
else
    echo "❌ Failed to update the version in $swift_file"
    exit 1
fi

# Check if the sed command was successful for the podspec file
if [ $c_result -eq 0 ]; then
    echo "✅ Version updated successfully to $new_version in $podspec_c_file"
else
    echo "❌ Failed to update the version in $podspec_c_file"
    exit 1
fi

# Check if the sed command was successful for the podspec file
if [ $ci_result -eq 0 ]; then
    echo "✅ Version updated successfully to $new_version in $podspec_ci_file"
else
    echo "❌ Failed to update the version in $podspec_ci_file"
    exit 1
fi

# Check if the sed command was successful for the podspec file
if [ $sr_result -eq 0 ]; then
    echo "✅ Version updated successfully to $new_version in $podspec_sr_file"
else
    echo "❌ Failed to update the version in $podspec_sr_file"
    exit 1
fi

# Check if the sed command was successful for the podspec file
if [ $dep_c_result -eq 0 ]; then
    echo "✅ Dependency version updated in Coralogix.podspec"
else
    echo "❌ Failed to update dependency in Coralogix.podspec"
    exit 1
fi

# Check if the sed command was successful for the podspec file
if [ $dep_sr_result -eq 0 ]; then
    echo "✅ Dependency version updated in SessionReplay.podspec"
else
    echo "❌ Failed to update dependency in SessionReplay.podspec"
    exit 1
fi
