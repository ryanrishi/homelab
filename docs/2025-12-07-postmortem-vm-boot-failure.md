# Postmortem: VM Boot Failure After RAM Upgrade

**Date**: December 7, 2025  
**Duration**: ~2 hours  
**Impact**: Complete outage of homelab k3s cluster and services  
**Root Cause**: Missing EFI disk files and invalid storage references after infrastructure changes  

## Executive Summary

On December 7, 2025, a routine RAM upgrade (16GB → 32GB) on our primary homelab server resulted in a complete failure of all virtual machines to boot. This cascaded into a full outage of our Kubernetes cluster, including critical services like PiHole (DNS), which affected internet connectivity for the entire home network.

The incident was caused by missing UEFI boot files and invalid storage configuration references that were exposed when VMs attempted to restart after the hardware upgrade. While the immediate trigger was the RAM upgrade requiring a reboot, the underlying issue stemmed from storage configuration drift that occurred during previous cluster expansion activities.

**Key Lessons**: Infrastructure configuration drift can remain hidden until system restarts expose missing dependencies. Regular validation of VM configurations and automated testing of disaster recovery procedures would have prevented this extended outage.

## Timeline (All times EST)

| Time | Event |
|------|-------|
| 16:30 | Planned shutdown of pve001 (secondary Proxmox node) |
| 16:35 | Planned shutdown of NUC (primary Proxmox node) for RAM upgrade |
| 17:00 | RAM upgrade completed, NUC powered on |
| 17:05 | **INCIDENT START**: All VMs failed to boot with storage errors |
| 17:10 | Confirmed DNS outage affecting entire home network |
| 17:15 | Investigation began: identified missing EFI disk files |
| 18:00 | Root cause analysis: storage reference configuration drift |
| 18:30 | Fix deployed: recreated EFI disks and corrected storage references |
| 18:50 | **INCIDENT END**: All VMs restored, services operational |

## Technical Details

### Infrastructure Overview

Our homelab runs on a dual-node Proxmox VE cluster:
- **Primary Node (NUC)**: Hosts 7 VMs including k3s control plane and PiHole
- **Secondary Node (pve001)**: Hosts additional k3s nodes  
- **Storage**: Local storage on each node, no shared storage

**Key VMs affected**:
- VM 116 (k3s-server-0): Kubernetes control plane + PiHole DNS
- VM 114/115 (k3s-server-1/2): Additional Kubernetes control plane nodes
- VM 120 (k3s-replica-0): Kubernetes worker node
- VM 109/111 (wireguard/ddclient): Network services

### Root Cause Analysis

**Primary Issue**: Missing EFI disk files required for UEFI boot
- VMs configured with `bios: ovmf` (UEFI mode) require EFI system partition files
- These files should exist at `/var/lib/vz/images/{VMID}/vm-{VMID}-disk-0.raw`
- Only VM 108 had its EFI disk file present; all others were missing

**Secondary Issue**: Invalid storage pool references  
- VM configurations referenced `local-lvm` storage pool
- This storage pool no longer existed on the NUC node
- Caused additional boot failures even after EFI disks were recreated

### Why This Happened

**Storage Configuration Drift**: The evidence suggests this configuration drift occurred during previous cluster expansion when pve001 was added to the cluster. Proxmox clustering can sometimes cause storage configuration changes, and it appears the `local-lvm` storage pool was either:

1. Migrated to cluster-shared storage that later became unavailable
2. Renamed/reconfigured during cluster setup  
3. Removed during storage consolidation activities

**Hidden Failure**: Because VMs don't restart frequently in a homelab environment, this misconfiguration remained hidden until the planned reboot exposed the missing dependencies.

### Impact Assessment

**Services Affected**:
- ✅ **Critical**: PiHole DNS (complete home internet outage)
- ✅ **High**: Kubernetes cluster (all applications down)  
- ✅ **Medium**: WireGuard VPN (remote access down)
- ✅ **Low**: Dynamic DNS updates (external access affected)

**Blast Radius**: Entire homelab infrastructure unusable, affecting:
- Home internet browsing (DNS resolution failure)
- Self-hosted applications and services
- Remote access capabilities
- Development and testing environments

## Technical Resolution

### Fix Applied

1. **EFI Disk Recreation**:
   ```bash
   # For each affected VM:
   mkdir -p /var/lib/vz/images/{VMID}/
   qm set {VMID} -delete efidisk0
   qm set {VMID} -efidisk0 local:0,efitype=4m
   ```

2. **Storage Reference Correction**:
   ```bash
   # Updated storage pool references from local-lvm to local
   qm set {VMID} -scsi0 local:20
   qm set {VMID} -ide3 local:cloudinit  
   ```

3. **Validation**:
   - Verified each VM could start successfully
   - Confirmed network connectivity and service functionality
   - Validated k3s cluster reformation

### Why This Fix Worked

- **EFI Disks**: Recreated the UEFI system partition files required for boot
- **Storage References**: Updated configurations to use existing `local` storage pool
- **Cloud-init**: Regenerated cloud-init ISOs for proper VM initialization

## Prevention and Monitoring

### Immediate Actions Taken
- [x] Documented storage pool configuration in infrastructure notes
- [x] Created this postmortem for future reference
- [ ] **TODO**: Implement VM configuration validation script

### Long-term Improvements Needed

1. **Configuration Monitoring**:
   - Implement automated checks for VM storage references  
   - Monitor EFI disk file presence for UEFI VMs
   - Alert on storage pool configuration changes

2. **Testing Procedures**:
   - Regular disaster recovery testing with full cluster restarts
   - Automated validation of VM configurations before changes
   - Staging environment that mirrors production storage setup

3. **Documentation**:
   - Maintain inventory of storage pools and their purposes  
   - Document VM dependencies and storage requirements
   - Create runbook for storage-related incident response

4. **Infrastructure as Code**:
   - Migrate to Terraform-managed VM configurations
   - Version control all infrastructure changes
   - Implement configuration drift detection

### Monitoring Gaps Identified

- No alerting on VM boot failures
- No validation of EFI disk file integrity  
- No monitoring of storage pool configuration changes
- Insufficient disaster recovery testing frequency

## Key Takeaways

1. **Configuration Drift is Silent**: Storage misconfigurations can remain hidden until system restarts expose them
2. **UEFI Complexity**: UEFI VMs have additional boot dependencies that must be maintained  
3. **Cascading Failures**: DNS service failure amplified the impact to the entire home network
4. **Testing Frequency**: Homelab environments need regular disaster recovery validation despite low change frequency

## Action Items

| Priority | Action | Owner | Due Date |
|----------|--------|-------|----------|
| High | Implement VM configuration validation script | Infrastructure Team | 2025-12-14 |
| High | Create disaster recovery testing schedule | Infrastructure Team | 2025-12-14 |  
| Medium | Document storage pool architecture | Infrastructure Team | 2025-12-21 |
| Medium | Research Terraform VM management | Infrastructure Team | 2025-12-28 |
| Low | Implement configuration drift monitoring | Infrastructure Team | 2026-01-15 |

---

**Incident Commander**: Claude Code  
**Contributors**: Infrastructure Team  
**Review Date**: 2025-12-14  

*This postmortem will be reviewed in one week to assess progress on action items and identify any additional lessons learned.*