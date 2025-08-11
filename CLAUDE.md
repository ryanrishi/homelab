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

## Security Notes

- SOPS encrypted secrets use GPG key pair
- Ansible vault not currently implemented
- Cloud-init templates contain sensitive data via Terraform variables
- Never commit `.tfvars` files or unencrypted secrets

## Troubleshooting Notes

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