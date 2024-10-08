import os
import json

# Set your base directory here
BASE_DIR = os.getcwd()
BASE_URL = "https://raw.githubusercontent.com/xtianxian/Linux-Rootfs/refs/heads/main"

# List of valid ABIS (valid architectures)
VALID_ABIS = ["arm64", "armhf", "amd64", "i386", "x86", "x86_64", "aarch64"]

# Define Ubuntu version mapping with full codenames
UBUNTU_VERSION_MAP = {
    "14.04": "Trusty Tahr",
    "16.04": "Xenial Xerus",
    "18.04": "Bionic Beaver",
    "20.04": "Focal Fossa",
    "22.04": "Jammy Jellyfish",
    "24.04": "Noble Numbat"
}

# Function to get the file size in bytes (compressed size)
def get_file_size(file_path):
    return os.path.getsize(file_path)

# Function to create the relative URL for a given file
def get_relative_url(version, arch, file_name, os_type):
    return f"{BASE_URL}/{os_type}/{version}/{arch}/{file_name}"

# Function to read the MD5 checksum from the .md5 file
def get_md5_checksum(md5_file_path):
    try:
        with open(md5_file_path, "r") as md5_file:
            md5_checksum = md5_file.read().strip().split()[0]  # Only read the checksum
        return md5_checksum
    except Exception as e:
        print(f"Error reading MD5 file {md5_file_path}: {e}")
        return None

# Initialize an empty dictionary to store the rootfs data
rootfs_metadata = {"distributions": []}

# Loop through OS types (alpine, ubuntu)
for os_type in ["alpine", "ubuntu"]:
    os_type_path = os.path.join(BASE_DIR, os_type)
    if os.path.exists(os_type_path):
        os_data = {
            "name": os_type.capitalize(),  # Set the OS name
            "versions": {}
        }

        # Loop through all versions (directories), sorted in descending order
        for version in sorted(os.listdir(os_type_path), reverse=True):
            version_path = os.path.join(os_type_path, version)
            if os.path.isdir(version_path):
                version_data = {}

                # Add the codename: for Ubuntu we use the full codenames, for Alpine we concatenate the version
                if os_type == "ubuntu":
                    codename = UBUNTU_VERSION_MAP.get(version, "").title()
                else:
                    codename = f"{os_type.capitalize()}-{version}"

                version_data["codename"] = codename
                version_data["architectures"] = {}
                has_valid_arch = False  # Flag to check if there's a valid architecture

                # Loop through all architectures (directories inside version), sorted alphabetically
                for arch in sorted(os.listdir(version_path)):
                    if arch not in VALID_ABIS:
                        continue  # Skip directories that are not valid ABIs

                    arch_path = os.path.join(version_path, arch)
                    if os.path.isdir(arch_path):
                        arch_data = {}

                        # Find the rootfs tar.gz file
                        for file_name in os.listdir(arch_path):
                            if file_name.endswith("-rootfs.tar.gz"):  # Reverting to .tar.gz
                                file_path = os.path.join(arch_path, file_name)

                                # Get the corresponding MD5 file path and its checksum
                                md5_file_name = f"{file_name}.md5"
                                md5_file_path = os.path.join(arch_path, md5_file_name)
                                md5_checksum = get_md5_checksum(md5_file_path)
                                
                                if md5_checksum is not None:  # Only add valid files
                                    # Add file, download_size, url, and md5 to the JSON structure
                                    arch_data = {
                                        "file_name": file_name,
                                        "download_size": get_file_size(file_path),
                                        "download_url": get_relative_url(version, arch, file_name, os_type),
                                        "md5_checksum": md5_checksum  # Storing MD5 checksum directly
                                    }
                                    version_data["architectures"][arch] = arch_data
                                    has_valid_arch = True  # Found a valid architecture

                if has_valid_arch:
                    os_data["versions"][version] = version_data

        rootfs_metadata["distributions"].append(os_data)

# Save the data to a JSON file
with open("rootfs_metadata.json", "w") as json_file:
    json.dump(rootfs_metadata, json_file, indent=4)

print("JSON data with download sizes and MD5 checksums successfully generated.")
