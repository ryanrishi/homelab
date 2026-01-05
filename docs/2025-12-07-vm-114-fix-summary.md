# VM 114 Fix Summary

## Issue Description
VM 114 failed to boot after RAM upgrade with UEFI shell errors and subsequently had broken QEMU guest agent functionality.

## Root Cause
1. **Missing EFI disk**: VM was configured for UEFI boot (`bios: ovmf`) but lacked the required EFI disk file
2. **Invalid storage reference**: VM configuration referenced non-existent `local-lvm` storage pool
3. **Guest agent PATH limitation**: QEMU guest agent runs with limited environment that doesn't include `/usr/bin` in PATH

## Fixes Applied

### 1. EFI Disk Recreation
```bash
# Deleted old broken EFI disk reference
ssh root@192.168.4.200 '/usr/sbin/qm set 114 -delete efidisk0'

# Created new EFI disk on local storage
ssh root@192.168.4.200 '/usr/sbin/qm set 114 -efidisk0 local:0,efitype=4m'
```

### 2. Storage Reference Correction
```bash
# Updated main disk to use correct storage pool and LVM path
ssh root@192.168.4.200 '/usr/sbin/qm set 114 -scsi0 /dev/pve/vm-114-disk-0,size=20G'

# Updated cloud-init to use local storage
ssh root@192.168.4.200 '/usr/sbin/qm set 114 -ide3 local:cloudinit'
```

### 3. Network Configuration
```bash
# Added static IP configuration for proper network connectivity
ssh root@192.168.4.200 '/usr/sbin/qm set 114 -ipconfig0 ip=192.168.4.219/24,gw=192.168.4.1'
```

### 4. Guest Agent Fix
**Issue**: Commands like `cat`, `hostname`, `ip` failed with "No such file or directory"
**Solution**: Use full paths when executing commands through guest agent

**Working examples**:
```bash
# Instead of: qm guest exec 114 -- cat /etc/hostname
ssh root@192.168.4.200 '/usr/sbin/qm guest exec 114 -- /usr/bin/cat /etc/hostname'

# Instead of: qm guest exec 114 -- ip addr
ssh root@192.168.4.200 '/usr/sbin/qm guest exec 114 -- /usr/bin/ip addr show'
```

## Validation Steps
1. ✅ VM boots successfully to login prompt
2. ✅ Network connectivity working (ping 192.168.4.219)
3. ✅ SSH access works as `ryan@192.168.4.219` 
4. ✅ Guest agent responds to commands with full paths
5. ✅ Hostname shows as `k3s-server-1`
6. ✅ IP configuration correct (192.168.4.219/24)

## Files Created/Modified
- `/var/lib/vz/images/114/vm-114-disk-1.raw` (new EFI disk)
- VM 114 configuration updated in Proxmox

## Next Steps for VM 115/120
Apply the same fixes:
1. Recreate EFI disks if missing
2. Update storage references from `local-lvm` to correct paths
3. Add static IP configurations if needed
4. Test guest agent functionality with full paths
5. Verify network connectivity and SSH access

## Key Lesson
QEMU guest agent has limited PATH environment. Always use full paths like `/usr/bin/command` when executing commands through `qm guest exec`.