#!/bin/bash

set -e

#source="../opentelemetry-swift"
source="../cx-ios-sdk"

github_url="https://github.com/open-telemetry/opentelemetry-swift"
target=""

# Usage function
function usage() {
    echo "Usage: $0 [-s <source>] [-t <target>]"
    echo "  -s, --source    Specify the source directory"
    echo "  -g, --github    Specify the github url"
    echo "  -t, --target    Specify the target directory"
    echo "  -h, --help      Display this help message"
    exit 0
}

# Parse command-line arguments
while (( "$#" )); do
    case "$1" in
        -s|--source)
                source="$2"
                shift 2
                ;;
        -t|--target)
                target="$2"
                shift 2
                ;;
        -g|--github)
                github_url="$2"
                shift 2
                ;;
        -h|--help)
                usage
                ;;
        --) # end argument parsing
            shift
            break
            ;;
        -*|--*=) # unsupported flags
            echo "Error: Unsupported flag $1" >&2
            exit 1
            ;;
        *) # preserve positional arguments
            PARAMS="$PARAMS $1"
            shift
            ;;
    esac
done

echo "Source: $source"
echo "Target: $target"

# Replace all type: .static with .dynamic
# Static libraries can't be bundled into xcframeworks hence the need to replace them with dynamic libraries
function update_package_swift() {
    file=$1
    # check if the file exists
    if [ ! -f $file ]; then
        echo "File $file does not exist"
        return
    fi
    echo "Updating $file"
    sed -i '' 's/.static/.dynamic/g' $file
}


# Build the scheme for the platform
function build() {
    scheme=$1
    platform=$2

    archs=""
    if [ "$platform" == "iOS" ]; then
        archs="arm64 arm64e"
    elif [ "$platform" == "iOS Simulator" ]; then
        archs="x86_64 arm64"
    elif [ "$platform" == "tvOS" ]; then
        archs="arm64"
    elif [ "$platform" == "tvOS Simulator" ]; then
        archs="x86_64 arm64"
    elif [ "$platform" == "macOS" ]; then
        archs="x86_64 arm64"
    fi

    echo "Building $scheme for $platform"
    xcodebuild archive -workspace $source \
        -scheme $scheme \
        -destination "generic/platform=$platform" \
        -archivePath "archives/$scheme/$platform" \
        -derivedDataPath ".build" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        ARCHS="$archs" \
        | xcpretty
    echo "Done archiving $scheme for $platform"

    xcframework_path="archives/$scheme/$platform.xcarchive/Products/usr/local/lib/"
    cp -R ./Coralogix/Frameworks/PLCrashReporter/CrashReporter.xcframework "$xcframework_path"
    echo "Done copying All xcframework"

    # Copy the swiftmodule to the framework
    framework_path="archives/$scheme/$platform.xcarchive/Products/usr/local/lib/$scheme.framework"
    echo "Copying swiftmodule to $framework_path"

    modules_path="$framework_path/Modules"
    mkdir -p "$modules_path"

    build_products_path=".build/Build/Intermediates.noindex/ArchiveIntermediates/$scheme/BuildProductsPath"

    # The platform name is used to determine the swiftmodule path
    case $platform in
        "iOS")
            release_folder="Release-iphoneos"
            ;;
        "iOS Simulator")
            release_folder="Release-iphonesimulator"
            ;;
        "tvOS")
            release_folder="Release-appletvos"
            ;;
        "tvOS Simulator")
            release_folder="Release-appletvsimulator"
            ;;
        "macOS")
            release_folder="Release" # for some reason, the directory is not suffixed with the platform name
            ;;
    esac

    release_path="$build_products_path/$release_folder"
    swift_module_path="$release_path/$scheme.swiftmodule"
    cp -r "$swift_module_path" "$modules_path"
    echo "Done copying swiftmodule to $framework_path"
}

# Create xcframework from the archives
function package() {
    scheme=$1
    shift
    platforms=("$@")

    args=()
    for platform in "${platforms[@]}"; do
        echo "Adding $platform to $scheme.xcframework"

        framework_path="archives/$scheme/$platform.xcarchive/Products/usr/local/lib/$scheme.framework"

        # For some reason, the dsym path needs to be absolute, else framework creation fails
        dsym_path=`readlink -f "archives/$scheme/$platform.xcarchive/dSYMs/$scheme.framework.dSYM"`

        args+=("-framework" "$framework_path" "-debug-symbols" "$dsym_path")
    done

  #  args+=("-framework" "Coralogix/Frameworks/PLCrashReporter/CrashReporter.xcframework")
  #  echo "######### $args"
  #  for arg in "${args[@]}"; do
  #      echo "$arg"
  #  done

    echo "Removing archives/$scheme.xcframework"
    rm -rf "frameworks/$scheme.xcframework"

    echo "Creating $scheme.xcframework"
    xcodebuild -create-xcframework "${args[@]}" -output "frameworks/$scheme/$scheme.xcframework" | xcpretty
    echo "Done creating $scheme.xcframework"
}

# Zip the xcframework
function compress() {
    scheme=$1
    echo "Removing artifacts/$scheme.zip"
    rm -rf "artifacts/$scheme.zip"

    echo "Zipping $scheme"
    mkdir -p "artifacts"

    # by default zip will include the full path of the files in the zip file
    # -j will not include the path but it doesn't work with -r
    pushd "frameworks"
    zip -r "../artifacts/$scheme.zip" "$scheme"
    popd
    echo "Done zipping $scheme"
}

# Writes the source information to given file file
# It includes the git commit hash and tag name
function create_version_info() {
    file=$1

    echo "Removing version info $file"
    rm -rf $file

    pushd $source
    # git describe can fail if there are no tags on the current commit
    tag=$(git describe --tags --exact-match HEAD 2> /dev/null || true)
    if [ $? -ne 0 ]; then
        echo "No tags on the current commit"
        tag="N/A"
    fi
    commit=`git rev-parse HEAD`
    popd

    echo "Creating version info $file"
    if [ $tag == "N/A" ]; then
        echo "- No tags on the current commit" >> $file
    else
        echo "- Release: [$tag]($github_url/releases/$tag)" >> $file
    fi
    echo "- Commit: $commit" >> $file

    # checksum of all the zipped artifacts
    echo "- Checksums:" >> $file
    for artifact in `ls artifacts/*.zip`; do
        checksum=$(shasum -a 1 $artifact | cut -d ' ' -f 1)

        # get zip file name without the path
        artifact=$(basename $artifact)
        echo "  - $artifact: $checksum" >> $file
    done

    echo "Version info $file"
    cat $file
}

platforms=(
    "iOS"
    "iOS Simulator"
)

update_package_swift "$source/Package.swift"

for platform in "${platforms[@]}"; do
    build $target "$platform"
done

package $target "${platforms[@]}"
compress $target
create_version_info "artifacts/release_notes.md"
