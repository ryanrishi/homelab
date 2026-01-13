#!/bin/bash
#
# create-debian-template.sh
# Creates a Debian cloud-init template for Terraform automation
#
# Usage: ./create-debian-template.sh [11|12|13] [VMID]
# Defaults: Debian 12, VMID 9000
#

set -euo pipefail

# Configuration
# Inputs
DEBIAN_VERSION=${1:-12}
VM_ID=${2:-9000}
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
elif [[ "$DEBIAN_VERSION" == "13" ]]; then
    IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
    IMAGE_FILE="debian-13-generic-amd64.qcow2"
else
    echo "Error: Unsupported Debian version. Use 11, 12, or 13."
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

# Create VM (OVMF/UEFI with persistent efivars)
echo "Creating VM ${VM_ID} (OVMF/UEFI)..."
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
  --ostype l26 \
  --bios ovmf \
  --efidisk0 local-lvm:0,efitype=4m

# Resize disk
echo "Resizing disk to ${DISK_SIZE}..."
qm disk resize ${VM_ID} scsi0 ${DISK_SIZE}

# Set minimal cloud-init defaults (accounts/keys provided at clone time via Terraform)
echo "Configuring cloud-init defaults..."
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
