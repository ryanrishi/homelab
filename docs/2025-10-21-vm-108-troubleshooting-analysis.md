# VM 108 Troubleshooting Analysis

## Problem Summary
VM 108 was stuck at UEFI prompt and couldn't boot despite having disk storage configured. The error `TASK ERROR: volume 'local:108/vm-108-disk-1.raw' does not exist` was encountered, and after removing hard disks, the VM started but had no bootable disk attached.

## Root Cause Analysis

### Initial Investigation
- VM 108 configuration showed disks marked as "unused"
- Multiple disk images with conflicting formats (.raw vs .qcow2)
- All disk images were nearly empty (4KB - 5.2MB used out of 32GB)

### Key Discovery
By comparing working VMs (109 and 111), found that:
1. **Working VMs used LVM storage** (`/dev/pve/vm-XXX-disk-0`) instead of file-based storage
2. **VM 108 had an LVM volume** (`/dev/pve/vm-108-disk-0`) with actual data (16GB, 99.25% full)
3. **VM was misconfigured** to boot from empty qcow2 files instead of the LVM volume

## Configuration Comparison

### Working VMs (109, 111)
```
scsi0: local-lvm:vm-XXX-disk-0,cache=none,discard=on,size=20G
efidisk0: local:XXX/vm-XXX-disk-1.raw,efitype=4m,size=128K
ide2: none,media=cdrom
```

### VM 108 (Before Fix)
```
scsi0: local:108/vm-108-disk-2.qcow2,size=32G
efidisk0: local:108/vm-108-disk-3.raw,size=128K
ide2: local:108/vm-108-cloudinit.qcow2,media=cdrom
```

### VM 108 (After Fix)
```
scsi0: /dev/pve/vm-108-disk-0,size=16G
efidisk0: local:108/vm-108-disk-0.raw,efitype=4m,size=528K
ide2: none,media=cdrom
```

## Storage Analysis

### Proxmox Cluster Configuration
- 2-node cluster ("nyc")
- Nodes: 192.168.4.200 (local), 192.168.4.201
- Available storage: `local` (dir), `snippets` (dir)
- Missing: `local-lvm` storage backend (used by working VMs)

### LVM Volumes Found
```bash
# Working VMs
/dev/pve/vm-109-disk-0  # 20GB
/dev/pve/vm-111-disk-0  # 20GB

# VM 108 (the missing data!)
/dev/pve/vm-108-disk-0     # 16GB, 99.25% full ✓
/dev/pve/vm-108-cloudinit  # 4MB
```

### File-based Storage (Nearly Empty)
```bash
vm-108-disk-0.raw      # 4KB used (empty)
vm-108-disk-1.qcow2    # 5.2MB used (nearly empty)
vm-108-disk-2.qcow2    # 5.2MB used (copy of disk-1)
vm-108-cloudinit.qcow2 # 4.4MB (cloud-init)
vm-108-disk-3.raw      # 128KB (EFI disk)
```

## Resolution Steps

### 1. Cleanup Phase
- Stopped VM 108
- Removed unused disk references from VM configuration
- Deleted empty/nearly empty disk images:
  - `vm-108-disk-0.raw` (4KB)
  - `vm-108-disk-1.qcow2` (5.2MB)

### 2. Configuration Fix
- **Boot Disk**: Changed from `local:108/vm-108-disk-2.qcow2` to `/dev/pve/vm-108-disk-0`
- **EFI Disk**: Added missing `efitype=4m` parameter and recreated with proper size
- **Cloud-init**: Removed to match working VM configuration (`ide2: none,media=cdrom`)

### 3. Final Configuration
```bash
qm config 108
agent: 1
bios: ovmf
boot: order=scsi0;ide2
cores: 4
cpu: host
description:  VM 108 (media) - recreated from running process
efidisk0: local:108/vm-108-disk-0.raw,efitype=4m,size=528K
hostpci0: 0000:00:02.0,pcie=1
ide2: none,media=cdrom
machine: q35
memory: 4096
name: media
net0: virtio=A6:4C:7B:8B:BE:B0,bridge=vmbr0
numa: 0
ostype: l26
scsi0: /dev/pve/vm-108-disk-0,size=16G
scsihw: virtio-scsi-pci
smbios1: uuid=ec1eb45b-df18-4b92-a3b5-7bc13c957371
sockets: 2
tablet: 1
unused0: local:108/vm-108-disk-2.qcow2
vmgenid: 6398a6f0-109b-40cc-a4cb-d339e7dcba79
```

## Lessons Learned

### 1. Storage Backend Importance
- File-based storage (`local`) vs LVM storage have different management patterns
- LVM volumes may exist even when storage backend configuration is missing
- Always check for existing LVM volumes: `find /dev -name '*vm-XXX*'`

### 2. Configuration Drift
- VM configurations can drift from their actual storage
- Compare working VMs to identify configuration patterns
- Check `lvs | grep vm-XXX` to find actual data locations

### 3. EFI Configuration
- UEFI VMs require proper EFI disk configuration
- Missing `efitype=4m` parameter can cause boot failures
- EFI disk size matters (528K with 4m type vs 128K default)

### 4. Cloud-init Compatibility
- Cloud-init may not be necessary for all VM types
- Removing cloud-init can resolve boot issues in some cases
- Match configuration to working reference VMs

## Tools and Commands Used

### Investigation
```bash
# VM configuration
qm config <vmid>
qm status <vmid>

# Storage analysis
pvesm status
pvesm list local
ls -lh /var/lib/vz/images/<vmid>/
qemu-img info <disk-file>

# LVM discovery
find /dev -name '*vm-XXX*'
lvs | grep vm-XXX

# Cluster info
pvecm status
cat /etc/pve/storage.cfg
```

### Resolution
```bash
# VM management
qm stop <vmid>
qm start <vmid>
qm set <vmid> --option value

# Disk management
qm importdisk <vmid> <disk-file> <storage>
qm set <vmid> --delete <option>
rm <disk-file>
```

## Result
VM 108 now boots successfully from the LVM volume containing the actual OS data instead of being stuck at the UEFI prompt.