# Proxmox Cluster Troubleshooting Guide

## Overview

This document chronicles the troubleshooting process for a persistent Proxmox cluster issue that manifested as filesystem hangs, web UI timeouts, and VM configuration losses. The root cause was identified as corosync network communication problems causing cluster filesystem instability.

## Initial Symptoms

- **Web UI timeouts**: Proxmox web interface at https://192.168.4.200:8006 became inaccessible
- **SSH key addition failures**: `vi ~/.ssh/authorized_keys` would hang and drop SSH sessions
- **Cluster filesystem hangs**: Operations on `/etc/pve/` would timeout
- **VM configurations missing**: All VMs disappeared from Proxmox UI despite running processes

## Environment Details

- **Hardware**: Intel NUC (ryanrishi) + Lenovo ThinkCentre M720s (pve001)
- **Network**: UniFi Dream Machine with both nodes on same subnet
- **Cluster**: 2-node Proxmox cluster named "nyc"
- **Storage**: NVMe primary storage, cluster using corosync for communication

## Root Cause Analysis

### Initial Hardware Suspicion

Early diagnostics revealed PCIe/NVMe errors in kernel logs:
```
nvme 0000:02:00.0: PCIe Bus Error: severity=Correctable, type=Physical Layer, (Receiver ID)
nvme 0000:02:00.0:   device [15b7:5006] error status/mask=00000001/0000e000
nvme 0000:02:00.0:    [ 0] RxErr                  (First)
```

**However**, testing revealed this was **NOT** the primary issue:
- ✅ Local filesystem writes worked perfectly (1.1 GB/s performance)
- ✅ SMART data showed healthy drive status
- ❌ Only cluster filesystem (`/etc/pve/`) operations hung

### True Root Cause: Network Communication Issues

The real culprit was **corosync network instability**:

```bash
# Corosync logs showed constant retransmit storms
journalctl -u corosync -f
[TOTEM] Retransmit List: fd fe 103 105 10d 117 11d 11e 124 12d 133 136
[TOTEM] Retransmit List: fd fe 103 105 10d 117 11d 11e 124 12d 133 137
```

**Network diagnostics revealed**:
```bash
# 84% packet loss to router during mtr test
mtr --report --report-cycles=50 192.168.4.201
HOST: ryanrishi           Loss%   Snt   Last   Avg  Best  Wrst StDev
1.|-- 192.168.4.1        84.0%    50    0.1   0.2   0.1   0.5   0.1
2.|-- pve001              2.0%    50    1.7   1.5   0.4   2.1   0.4
```

## How Cluster Filesystem Works

Understanding **pmxcfs** (Proxmox cluster filesystem) is crucial:

1. **Distributed filesystem**: `/etc/pve/` is shared across all cluster nodes
2. **Write consistency**: All writes must be replicated to maintain cluster state
3. **Network dependency**: Requires reliable corosync communication
4. **Failure protection**: Blocks writes when cluster communication is unreliable

**Why network issues cause filesystem hangs**:
- Corosync can't get acknowledgments for distributed locks
- pmxcfs blocks writes to prevent data corruption
- Reads may work (cached) but writes hang indefinitely

## Resolution Steps

### 1. Tuned Corosync Network Tolerance

Modified `/etc/pve/corosync.conf` to be more tolerant of network latency:

```toml
totem {
  cluster_name: nyc
  config_version: 6
  interface {
    linknumber: 0
  }
  ip_version: ipv4-6
  link_mode: passive
  secauth: on
  version: 2
  token: 5000              # Increased from 3000ms
  token_retransmit: 1000   # Increased from 714ms  
  token_retransmits_before_loss_const: 10  # Increased from 4
  consensus: 6000          # Increased from 3600ms
  join: 100                # Added
  max_messages: 20         # Added
}
```

### 2. Cluster Database Recovery

The configuration update process required careful handling due to the chicken-and-egg problem:

```bash
# 1. Stop cluster services on both nodes
systemctl stop corosync pve-cluster

# 2. Clear persistent cluster database to force regeneration
rm -rf /var/lib/pve-cluster/config.db*

# 3. Edit local corosync config (/etc/corosync/corosync.conf)
# 4. Start services to load new config
systemctl start pve-cluster pve-cluster
```

### 3. VM Configuration Recovery

VMs continued running but Proxmox lost their configurations. Recovery involved:

1. **Document running VMs** from process list:
```bash
ps aux | grep qemu | grep -v grep > /tmp/running_vms.txt
```

2. **Extract parameters** from running processes (memory, CPU, disks, networks)

3. **Recreate config files** in `/etc/pve/qemu-server/`:
```bash
# Example: VM 108 (media server)
cat > /etc/pve/qemu-server/108.conf << 'EOF'
agent: 1
bios: ovmf
boot: order=scsi0
cores: 4
cpu: host
memory: 4096
name: media
net0: virtio=A6:4C:7B:8B:BE:B0,bridge=vmbr0
scsi0: local-lvm:vm-108-disk-0,cache=none,discard=on,size=32G
scsihw: virtio-scsi-pci
smbios1: uuid=ec1eb45b-df18-4b92-a3b5-7bc13c957371
sockets: 2
EOF
```

### 4. SSL Certificate Regeneration

SSL certificates were lost during cluster filesystem corruption:

```bash
# Regenerate node certificates
pvecm updatecerts

# Restart web services
systemctl restart pveproxy
```

## Prevention Strategies

### Network Infrastructure

1. **Monitor packet loss**: Regular `mtr` tests between cluster nodes
2. **Check switch health**: Ensure UniFi equipment is stable
3. **Cable quality**: Verify ethernet cables and connections
4. **Consider dedicated cluster network**: Separate VLAN for cluster traffic

### Corosync Configuration

1. **Use conservative timings**: Higher tolerance for network latency
2. **Consider UDP unicast**: Bypass multicast issues with `transport: udpu`
3. **Monitor retransmits**: Watch corosync logs for communication issues

### Monitoring

1. **Cluster filesystem health**:
```bash
# Test cluster filesystem accessibility
timeout 5 ls -la /etc/pve/
```

2. **Corosync status**:
```bash
# Check for retransmit storms
journalctl -u corosync -f
```

3. **Node membership**:
```bash
# Verify cluster state
pvecm status
```

## Lessons Learned

1. **Hardware isn't always the culprit**: PCIe errors were a red herring
2. **Network quality matters**: Even small packet loss affects cluster stability
3. **Cluster filesystems are fragile**: Require very reliable network communication
4. **VM processes are independent**: VMs continue running even if Proxmox management fails
5. **Corosync defaults are aggressive**: May need tuning for real-world networks

## Future Improvements

1. **Implement UDP unicast**: Eliminate multicast dependency
2. **Network monitoring**: Automated alerting on packet loss
3. **Backup VM configs**: Regular exports of VM configurations
4. **Consider single-node operation**: For small homelabs, clustering may not be worth the complexity

## Commands Reference

### Diagnostics
```bash
# Check cluster status
pvecm status

# Test network quality
mtr --report --report-cycles=50 <target-ip>

# Monitor corosync
journalctl -u corosync -f

# Test cluster filesystem
timeout 5 ls -la /etc/pve/

# Check running VMs
ps aux | grep qemu | grep -v grep
qm list
```

### Recovery
```bash
# Restart cluster services
systemctl restart corosync pve-cluster pvedaemon pveproxy

# Regenerate certificates
pvecm updatecerts

# Force cluster filesystem restart
systemctl stop pve-cluster
pkill -9 pmxcfs
umount -l /etc/pve
systemctl start pve-cluster
```

---

*Document created: August 2025*  
*Cluster: nyc (ryanrishi + pve001)*  
*Author: Claude Code troubleshooting session*