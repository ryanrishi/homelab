# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a homelab infrastructure management repository that uses three main technologies:
- **Ansible** for configuration management of VMs and services
- **Terraform** for VM provisioning on Proxmox
- **Kubernetes (k3s)** for container orchestration with Flux CD

## ⚠️ CRITICAL: Resource Constraints

**HOMELAB SETUP**: Single Intel NUC with 16GB RAM total across all k3s nodes
- **BE EXTREMELY CAREFUL** with memory limits and resource requests
- **ALWAYS CHECK** current node memory allocation before increasing limits
- **NEVER** increase memory limits without checking cluster capacity first
- **PiHole is CRITICAL** - DNS outages affect entire home network  
- Memory increases can trigger SystemOOM → MetalLB crashes → IP reassignments → DNS outages

## ⚠️ CRITICAL: PiHole DNS Stability

**PiHole provides DNS for entire home network** - outages are unacceptable!

- **NEVER drain nodes** without first checking: `kubectl get pods -n pihole -o wide`
- **If PiHole is on target node**: Move it first with node selectors/affinity
- **IP pinning configured**: PiHole services pinned to 192.168.4.253
- **During cluster changes**: Expect brief IP reassignments during MetalLB restarts
- **Emergency access**: Use `kubectl port-forward -n pihole svc/pihole-web 8080:80`

**Check PiHole status:**
```bash
kubectl get pods -n pihole
kubectl get svc -n pihole  
nslookup google.com 192.168.4.253  # Test DNS
```

**Before any resource changes:**
```bash
kubectl describe nodes | grep -A10 "Allocated resources"
kubectl top nodes
```

## Key Commands

### Ansible
```bash
# Run all playbooks
ansible-playbook site.yml

# Run specific playbook
ansible-playbook threekings.yml
ansible-playbook nyc.yml

# Run specific playbook with inventory
ansible-playbook -i inventory/threekings.yml threekings.yml

# Run k3s setup
ansible-playbook k3s-server.yml
ansible-playbook k3s-agent.yml
```

### Terraform
```bash
# Initialize Terraform
cd terraform && terraform init

# Apply infrastructure changes
terraform apply

# Plan changes
terraform plan
```

### Kubernetes
```bash
# Validate Kubernetes manifests
cd kubernetes && ./scripts/validate.sh

# Create secrets with SOPS
kubectl create secret generic --namespace $NAMESPACE --from-file values.yaml $SECRET_NAME --dry-run=client -o yaml
sops --encrypt pihole-secrets.yaml > pihole-secrets.sops.yaml

# Decrypt secrets
sops --decrypt <file>
kubectl get secret <name> -o jsonpath='{.data.values\.yaml}' | base64 -d

# Create config maps
kubectl create cm my-config --from-literal=key1=value1 --dry-run=client -o yaml
```

## Architecture

### Infrastructure Layer
- **Proxmox**: Hypervisor running on physical NUCs
- **Terraform**: Provisions VMs using cloud-init templates
- **Cloud-init**: Handles initial VM setup and Ansible bootstrap

### Configuration Management
- **Ansible**: Manages VM configuration and service deployment
- **Roles**: Organized by service type (docker-*, monitoring, networking)
- **Inventories**: Separated by location (threekings, nyc, centennial)

### Kubernetes Layer
- **k3s**: Lightweight Kubernetes distribution
- **Flux CD**: GitOps continuous delivery
- **MetalLB**: Load balancer for external IPs
- **SOPS**: Secrets management with GPG encryption

### Services
- **Monitoring**: Grafana, InfluxDB, Telegraf, Prometheus
- **Networking**: PiHole, ddclient, WireGuard
- **Media**: HTPC stack (*arr services)
- **Document management**: Paperless-ngx

## Key Files and Directories

### Ansible Structure
- `site.yml`: Main playbook that includes all services
- `group_vars/`: Host-specific variables organized by location
- `inventory/`: Ansible inventory files
- `roles/`: Service-specific Ansible roles

### Terraform Structure
- `terraform/main.tf`: VM definitions and configuration
- `terraform/modules/cloud_init/`: Cloud-init template module
- `terraform/modules/cloud_init/files/`: User data files per VM type

### Kubernetes Structure
- `kubernetes/clusters/liberty/`: Flux CD cluster configuration
- `kubernetes/apps/`: Application definitions with Helm releases
- `kubernetes/infra/`: Infrastructure components (MetalLB, NFS)
- `kubernetes/scripts/validate.sh`: Validation script for manifests

## Development Workflow

1. **Terraform changes**: Modify VM configurations in `terraform/main.tf`
2. **Ansible changes**: Update roles or playbooks, test with `ansible-playbook`
3. **Kubernetes changes**: Modify manifests, validate with `kubernetes/scripts/validate.sh`
4. **Secrets**: Use SOPS for encryption, never commit plain secrets

## Cloud-init Quirks

- Cloud-init may not run on first boot in Proxmox
- Regenerate cloud-init image in Proxmox UI and reboot if needed
- Cloud-init logs: `cloud-init collect-logs` then examine the tarball

## Terraform Infrastructure Notes

### Dual-Node Setup
- **NUC**: Media server, k3s-server-0 (cluster init), ddclient, wireguard, k3s-replica-0
- **M720s**: k3s-server-1, k3s-server-2, k3s-replica-1, k3s-replica-2, k3s-replica-3

### Provider Configuration
- `proxmox.nuc`: 192.168.4.200 (ryanrishi node)
- `proxmox.m720s`: 192.168.4.201 (pve001 node)

### Template Requirements
Both nodes need `debian-12-cloudinit-template` created via `/terraform/scripts/create-debian-template.sh`

## Recreating k3s Nodes

### Important: Server vs Agent Nodes

**Agent nodes (k3s-replica-*)**: Can be freely destroyed and recreated with just terraform
- No special cleanup needed
- Just `terraform destroy/apply` the replica module

**Server nodes (k3s-server-*)**: Require etcd member cleanup before recreation
- Server nodes are etcd cluster members
- `kubectl delete node` does NOT remove the etcd member
- If you skip this step, the new node will fail with: `etcd cluster join failed: duplicate node name found`

### Workflow for Recreating Server Nodes

```bash
# 1. Cordon the node
kubectl cordon k3s-server-1

# 2. Check if PiHole is on this node (CRITICAL!)
kubectl get pods -n pihole -o wide

# 3. Drain the node
kubectl drain k3s-server-1 --ignore-daemonsets --delete-emptydir-data

# 4. Delete from Kubernetes
kubectl delete node k3s-server-1

# 5. Remove from etcd cluster (REQUIRED for server nodes!)
# SSH to any working server node that has etcdctl installed
ssh ryan@<working-node-ip>

# Find the member ID for the node being removed
sudo ETCDCTL_API=3 \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl --endpoints=https://127.0.0.1:2379 member list

# Remove the member (use the ID from above)
sudo ETCDCTL_API=3 \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl --endpoints=https://127.0.0.1:2379 member remove <member-id>

# 6. Destroy and recreate with terraform
cd terraform
terraform destroy -target='module.k3s-servers[1]'  # Adjust index as needed
terraform apply -target='module.k3s-servers[1]'
```

### Installing etcdctl (if needed)

On Debian-based nodes:
```bash
sudo apt-get update && sudo apt-get install -y etcd-client
```

### Why This Happens

- When you recreate a server node VM, the IP address often changes (DHCP)
- The hostname stays the same (e.g., k3s-server-1)
- Etcd sees: "There's already a member named k3s-server-1 but with a different IP"
- Result: "duplicate node name" error and k3s won't start
- Solution: Remove the old etcd member before creating the new one

## Security Notes

- SOPS encrypted secrets use GPG key pair
- Ansible vault not currently implemented
- Cloud-init templates contain sensitive data via Terraform variables
- Never commit `.tfvars` files or unencrypted secrets

## Troubleshooting Notes

### Debugging k3s Nodes

**Philosophy**: Debug via `kubectl` from outside the cluster, not by SSH'ing into nodes.

**Minimal cloud-init packages**: VMs are provisioned with only essential packages (`nfs-common`, `qemu-guest-agent`).

**If you need to debug on a node**, install packages temporarily:
```bash
# SSH to the node
ssh ryan@<node-ip>

# Install debugging tools as needed
sudo apt-get update && sudo apt-get install -y \
  bind9-dnsutils \  # DNS debugging (dig, nslookup)
  htop \            # Resource monitoring
  jq \              # JSON parsing
  lsof \            # Port/file descriptor debugging
  netcat-openbsd \  # Network testing
  nmap              # Network scanning
```

These tools are intentionally NOT in cloud-init to encourage debugging from outside the cluster.

### Proxmox Cluster Issues

#### pmxcfs Filesystem Hanging
**Symptom**: `/etc/pve/nodes/[nodename]` directory access hangs, preventing SSL certificate access
**Root Cause**: Cluster filesystem communication errors, often after node restarts or network issues
**Solution**: 
```bash
# Stop all PVE services
systemctl stop pve-cluster pve-ha-crm pve-ha-lrm pvedaemon pveproxy

# Force kill pmxcfs and unmount filesystem
pkill -9 pmxcfs
umount -l /etc/pve

# Restart cluster service cleanly
systemctl start pve-cluster

# Verify directory access works
timeout 5 ls -la /etc/pve/nodes/[nodename]/
```

#### pveproxy Startup Hanging
**Symptom**: `pvecm updatecerts --silent` hangs during pveproxy startup, preventing web interface access
**Root Cause**: Certificate update command hangs due to cluster communication issues
**Solution**: Create systemd override to skip the problematic pre-start command:
```bash
systemctl edit pveproxy
# Add these lines:
# [Service]
# ExecStartPre=

systemctl daemon-reload
systemctl start pveproxy
```

#### Unkillable Processes in D State
**Symptom**: Processes stuck in uninterruptible sleep (D state), survive SIGKILL
**Root Cause**: Processes waiting for kernel I/O operations that will never complete
**Solution**: Reboot required to clear kernel I/O wait states
```bash
# Check for D state processes
ps aux | grep -E " D "

# Only solution is reboot
systemctl reboot
```

#### Intel e1000e NIC Hardware Hang (RECURRING ISSUE)
**Symptom**:
- Entire network freezes/becomes unresponsive
- k3s nodes go NotReady simultaneously
- MetalLB speakers restart when network recovers
- PiHole IPs get reassigned (192.168.4.253 → random → 192.168.4.253)
- DNS outage during IP reassignment
- May coincide with high CPU usage and load average spikes

**Root Cause**:
- Intel e1000e NIC driver (0000:00:1f.6 eno1) hardware unit hang
- Triggered by high multicast traffic (mDNS/SSDP)
- Home Assistant using host networking for Sonos discovery generates multicast traffic
- Known issue with e1000e driver under multicast load

**Occurrences**:
- First incident: ~2025-12-07 20:33 (required physical reboot)
- Second incident: 2026-01-04 17:12:22 (NIC auto-recovered after reset)

**Diagnostics**:
```bash
# Check Proxmox host for e1000e hangs
ssh root@192.168.4.200 'dmesg -T | grep -iE "e1000e|hang"'

# Look for:
# e1000e 0000:00:1f.6 eno1: Detected Hardware Unit Hang
# e1000e 0000:00:1f.6 eno1: Reset adapter unexpectedly

# Check k3s cluster for IP reassignments
kubectl get events -A --sort-by='.lastTimestamp' | grep -E "IPAllocated|ClearAssignment"
```

**Potential Solutions** (in order of preference):
1. **Update e1000e driver** - May have fixes for multicast handling
   ```bash
   ssh root@192.168.4.200
   ethtool -i eno1  # Check current driver version
   # Update Proxmox kernel (includes driver updates)
   apt update && apt upgrade pve-kernel-*
   ```

2. **Update NIC firmware** - Check Intel website for firmware updates

3. **Disable host networking for Home Assistant** - Eliminates multicast traffic but loses Sonos discovery

4. **Replace NIC** - Use different NIC hardware or driver (e.g., Intel I350, Broadcom)

5. **Driver parameters** - Try tuning e1000e parameters (not recommended without deep understanding)

**Current Configuration**: Home Assistant host networking ENABLED for Sonos discovery - accepting periodic outages while investigating driver/firmware updates

### Cluster Communication Diagnostics
```bash
# Check cluster status
pvecm status
pvecm nodes

# Check corosync communication
corosync-cmapctl | grep members

# Verify cluster filesystem access
ls -la /etc/pve/nodes/
timeout 5 ls -la /etc/pve/nodes/[nodename]/

# Check SSL certificates
openssl x509 -in /etc/pve/nodes/[nodename]/pve-ssl.pem -text -noout | grep "Subject:"
openssl rsa -in /etc/pve/nodes/[nodename]/pve-ssl.key -check
```