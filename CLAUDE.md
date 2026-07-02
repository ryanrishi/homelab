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

## ⚠️ CRITICAL: Sensitive Information

**NEVER expose sensitive information in code or commits:**

- **Domain names**: NEVER hardcode domain names in files or commit messages
  - Use Terraform variables for all domain references
  - Keep actual values in `.tfvars` files (gitignored)
  - Use generic descriptions in commit messages

- **API tokens/keys**: NEVER commit API tokens, credentials, or secrets
  - Use SOPS encryption for Kubernetes secrets
  - Use Terraform variables marked as `sensitive = true`
  - Ensure `.tfvars` files are gitignored

- **IP addresses**: Avoid exposing internal IPs in public commits
  - Use variables or configuration files for network configuration

- **Account/Zone IDs**: Use Terraform variables, never hardcode

**Before committing:**
- Review commit diff for any sensitive values
- Check commit message doesn't reference domains/IPs
- Verify `.tfvars` files are gitignored
- Ensure secrets are encrypted with SOPS

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
- **NUC (pve)**: Media server, k3s-server-0 (cluster init), ddclient, wireguard, k3s-replica-0
- **M920q (pve002)**: k3s-server-1, k3s-server-2, k3s-replica-1, k3s-replica-2, k3s-replica-3

### Provider Configuration
- `proxmox.nuc`: 192.168.4.200 (pve)
- `proxmox.m920q`: 192.168.4.202 (pve002)

### Template Requirements
Both nodes need `debian-12-cloudinit-template` created via `/terraform/scripts/create-debian-template.sh`

## Recreating k3s Nodes

### Important: Server vs Agent Nodes

**Agent nodes (k3s-replica-*)**: Can be freely destroyed and recreated with just terraform
- No special cleanup needed
- Just `terraform destroy/apply` the replica module

**Server nodes (k3s-server-*)**: Are etcd cluster members
- On current k3s (v1.32), `kubectl delete node k3s-server-N` also removes the node's etcd member automatically
- So if you delete the node before recreating the VM, no manual etcd cleanup is needed
- Manual `etcdctl member remove` is only a fallback: needed if you recreate the VM WITHOUT deleting the node first (the stale member then collides with the new one → `etcd cluster join failed: duplicate node name found`)
- Always verify with `etcdctl member list` before recreating; only remove if the old member is still present

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

# 5. Verify the etcd member is gone (kubectl delete node usually removes it automatically)
# SSH to any working server node that has etcdctl installed
ssh ryan@<working-node-ip>

sudo ETCDCTL_API=3 \
  ETCDCTL_CACERT=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
  ETCDCTL_CERT=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
  ETCDCTL_KEY=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
  etcdctl --endpoints=https://127.0.0.1:2379 member list

# If the removed node is NOT listed, skip ahead. If it IS still listed
# (e.g. you recreated without deleting the node first), remove it:
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
- If a stale etcd member with that name still exists, etcd sees: "There's already a member named k3s-server-1 but with a different IP" → "duplicate node name" error and k3s won't start
- `kubectl delete node` removes the etcd member for you, so following the workflow order (delete node, then recreate) avoids this
- The manual `member remove` only matters when the node was NOT deleted first

## Security Notes

- SOPS encrypted secrets use GPG key pair
- Ansible vault not currently implemented
- Cloud-init templates contain sensitive data via Terraform variables
- Never commit `.tfvars` files or unencrypted secrets

## Code Comment Guidelines

**Don't put "data" in comments** - information that can become outdated causes confusion.

This includes:
- **Specific values** defined elsewhere (RAM, disk sizes, counts)
- **Context-specific reasons** for current state (why something is disabled, temporary workarounds)

Examples:
- **Bad**: `# Schedule on nodes with 4GB RAM and 80GB disk`
- **Bad**: `enabled: false  # Disabled until storage and media stack are working`
- **Good**: `# Schedule on agent nodes which have more resources`
- **Good**: `enabled: false`

The code should speak for itself. If someone later changes `enabled: false` to `enabled: true`, any comment explaining why it was disabled is now wrong and misleading.

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

### Proxmox Node Maintenance Mode

Before performing maintenance on a Proxmox node (updates, hardware changes, etc.), put it in maintenance mode to gracefully migrate VMs to other nodes.

```bash
# Enable maintenance mode (VMs will live-migrate to other nodes)
ha-manager crm-command node-maintenance enable <node-name>

# Check HA status
ha-manager status

# Disable maintenance mode when done
ha-manager crm-command node-maintenance disable <node-name>
```

**What it does:**
- Gracefully live-migrates HA-managed VMs to other cluster nodes
- Minimal disruption (sub-second interruption during migration)
- Prevents new VMs from being scheduled on the node
- Safer than manually draining/migrating VMs

**Requirements:**
- Node must be part of a Proxmox cluster
- VMs must be configured for HA (High Availability)
- Shared storage required for live migration

**Note:** No GUI for this feature yet - CLI only.

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

#### Intel e1000e NIC Hardware Hang
**Symptom**: Host becomes unreachable; k3s nodes go NotReady; NIC may not recover without physical reboot

**Root Cause**: Intel I219-V NIC driver bug triggered by high multicast traffic (mDNS/SSDP)

**Hardware**:
- **pve** (NUC): kernel 6.5.11-7-pve — hangs but usually recovers on its own
- **pve002** (M920q): kernel 6.8.12-9-pve — fatal hangs, requires physical reboot

**Fix**: Disable TSO/GSO to avoid stuck transmit path:
```bash
ethtool -K eno1 tso off gso off
```
Persist by adding `post-up ethtool -K eno1 tso off gso off` to the `iface eno1` stanza in `/etc/network/interfaces`. Applied to pve002; consider applying to pve as well.

**Long-term fix**: Replace onboard NICs with PCIe cards (Intel I350, X710, or Broadcom BCM5720)

**Diagnostics**:
```bash
# Check for hangs in current boot
journalctl -b | grep "Hardware Unit Hang"

# "Reset adapter" message = recoverable; no reset message = fatal, needs physical reboot
```

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