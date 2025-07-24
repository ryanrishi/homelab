#!/bin/bash
#
# create-debian-template.sh
# Creates a Debian cloud-init template for Terraform automation
#
# Usage: ./create-debian-template.sh [11|12]
# Default: Debian 12
#

set -euo pipefail

# Configuration
DEBIAN_VERSION=${1:-12}
VM_ID=9000
TEMPLATE_NAME="debian-${DEBIAN_VERSION}-cloudinit-template"
MEMORY=1024
CORES=1
DISK_SIZE="8G"

# Debian cloud image URLs
if [[ "$DEBIAN_VERSION" == "11" ]]; then
    IMAGE_URL="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
    IMAGE_FILE="debian-11-generic-amd64.qcow2"
elif [[ "$DEBIAN_VERSION" == "12" ]]; then
    IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
    IMAGE_FILE="debian-12-generic-amd64.qcow2"
else
    echo "Error: Unsupported Debian version. Use 11 or 12."
    exit 1
fi

echo "=== Creating Debian ${DEBIAN_VERSION} Cloud-Init Template ==="
echo "VM ID: ${VM_ID}"
echo "Template Name: ${TEMPLATE_NAME}"
echo "Image URL: ${IMAGE_URL}"
echo

# Check if VM ID already exists
if qm status ${VM_ID} >/dev/null 2>&1; then
    echo "Error: VM ${VM_ID} already exists. Please destroy it first:"
    echo "  qm destroy ${VM_ID}"
    exit 1
fi

# Download Debian cloud image
echo "Downloading Debian ${DEBIAN_VERSION} cloud image..."
if [[ ! -f "$IMAGE_FILE" ]]; then
    wget -q --show-progress "$IMAGE_URL"
else
    echo "Image already exists, skipping download."
fi

# Create VM
echo "Creating VM ${VM_ID}..."
qm create ${VM_ID} \
  --name "${TEMPLATE_NAME}" \
  --memory ${MEMORY} \
  --cores ${CORES} \
  --net0 virtio,bridge=vmbr0 \
  --scsi0 local-lvm:0,import-from="$(pwd)/${IMAGE_FILE}" \
  --ide2 local-lvm:cloudinit \
  --boot order=scsi0 \
  --serial0 socket \
  --agent enabled=1 \
  --ostype l26

# Resize disk
echo "Resizing disk to ${DISK_SIZE}..."
qm disk resize ${VM_ID} scsi0 ${DISK_SIZE}

# Set cloud-init defaults
echo "Configuring cloud-init defaults..."
qm set ${VM_ID} --ciuser root
qm set ${VM_ID} --cipassword password
qm set ${VM_ID} --sshkeys ~/.ssh/authorized_keys || echo "Warning: No SSH keys found"
qm set ${VM_ID} --ipconfig0 ip=dhcp

# Convert to template
echo "Converting VM to template..."
qm template ${VM_ID}

# Cleanup
echo "Cleaning up..."
rm -f "${IMAGE_FILE}"

echo
echo "=== Template Creation Complete ==="
echo "Template ID: ${VM_ID}"
echo "Template Name: ${TEMPLATE_NAME}"
echo
echo "Update your Terraform configuration to use:"
echo "  cloud_init_template_name = \"${TEMPLATE_NAME}\""
echo
echo "Next steps:"
echo "1. Create terraform user: pveum user add terraform@pam"
echo "2. Set terraform password: pveum passwd terraform@pam"
echo "3. Assign permissions: pveum aclmod / -user terraform@pam -role PVEVMAdmin"
echo "4. Test with: terraform plan"