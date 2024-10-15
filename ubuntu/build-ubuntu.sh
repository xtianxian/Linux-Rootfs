#!/bin/bash
set -e

# Check if debootstrap is installed; if not, install necessary tools
if ! command -v debootstrap &> /dev/null; then
    echo "debootstrap not found. Installing necessary tools..."
    sudo apt update && sudo apt install debootstrap qemu-user-static binfmt-support tar gzip -y
fi

# Get the directory where the script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Define architectures (debootstrap naming)
ARCHS=("arm64" "armhf" "amd64" "i386")  # Using debootstrap naming

# Define Ubuntu version mapping (version number -> code name)
declare -A UBUNTU_VERSION_MAP
UBUNTU_VERSION_MAP=(
    ["14.04"]="trusty"     # Ubuntu 14.04 LTS (Trusty Tahr)
    ["16.04"]="xenial"     # Ubuntu 16.04 LTS (Xenial Xerus)
    ["18.04"]="bionic"     # Ubuntu 18.04 LTS (Bionic Beaver)
    ["20.04"]="focal"      # Ubuntu 20.04 LTS (Focal Fossa)
    ["22.04"]="jammy"      # Ubuntu 22.04 LTS (Jammy Jellyfish)
    ["24.04"]="noble"      # Ubuntu 24.04 LTS (Noble Numbat)
)

# URLs for the shared libraries
declare -A SELINUX_LIBS
SELINUX_LIBS["x86"]="https://github.com/CypherpunkArmory/UserLAnd-Assets-Debian/raw/master/assets/x86/libdisableselinux.so"
SELINUX_LIBS["x86_64"]="https://github.com/CypherpunkArmory/UserLAnd-Assets-Debian/raw/master/assets/x86_64/libdisableselinux.so"
SELINUX_LIBS["arm"]="https://github.com/CypherpunkArmory/UserLAnd-Assets-Debian/raw/master/assets/arm/libdisableselinux.so"
SELINUX_LIBS["arm64"]="https://github.com/CypherpunkArmory/UserLAnd-Assets-Debian/raw/master/assets/arm64/libdisableselinux.so"

enable_qemu() {
    local arch=$1  # Pass ARCH as an argument
    if [[ $arch == "arm64" ]]; then
        echo "Enabling QEMU for arm64..."
        sudo update-binfmts --enable qemu-aarch64
    elif [[ $arch == "armhf" ]]; then
        echo "Enabling QEMU for armhf..."
        sudo update-binfmts --enable qemu-arm
    fi
}

disable_qemu() {
    local arch=$1  # Pass ARCH as an argument
    if [[ $arch == "arm64" ]]; then
        echo "Disabling QEMU for arm64..."
        sudo update-binfmts --disable qemu-aarch64
    elif [[ $arch == "armhf" ]]; then
        echo "Disabling QEMU for armhf..."
        sudo update-binfmts --disable qemu-arm
    fi
}

# Function to add libdisableselinux.so to /usr/lib and update /etc/ld.so.preload
add_libdisableselinux() {
    local arch=$1  # Architecture
    local rootfs_dir=$2  # Root filesystem directory

    # Determine the URL based on architecture
    case $arch in
        "amd64")
            lib_url="${SELINUX_LIBS["x86_64"]}"
            ;;
        "i386")
            lib_url="${SELINUX_LIBS["x86"]}"
            ;;
        "armhf")
            lib_url="${SELINUX_LIBS["arm"]}"
            ;;
        "arm64")
            lib_url="${SELINUX_LIBS["arm64"]}"
            ;;
        *)
            echo "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    # Download the libdisableselinux.so and place it in /usr/lib
    echo "Downloading libdisableselinux.so for $arch..."
    wget -q -O $rootfs_dir/usr/lib/libdisableselinux.so $lib_url

    # Add the library path to /etc/ld.so.preload
    echo "Adding libdisableselinux.so to /etc/ld.so.preload..."
    sudo tee $rootfs_dir/etc/ld.so.preload > /dev/null <<EOF
/usr/lib/libdisableselinux.so
EOF
}

# Loop over each Ubuntu version and ARCH to create rootfs
for UBUNTU_VERSION in "${!UBUNTU_VERSION_MAP[@]}"; do
    CODE_NAME=${UBUNTU_VERSION_MAP[$UBUNTU_VERSION]}

    for ARCH in "${ARCHS[@]}"; do

        # Set rootfs directory and tarball name (structured folders by version number and ARCH)
        ROOTFS_DIR="$SCRIPT_DIR/$UBUNTU_VERSION/$ARCH/rootfs"
        TARBALL_NAME="$SCRIPT_DIR/$UBUNTU_VERSION/$ARCH/ubuntu-${UBUNTU_VERSION}-${ARCH}-rootfs.tar.gz"  # Output tarball updated to tar.gz
        MD5_FILE="$TARBALL_NAME.md5"  # MD5 file name

        # Set the correct repository URL based on architecture
        if [[ $ARCH == "arm64" || $ARCH == "armhf" ]]; then
            REPO_URL="http://ports.ubuntu.com/ubuntu-ports/"
        else
            REPO_URL="http://archive.ubuntu.com/ubuntu/"
        fi

        echo "Building rootfs for Ubuntu $UBUNTU_VERSION ($CODE_NAME) on $ARCH..."

        # Enable QEMU only for ARM architectures (needed for arm64 and armhf on x86 host)
        if [[ $ARCH == "arm64" || $ARCH == "armhf" ]]; then
            enable_qemu $ARCH
        fi

        # Step 1: Create rootfs directory
        echo "Creating rootfs directory at $ROOTFS_DIR"
        mkdir -p $ROOTFS_DIR  # Ensure the rootfs directory is created

        # Step 2: Use debootstrap to create the base system with necessary packages
        echo "Bootstrapping Ubuntu $UBUNTU_VERSION ($ARCH) with necessary packages..."
        sudo debootstrap --arch=$ARCH --foreign --components=main,universe,multiverse --variant=minbase --include=apt,apt-utils,sudo,dbus,dbus-x11,wget,curl,vim,net-tools,lsb-release,locales,tzdata,passwd,bash-completion,command-not-found $CODE_NAME $ROOTFS_DIR $REPO_URL

        # Check if debootstrap command was successful
        if [ $? -ne 0 ]; then
            echo "Debootstrap failed for $UBUNTU_VERSION ($ARCH). Exiting."
            if [[ $ARCH == "arm64" || $ARCH == "armhf" ]]; then
                disable_qemu $ARCH
            fi
            exit 1
        fi

        # Step 3: Copy the correct QEMU static binary for ARM emulation (only for ARM architectures)
        if [[ $ARCH == "arm64" ]]; then
            if [ -f /usr/bin/qemu-aarch64-static ]; then
                echo "Copying qemu-aarch64-static for ARM64 emulation..."
                sudo cp /usr/bin/qemu-aarch64-static $ROOTFS_DIR/usr/bin/
            else
                echo "qemu-aarch64-static not found!"
            fi
        elif [[ $ARCH == "armhf" ]]; then
            if [ -f /usr/bin/qemu-arm-static ]; then
                echo "Copying qemu-arm-static for ARMHF emulation..."
                sudo cp /usr/bin/qemu-arm-static $ROOTFS_DIR/usr/bin/
            else
                echo "qemu-arm-static not found!"
            fi
        else
            echo "No QEMU needed for architecture $ARCH"
        fi

        # Step 4: Finish the second stage of debootstrap inside the chroot
        echo "Running the second stage of debootstrap..."
        sudo chroot $ROOTFS_DIR /debootstrap/debootstrap --second-stage

        if [ $? -ne 0 ]; then
            echo "Debootstrap second stage failed for $UBUNTU_VERSION ($ARCH). Exiting."
            if [[ $ARCH == "arm64" || $ARCH == "armhf" ]]; then
                disable_qemu $ARCH
            fi
            exit 1
        fi

        # Step 5: Configure locales (system-wide)
        echo "Configuring locales in the rootfs..."
        sudo tee $ROOTFS_DIR/etc/locale.gen > /dev/null <<EOF
en_US.UTF-8 UTF-8
EOF
        sudo chroot $ROOTFS_DIR /usr/bin/env DEBIAN_FRONTEND=noninteractive locale-gen en_US.UTF-8
        sudo chroot $ROOTFS_DIR /usr/bin/env DEBIAN_FRONTEND=noninteractive update-locale LANG=en_US.UTF-8
        sudo chroot $ROOTFS_DIR /usr/bin/env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales

        # Step 6: Set user-specific locale by adding to .profile (including root)
        echo "Configuring user-specific locales in .profile"
        PROFILE_PATH="$ROOTFS_DIR/root/.profile"
        if [ ! -f $PROFILE_PATH ]; then
            echo "Creating .profile for root..."
            sudo touch $PROFILE_PATH
        fi

        sudo tee -a $PROFILE_PATH > /dev/null <<EOF

# Set user-specific locale for root
export PS1='\[\e[32m\]\u@\h:\[\e[34m\]\w\[\e[0m\]# '
export TERM=xterm-256color
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export HOME=/root
export USER=root
EOF

        # Step 7: Create necessary files in the rootfs after the second stage
        echo "Creating necessary directories..."
        sudo mkdir -p $ROOTFS_DIR/etc/network
        sudo mkdir -p $ROOTFS_DIR/etc/apt

        # Create /etc/apt/sources.list
        echo "Creating /etc/apt/sources.list in the rootfs..."
        sudo tee $ROOTFS_DIR/etc/apt/sources.list > /dev/null <<EOF
deb $REPO_URL $CODE_NAME main universe multiverse
deb $REPO_URL $CODE_NAME-updates main universe multiverse
deb $REPO_URL $CODE_NAME-security main universe multiverse
EOF

        # Add the prepared bash.bashrc file (located beside the script)
        PREPARED_BASHRC="$SCRIPT_DIR/bash.bashrc"

        if [ -f "$PREPARED_BASHRC" ]; then
            echo "Copying prepared bash.bashrc to $ROOTFS_DIR/etc/bash.bashrc..."
            sudo cp "$PREPARED_BASHRC" "$ROOTFS_DIR/etc/bash.bashrc"
            sudo chmod 644 "$ROOTFS_DIR/etc/bash.bashrc"  # Set proper permissions
        else
            echo "Prepared bash.bashrc file not found at $PREPARED_BASHRC. Exiting."
            exit 1
        fi

        # Create /etc/fstab
        echo "Creating /etc/fstab in the rootfs..."
        sudo tee $ROOTFS_DIR/etc/fstab > /dev/null <<EOF
proc            /proc           proc    defaults          0       0
sysfs           /sys            sysfs   defaults          0       0
devpts          /dev/pts        devpts  defaults          0       0
EOF

        # Create /etc/network/interfaces
        echo "Creating /etc/network/interfaces in the rootfs..."
        sudo tee $ROOTFS_DIR/etc/network/interfaces > /dev/null <<EOF
auto lo
iface lo inet loopback

allow-hotplug *
iface * inet dhcp
EOF

        # Create /etc/resolv.conf for DNS (Google and Cloudflare DNS)
        echo "Creating /etc/resolv.conf in the rootfs..."
        sudo tee $ROOTFS_DIR/etc/resolv.conf > /dev/null <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

        # Step 8: Add custom PS1 prompt and invoke motd in bashrc
        echo "Configuring .bashrc with custom prompt and enabling motd..."

        # Add custom PS1 prompt and call motd
        sudo tee -a $ROOTFS_DIR/root/.bashrc > /dev/null <<EOF

# Execute motd
run-parts /etc/update-motd.d
echo   # Add a new line after motd output
EOF

        # Always add libdisableselinux.so to /etc/ld.so.preload for all Ubuntu versions
        echo "Adding libdisableselinux.so for $UBUNTU_VERSION ($ARCH)..."
        add_libdisableselinux $ARCH $ROOTFS_DIR

        # Step 9: Cleanup

        # Remove apt cache
        sudo rm -rf $ROOTFS_DIR/var/lib/apt/lists/*
        sudo rm -rf $ROOTFS_DIR/var/cache/apt/archives/*

        # Remove temporary files
        sudo rm -rf $ROOTFS_DIR/tmp/*
        sudo rm -rf $ROOTFS_DIR/var/tmp/*

        # Remove log files
        sudo rm -rf $ROOTFS_DIR/var/log/*

        # Remove SSH keys (if any)
        sudo rm -f $ROOTFS_DIR/etc/ssh/ssh_host_*

        # Remove bash history
        sudo rm -f $ROOTFS_DIR/root/.bash_history
        sudo rm -f $ROOTFS_DIR/home/*/.bash_history

        # Cleanup: Remove QEMU static binaries from the rootfs after the second stage
        if [[ $ARCH == "arm64" ]]; then
            echo "Removing qemu-aarch64-static from $ROOTFS_DIR/usr/bin/..."
            sudo rm -f $ROOTFS_DIR/usr/bin/qemu-aarch64-static
        elif [[ $ARCH == "armhf" ]]; then
            echo "Removing qemu-arm-static from $ROOTFS_DIR/usr/bin/..."
            sudo rm -f $ROOTFS_DIR/usr/bin/qemu-arm-static
        fi

        # Step 10: Packaging the rootfs into a tar.gz archive...
        echo "Packaging the rootfs into a tar.gz archive..."
        pushd $ROOTFS_DIR > /dev/null
        sudo tar --numeric-owner -czf $TARBALL_NAME .
        popd > /dev/null

        # Step 11: Generate MD5 checksum for the tar.gz archive
        echo "Generating MD5 checksum for $TARBALL_NAME"
        pushd $(dirname $TARBALL_NAME) > /dev/null
        md5sum $(basename $TARBALL_NAME) | sudo tee $(basename $MD5_FILE)
        popd > /dev/null

        # Remove the rootfs folder after packaging to save space
        sudo rm -rf $ROOTFS_DIR

        # Final Cleanup
        if [[ $ARCH == "arm64" || $ARCH == "armhf" ]]; then
            disable_qemu $ARCH
        fi

        echo "Ubuntu $UBUNTU_VERSION ($ARCH) Rootfs with apt, dbus, and dbus-x11 is ready and packaged as $TARBALL_NAME!"
        echo "MD5 checksum is available in $MD5_FILE"

    done
done
