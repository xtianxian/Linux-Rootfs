#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Define architectures with aligned names
ARCHS=("arm64" "armhf" "amd64" "i386")  # Aligned architecture names (amd64 for x86_64)

# Define Alpine versions and their latest minor releases
ALPINE_VERSIONS=("3.20.3" "3.19.4" "3.18.9" "3.17.10" "3.16.9")  # Latest minor releases

# Function to map architecture names to Alpine's naming scheme
map_arch_to_alpine() {
    case "$1" in
        "arm64") echo "aarch64" ;;
        "armhf") echo "armhf" ;;
        "amd64") echo "x86_64" ;;  # Map amd64 to x86_64 in Alpine's naming
        "i386") echo "x86" ;;
        *) echo "Unknown architecture: $1" && exit 1 ;;
    esac
}

# Loop over each Alpine version and architecture to download the tarball and generate md5sum
for ALPINE_VERSION in "${ALPINE_VERSIONS[@]}"; do
    for ARCH in "${ARCHS[@]}"; do

        # Map the architecture to Alpine's naming scheme
        ALPINE_ARCH=$(map_arch_to_alpine "$ARCH")

        # Set tarball name (structured folders by version number and ARCH)
        TARBALL_GZ_NAME="$SCRIPT_DIR/$ALPINE_VERSION/$ARCH/alpine-${ALPINE_VERSION}-${ARCH}-rootfs.tar.gz"  # Downloaded tarball (gzip)
        MD5_FILE="$TARBALL_GZ_NAME.md5"  # MD5 file name

        # Minirootfs download URL (with mapped architecture)
        MINIROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION:0:4}/releases/${ALPINE_ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"

        echo "Downloading Alpine $ALPINE_VERSION minirootfs for $ARCH ($ALPINE_ARCH)..."

        # Step 1: Download Alpine minirootfs tarball
        mkdir -p "$(dirname "$TARBALL_GZ_NAME")"  # Ensure the version and architecture directory is created
        wget $MINIROOTFS_URL -O $TARBALL_GZ_NAME

        # Step 2: Generate MD5 checksum for the downloaded tarball
        echo "Generating MD5 checksum for $TARBALL_GZ_NAME"
        pushd "$(dirname "$TARBALL_GZ_NAME")" > /dev/null
        md5sum "$(basename "$TARBALL_GZ_NAME")" | sudo tee "$(basename "$MD5_FILE")"
        popd > /dev/null

        echo "Alpine $ALPINE_VERSION ($ARCH) Mini Rootfs is downloaded and MD5 checksum is saved as $MD5_FILE"

        # Step 3: Remove the original tar.gz file if no longer needed
        echo "Optionally, you can remove the original .tar.gz file... (currently skipping this step)"

    done
done
