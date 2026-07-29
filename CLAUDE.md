# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a homelab infrastructure management repository that uses three main technologies:
- **Ansible** for configuration management of VMs and services
- **Terraform** for VM provisioning on Proxmox
- **Kubernetes (k3s)** for container orchestration with Flux CD

## ⚠️ CRITICAL: Resource Constraints

**HOMELAB SETUP**: Three Proxmox hosts, 78GB RAM total (31 + 15 + 31). `pve002` is the constraint
at 15GB with ~2GB free — check it specifically, not just the cluster total.
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
- **k3s**: Lightweight Kubernetes distribution. Bundled servicelb and traefik are
  disabled (`roles/k3s-server` config); MetalLB and the Flux-managed Traefik are used instead.
- **Flux CD**: GitOps continuous delivery
- **MetalLB**: Load balancer for external IPs. Pin an IP with the
  `metallb.universe.tf/loadBalancerIPs` annotation (or `spec.loadBalancerIP`) —
  `metallb.io/loadBalancerIPs` is silently ignored and the service gets auto-assigned.
- **kube-vip**: Control-plane VIP `192.168.4.5` (control-plane-only DaemonSet, ARP +
  leader election). Server nodes join via this VIP (`k3s_server_endpoint`) and kubectl
  points at it, so no single server is a hard dependency. Servers stay on DHCP.
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

### Three-Node Setup

| Proxmox host | IP | k3s | Other VMs |
|---|---|---|---|
| `ryanrishi` (NUC) | 192.168.4.200 | 1 server, 2 agents (one with iGPU) | `molt`, `media` (stopped) |
| `pve002` (M920q) | 192.168.4.202 | 1 server, 1 agent | — |
| `pve003` (NUC) | 192.168.4.203 | 1 server, 2 agents (one with iGPU) | — |

**Exactly one k3s server per Proxmox host.** Preserve this: it is what lets any single host reboot
without losing etcd quorum.

k3s nodes are named `k3s-{server,agent}-<6 random chars>` — there are no ordinals, and every IP is
DHCP. Get current values from `kubectl get nodes -o wide`. `media` and `molt` are deliberately NOT
managed by Terraform.

### Provider Configuration
Single provider, `bpg/proxmox`, named `proxmox`. Node name → IP comes from `var.pve_nodes`, which
the provider also uses for SSH (snippet uploads have no API equivalent, and the hostnames do not
resolve in DNS). SSH key path comes from `PROXMOX_VE_SSH_PRIVATE_KEY` in the gitignored
`terraform/.env`.

### No templates
VMs are built directly from a pinned, checksummed Debian cloud image via `disk.import_from` (see
`terraform/images.tf`). There is no Proxmox template to maintain and no `create-debian-template.sh`.
Use the `generic` cloud image, not `genericcloud` — the `-cloud` kernel ships no DRM drivers, so
`i915` can never bind and GPU passthrough silently fails.

## Recreating k3s Nodes

### Rebuild by replacing the `random_string`, never the VM

The random suffix is stable in state, so a `-replace` on the VM brings it back under the *same
name* — and k3s writes node identity only at first registration, so the surviving node object keeps
its old IP and loses its `--node-label` flags.

```bash
terraform apply -replace='random_string.k3s_agent[N]' -target='module.k3s_agents'
```

This cascades because `name` → cloud-init `hostname` → snippet content hash → `user_data_file_id`,
and that field is ForceNew. `name` alone is not.

### Always evacuate Longhorn BEFORE draining

`kubectl drain` evicts Longhorn's `instance-manager`, and without it there is no agent left on the
node to garbage-collect replicas — they strand at `stopped` forever and the node CR outlives
`kubectl delete node`.

```bash
kubectl patch nodes.longhorn.io <node> -n longhorn-system --type=merge \
  -p '{"spec":{"allowScheduling":false,"evictionRequested":true}}'
```

`allowScheduling: false` must be in the same patch or the webhook rejects it; `kubectl cordon` does
NOT set it. Wait until every affected volume is `healthy` with its full replica count running on
*other* nodes. **Re-derive which volumes live on the node immediately beforehand** — placement
moves constantly, and `longhorn-single` volumes have only one copy.

### Ordering, and why it differs for rebuild vs removal

- **Rebuilding** a node: `kubectl delete node` first, then recreate.
- **Removing** one permanently: destroy the VM FIRST, *then* `kubectl delete node`. The VM stays
  alive during the ~90s destroy, and a live k3s server will re-register its own node object inside
  that window. That happened on 2026-07-28: a removed server came back `NotReady` with
  `EtcdIsVoter=True` after its VM was gone, leaving etcd at 4 members with one permanently dead —
  quorum met by exactly 3 live servers, i.e. **zero fault tolerance**, with nothing visibly broken.
  `kubectl delete node` removes the etcd member whether or not the VM exists, so there is no
  benefit to going first.

**Re-check `kubectl get nodes` a minute after any server removal.** Whether the object comes back
is a race against the kubelet heartbeat, so absence immediately after the delete proves nothing.

### Replacing a server: add before removing

Bring the new server up and confirm `EtcdIsVoter=True` before removing the old one. 3 members and 4
members both tolerate one failure; 2 members tolerate none. There is no `etcdctl` installed on the
nodes — use the node condition instead:

```bash
kubectl get nodes -l node-role.kubernetes.io/etcd=true -o json \
  | jq -r '.items[]|"\(.metadata.name) \([.status.conditions[]|select(.type=="EtcdIsVoter")|.status]|join(""))"'
```

If the departing server holds the kube-vip lease (`kubectl get lease -n kube-system plndr-cp-lock
-o jsonpath='{.spec.holderIdentity}'`), move it off before draining so the VIP fails over gracefully
instead of dying with the VM. The DaemonSet's label is `app.kubernetes.io/name=kube-vip-ds` — a
selector of `name=kube-vip` matches nothing and exits 0, so it looks like it worked while doing
nothing.

**Deleting the pod alone does not move the lease, and neither does deleting the lease alongside it.**
A freshly-started kube-vip acquires immediately, while the incumbents sit on a slow retry — so the
departing server's recreated pod wins the re-election within ~10s, every time. The delete must
*block* until the pod is actually gone, and only then can the lease be deleted:

```bash
kubectl delete pod -n kube-system -l app.kubernetes.io/name=kube-vip-ds \
  --field-selector spec.nodeName=<server> --wait=true --timeout=60s
kubectl delete lease -n kube-system plndr-cp-lock
```

Verify the holder actually changed, and re-check a minute later — the recreated pod is still a
candidate and the point is for it to lose. The API stays up throughout; the VIP moves without a
readyz failure.

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

### Disabling a bundled k3s addon deletes its CRDs

`--disable <addon>` uninstalls the addon, and if it owns CRDs those get **deleted**
(taking all their CR objects with them). Disabling bundled traefik removed the core
`traefik.io` CRDs (IngressRoute/Middleware), which the Flux-managed Traefik relied on
— silently breaking all IngressRoute routing (e.g. the media `*arr` apps). The
Flux Traefik chart had only ever installed the `hub.traefik.io` CRDs because the core
ones already existed (from the bundled addon).

**Fix / prevention**: make the replacement own its CRDs. For the Flux Traefik
HelmRelease, set `spec.install.crds` and `spec.upgrade.crds` to `CreateReplace`, then
force a Helm upgrade (`flux reconcile helmrelease traefik -n traefik --force`) so Flux
(re)installs the chart's CRDs.

### Flux var change that feeds a HelmRelease annotation

Changing a `cluster-settings` value used in a HelmRelease (e.g. `SVC_TRAEFIK_IP` for a
MetalLB pin) requires reconciling the HelmRelease in the same pass, not just the
kustomization — otherwise the ConfigMap updates but the rendered Service keeps the old
value until the next Helm apply, briefly moving the IP and breaking anything (like DNS)
that points at the intended one.

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

### Proxmox Node Maintenance

**`ha-manager crm-command node-maintenance` does not work here and must not be used.** It requires
HA-configured guests and shared storage; this lab has neither (no `proxmox_virtual_environment_ha_*`
resources, every disk on node-local `local-lvm`), and two agents use iGPU passthrough, which cannot
migrate at all. Nothing would move — the command is a no-op that reads like a safeguard.

Redundancy comes from the k3s layer instead: one k3s server per Proxmox host, so a single host can
be down without losing etcd quorum. **Only ever take down one host at a time.** Evacuate
Kubernetes, then stop the guests:

```bash
# 1. Gates: 8/8 nodes Ready, etcd 3/3 voters, all Longhorn volumes healthy, PiHole 3/3, DNS resolving.
#    Re-derive which k3s nodes are on this host — names and IPs are DHCP and placement drifts.
kubectl get nodes -o wide -L topology.kubernetes.io/zone

# 2. If this host's server holds the kube-vip lease, move it first.
kubectl get lease -n kube-system plndr-cp-lock -o jsonpath='{.spec.holderIdentity}'
kubectl delete pod -n kube-system -l app.kubernetes.io/name=kube-vip-ds \
  --field-selector spec.nodeName=<server>
# If the lease does not move (the DaemonSet can recreate the pod and reacquire), delete the lease
# to force re-election: kubectl delete lease -n kube-system plndr-cp-lock

# 3. Cordon every node on the host FIRST, so drained pods do not land back on it. Then drain.
kubectl cordon <server> <agent...>
kubectl drain <agent> --ignore-daemonsets --delete-emptydir-data --timeout=15m

# 4. Stop only guests that are actually running, so stopped VMs can never be in scope.
RUNNING=$(qm list | awk '$3=="running" {print $1}'); echo "$RUNNING"
for id in $RUNNING; do qm shutdown $id --timeout 180; done
```

Expect the agent drain to sit on the Longhorn `instance-manager` PDB until volumes detach. If it
never completes, the node likely holds the **last replica** of some volume — Longhorn's
`node-drain-policy` is `block-if-contains-last-replica`, which is protecting data, not
malfunctioning. The workload pods will already have moved; that is what matters.

Do **not** set `evictionRequested` for a reboot — that is for permanent removal and has stalled for
30+ minutes. Draining is not optional either: `node-down-pod-deletion-policy` is `do-nothing`, so
pods with Longhorn volumes hang until the node returns rather than rescheduling.

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

**Hardware**: all three hosts use the Intel I219-V. Historically `ryanrishi` (NUC) recovered on its
own via an adapter reset, while `pve002` (M920q) hung fatally and needed a physical reboot.

**Fix**: Disable TSO/GSO to avoid stuck transmit path:
```bash
ethtool -K eno1 tso off gso off
```
Persist by adding `post-up ethtool -K eno1 tso off gso off` to the `iface eno1` stanza in
`/etc/network/interfaces`. **Applied and persistent on all three hosts.** It survives major
upgrades, but re-verify after any kernel or PVE version change — the offloads reverting is silent
until the host wedges:
```bash
ethtool -k eno1 | grep -E "^tcp-segmentation-offload|^generic-segmentation-offload"  # both "off"
```

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