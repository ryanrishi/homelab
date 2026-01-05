# k3s-server-0 Upgrade: Debian 12 to 13

**Date**: January 4-5, 2026
**Duration**: ~2 hours
**Outcome**: Success - zero downtime

## Context

k3s-server-0 was the last node in the cluster still running Debian 12. After successfully upgrading k3s-replica-0 earlier in the day, it was time to tackle the big one: the original cluster init node.

This was nerve-wracking because:
- k3s-server-0 originally bootstrapped the entire cluster with `cluster_init=true`
- All other nodes were hardcoded to connect via the `k3s-server-0` hostname
- It was running on the NUC (only node at 192.168.4.200) with 587 days of uptime
- There was configuration drift: the VM had a static IP (192.168.4.65) that wasn't in terraform

## Planning Phase

I spent significant time investigating risks before touching anything:

### Risk Assessment

**High Risks Identified**:
1. **DNS resolution failure** - All nodes connect via `k3s-server-0` hostname. If that stops resolving, the cluster dies.
2. **etcd duplicate member error** - If the old etcd member isn't removed before VM recreation, the new node can't join.
3. **Cluster re-initialization** - If `cluster_init=true` is used during recreation, k3s would try to create a NEW cluster instead of joining the existing one.

**Key Decision: cluster_init Flag Behavior**

The user asked a critical question: "How can I be sure that it won't try to create (or worse, overwrite) the existing cluster?"

Research into k3s documentation revealed:
- `--cluster-init` flag tells k3s to initialize a NEW etcd cluster
- After the cluster is established, k3s docs say "there is nothing special about the first node"
- The correct flag for joining an existing cluster is `--server https://k3s-server-0:6443`
- **Decision**: Set `cluster_init=false` permanently in terraform config

This was a key insight - keeping `cluster_init=true` would have been catastrophic.

### Protection Strategy

- **Proxmox snapshot**: Attempted but unavailable (storage backend doesn't support snapshots)
- **User decision**: "Let's proceed w/o the snapshot"
- **Quorum safety**: 4 server nodes with etcd quorum of 3 - can tolerate 1 failure
- **PiHole HA**: Already configured with 3 replicas on other nodes (from earlier session)

### Terraform Changes Planned

1. Change `cluster_init` from `true` to `false`
2. Add `ip = "192.168.4.65"` to fix configuration drift
3. Fix lookup syntax bug: `lookup(local.k3s_servers[count.index].cluster_init, false)` → `lookup(local.k3s_servers[count.index], "cluster_init", false)`

## Execution

### Phase 1: Preparation

Created etcd member backup:
```
ssh ryan@192.168.4.44  # k3s-server-1
etcdctl member list -w table > ~/etcd-members-pre-upgrade.txt
```

Backed up 4 members:
- k3s-server-0: 192.168.4.65 (member ID: ad30af57897538b)
- k3s-server-1: 192.168.4.44
- k3s-server-2: 192.168.4.149
- k3s-server-3: 192.168.4.99

Updated terraform config with both changes (cluster_init=false, ip=192.168.4.65).

### Phase 2: Node Removal

Cordoned and drained k3s-server-0, deleted from Kubernetes.

**Surprise**: When we ran `kubectl delete node k3s-server-0`, then checked the etcd member list, the member was already gone! k3s automatically removed it - no manual `etcdctl member remove` needed.

This was a pleasant deviation from the plan. The CLAUDE.md procedure (from a previous node recreation) required manual etcd member removal, but that was before we understood k3s's automation.

### Phase 3: VM Destruction and Recreation

User ran terraform commands manually:
```bash
terraform destroy -target='module.k3s-servers[0]'
terraform apply -target='module.k3s-servers[0]'
```

VM creation was fast (~5 minutes) - just cloning from the Debian 13 template.

### Phase 4: The Cloud-Init Failure

**Challenge #1: k3s Service Won't Start**

Cloud-init completed but k3s service was in a crash loop:
```
fatal msg="starting kubernetes: preparing server: failed to get CA certs:
Get \"https://k3s-server-0:6443/cacerts\": dial tcp 127.0.1.1:6443: connect: connection refused"
```

**Root Cause**: Circular dependency in DNS resolution.

The k3s service file had:
```
ExecStart=/usr/local/bin/k3s server --server https://k3s-server-0:6443 ...
```

And `/etc/hosts` (managed by cloud-init) had:
```
127.0.1.1 k3s-server-0 k3s-server-0
```

So k3s was trying to connect to `k3s-server-0:6443` which resolved to `127.0.1.1` (itself) before k3s was even running. Classic chicken-and-egg problem.

**First Attempted Solution**: Automation

I modified terraform to add `k3s_server_endpoint = "k3s-server-1"` as a per-server override, which would pass through ansible and generate:
```
ExecStart=/usr/local/bin/k3s server --server https://k3s-server-1:6443 ...
```

This would have been a repeatable, automated fix for future recreations.

**User Decision**: Manual Fix Instead

User: "eh no let's not do that. back out your changes, let's just change this to k3s-server-1 inside the vm manually"

Fair point - the automation was adding complexity for a scenario that hopefully won't happen often (recreating the first node). Manual fix was simpler.

**Challenge #2: DNS Resolution for k3s-server-1**

After changing the service file to point to k3s-server-1, new error:
```
dial tcp: lookup k3s-server-1: no such host
```

The VM was using the router (192.168.4.1) for DNS, not PiHole (192.168.4.253), and k3s-server-1 wasn't registered in the router's DNS.

**Solution**: Added to /etc/hosts:
```bash
echo '192.168.4.44 k3s-server-1' | sudo tee -a /etc/hosts
```

Restarted k3s service, and it immediately joined the cluster successfully.

## Final Verification

### Cluster Health
- All 6 nodes Ready (4 servers + 2 agents)
- k3s-server-0 showing Debian 13, age 15 seconds
- Memory usage healthy: k3s-server-0 at 42%, all nodes under 62%

### etcd Cluster
```
+------------------+---------+-----------------------+----------------------------+
|        ID        | STATUS  |         NAME          |         PEER ADDRS         |
+------------------+---------+-----------------------+----------------------------+
| ce1c571297db2bdb | started | k3s-server-3-998c1675 |  https://192.168.4.99:2380 |
| cfae06e690795a32 | started | k3s-server-0-7cd9d4da |  https://192.168.4.65:2380 |
| d214464dc90026e2 | started | k3s-server-1-c63ef65a |  https://192.168.4.44:2380 |
| ebfc65499836078d | started | k3s-server-2-2efcc06c | https://192.168.4.149:2380 |
+------------------+---------+-----------------------+----------------------------+
```

All endpoints healthy - 4/4 members responding in ~4-5ms.

New member ID `cfae06e690795a32` replaced old `ad30af57897538b` as expected.

### Services
- PiHole: 3 replicas running on k3s-server-2, k3s-server-3, k3s-replica-1 (not on server-0, as planned)
- DNS test: `nslookup google.com 192.168.4.253` successful
- LoadBalancer IP: 192.168.4.253 stable
- Flux CD: All kustomizations reconciling on latest revision

### Zero Downtime Achieved
- Control plane: 0 minutes downtime (3 servers maintained quorum)
- PiHole DNS: 0 minutes downtime (3 replicas on other nodes)
- k3s-server-0: ~15 minutes downtime (VM clone + manual fixes + k3s join)

## Deviations from Plan

1. **Proxmox Snapshot**: Planned but unavailable - storage backend didn't support it. Proceeded anyway.

2. **etcd Member Removal**: Plan called for manual `etcdctl member remove`. Reality: k3s auto-removed it when we ran `kubectl delete node`. Less manual work than expected.

3. **Automation vs Manual Fix**: Planned to add terraform automation for `k3s_server_endpoint` override. User chose manual fix instead for simplicity. Required two manual changes on the VM:
   - Edit `/etc/systemd/system/k3s.service` to point to k3s-server-1
   - Add k3s-server-1 to `/etc/hosts` for DNS resolution

4. **VM Creation Time**: Plan estimated 5-10 minutes. Actual: ~5 minutes for VM, but another ~10-15 minutes debugging cloud-init failure and applying manual fixes.

## Key Decisions Made

### During Planning
- **Set cluster_init=false permanently**: Based on k3s docs research showing `--cluster-init` would create a new cluster
- **Proceed without Proxmox snapshot**: Risk accepted given HA configuration
- **Add static IP to terraform**: Fix configuration drift for repeatability

### During Execution
- **Manual fix over automation**: Chose simplicity for a rare operation (recreating first node)
- **Use k3s-server-1 as bootstrap target**: Cleanest available server to connect to during join

## Lessons Learned

### What Went Well
- **Planning paid off**: Identifying the cluster_init risk before execution prevented a disaster
- **k3s automation**: Auto-removal of etcd members on node deletion is slick
- **HA architecture**: 3-node quorum meant zero downtime for the cluster
- **PiHole HA**: Pre-existing 3-replica setup meant zero DNS downtime

### Gotchas
- **cloud-init manage_etc_hosts**: The `127.0.1.1 hostname` mapping is automatic and interferes with k3s bootstrap when the node needs to connect to itself by hostname
- **DNS resolution during bootstrap**: New VMs don't have all cluster hostnames in DNS by default - /etc/hosts entries needed for bootstrap
- **Terraform state drift**: Static IP was manually configured but not in terraform - important to find and fix these before major operations

### For Next Time
If we ever need to recreate k3s-server-0 again:

1. The `/etc/hosts` fix will be needed again unless we:
   - Add k3s-server-1 to PiHole DNS as a static entry, OR
   - Configure cloud-init to disable `manage_etc_hosts`, OR
   - Add terraform automation to override k3s_server_endpoint for server-0

2. The k3s service file edit will be needed again (point to k3s-server-1 not k3s-server-0)

3. Could potentially add these fixes to the ansible playbook as a post-install step specifically for server-0

### Broader Takeaway
The original "first node is special" assumption (cluster_init=true) was wrong once the cluster was established. k3s treats all server nodes equally after initial bootstrap. This is good for resilience but means we need to be careful about bootstrap procedures during node recreation.

## Final State

**Cluster**: 6 nodes (4 servers, 2 agents), all running Debian 13
**etcd**: 4-member cluster, all healthy
**k3s version**: v1.30.0+k3s1 across all nodes
**PiHole**: 3 replicas, DNS operational at 192.168.4.253
**Uptime**: k3s-server-0 at 15 seconds (new), others at 7-26 hours
**Configuration**: Terraform state now matches reality (static IP, cluster_init=false)

The "kingpin" node has been successfully upgraded with zero impact to the cluster. The last Debian 12 holdout is now gone.
