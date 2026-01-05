# Pi-hole High Availability Plan (UniFi)

## Goal
Keep local DNS working during k3s outages or maintenance by running a second Pi-hole on a Raspberry Pi outside the cluster, with simple failover and minimal complexity.

## Scope
- Keep the in-cluster Pi-hole.
- Add a Raspberry Pi Pi-hole and sync key config.
- Configure UniFi to provide resilient DNS resolution.

## Non-Goals
- Live-syncing FTL/query logs.
- Anycast/BGP/VRRP unless later needed.

---

## Architecture
- k3s Pi-hole: Stable MetalLB IP on TCP/UDP 53 (e.g., `192.168.4.53`).
- Raspberry Pi Pi-hole: Static/reserved IP outside k3s (e.g., `192.168.4.54`).
- Sync: Gravity Sync for adlists, groups, clients, regex, and local DNS records.
- Upstreams: Either public resolvers (Cloudflare/Quad9) or local Unbound per instance.
- Health: Check TCP/UDP 53 and Pi-hole API/FTL status.

---

## Failover vs. Load Balancing

### Client-Level Fallback (DHCP two DNS servers)
- Pros: Simple; no central chokepoint; widely compatible.
- Cons: Clients often “stick” to one DNS until timeout; not true load balancing.
- How: DHCP advertises two DNS servers: `[k3s_pihole_IP, rpi_pihole_IP]`.

### Router-Level Forwarding (UniFi dnsmasq)
- Pros: Centralized behavior; can query both backends in parallel with `all-servers`.
- Cons: Router becomes logical dependency; requires dnsmasq options.
- How: Clients use the gateway as DNS; gateway forwards to both Pi-holes.

### VIP/VRRP (Keepalived)
- Pros: Single virtual DNS IP that floats.
- Cons: Cross-environment complexity k3s+Pi; not ideal with MetalLB.
- How: Skip initially; revisit only if a single DNS IP is mandatory.

Recommendation: Start with Client-Level Fallback. If clients failover poorly, switch to Router-Level Forwarding with `all-servers`.

---

## Implementation Plan

### 1) Assign Stable Addresses
- k3s Pi-hole: Reserve a MetalLB IP (example `192.168.4.53`).
- Raspberry Pi Pi-hole: Static/reserved IP (example `192.168.4.54`).

### 2) Deploy Raspberry Pi Pi-hole
- Install Raspberry Pi OS Lite (64-bit); update firmware and OS.
- Install Pi-hole (standard installer).
- Upstream choice:
  - Cloudflare: `1.1.1.1`, `1.0.0.1` (or Quad9: `9.9.9.9`, `149.112.112.112`).
  - Optional Unbound local resolver: Install Unbound and point Pi-hole to `127.0.0.1#5335`.

### 3) Sync Config (Gravity Sync)
- On both Pi-holes: create a dedicated user with SSH key auth.
- On the RPi (or whichever is “secondary”):
  - `curl -sSL https://raw.githubusercontent.com/vmstan/gravity-sync/main/install.sh | bash`
  - `gravity-sync configure` and set the “primary” peer.
  - `gravity-sync push` (or `pull`) to seed, then set up the systemd timer for periodic sync (e.g., every 30–60 min).
- Sync scope: adlists, groups, clients, regex, local DNS. Do not sync FTL DB.
- Also export Teleporter backups periodically for DR.

### 4) UniFi DHCP/DNS Configuration

Option A — Client-Level Fallback (recommended starting point):
- UniFi Network → Settings → Networks → LAN → Edit → DHCP Name Server → Manual.
- Enter both IPs: `192.168.4.53`, `192.168.4.54`.
- Apply changes; renew client DHCP leases to pick up the new DNS list.

Option B — Router-Level Forwarding (USG/UXG) with dnsmasq:
- Keep DHCP Name Server = Auto (gateway IP) so clients query the router.
- Configure USG/UXG to forward to both Pi-holes. In `config.gateway.json` on the controller host:

```json
{
  "service": {
    "dns": {
      "forwarding": {
        "name-server": [
          "192.168.4.53",
          "192.168.4.54"
        ]
      }
    }
  }
}
```

- For parallel queries (fastest reply wins), add the dnsmasq option `all-servers`:

```json
{
  "service": {
    "dns": {
      "forwarding": {
        "name-server": [
          "192.168.4.53",
          "192.168.4.54"
        ],
        "options": [
          "all-servers"
        ]
      }
    }
  }
}
```

- For deterministic primary→secondary behavior instead, use `strict-order` (not with `all-servers`):

```json
{
  "service": {
    "dns": {
      "forwarding": {
        "name-server": [
          "192.168.4.53",
          "192.168.4.54"
        ],
        "options": [
          "strict-order"
        ]
      }
    }
  }
}
```

- Adopt and provision the USG/UXG to apply changes.

Notes for UDM/UDM Pro:
- `config.gateway.json` is not supported. You can approximate Option B by setting the WAN DNS servers to your Pi-holes and keeping DHCP Name Server = Auto (gateway), or use community tools (e.g., udm-utilities) to customize dnsmasq. Client-level fallback (Option A) is usually simpler on UDM.

### 5) Health Checks and Monitoring
- Basic liveness: TCP 53 (and optionally UDP 53) on both Pi-hole IPs.
- Pi-hole API: `http://<IP>/admin/api.php?summaryRaw` for status metrics.
- Alert if either endpoint is down or Gravity Sync fails.

### 6) Security and Access
- Restrict admin UIs to LAN; strong passwords.
- SSH key auth for Gravity Sync; disable password auth.
- Firewall to limit DNS to the LAN.

### 7) Testing and Cutover
- `nslookup` directly against each Pi-hole and the router DNS.
- Take k3s Pi-hole offline; confirm DNS continues via RPi.
- Take RPi Pi-hole offline; confirm DNS continues via k3s.
- Confirm Gravity Sync propagates lists and local DNS.

### 8) Operations
- Regular OS and Pi-hole updates; Unbound updates if used.
- Weekly Teleporter exports to off-box storage.
- Document recovery steps and IP reservations.

---

## Acceptance Criteria
- Both Pi-holes resolve queries; either alone can sustain LAN DNS.
- DHCP consistently provides resilient DNS configuration to clients.
- k3s outage does not break LAN DNS.
- Gravity Sync replicates lists and local DNS within 1 hour.
- Monitoring alerts on failure of either DNS instance.

---

## Appendix: MetalLB Service Example (k3s Pi-hole)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: pihole-dns
  namespace: pihole
  annotations:
    metallb.universe.tf/address-pool: default
spec:
  type: LoadBalancer
  loadBalancerIP: 192.168.4.53
  ports:
    - name: dns-udp
      port: 53
      protocol: UDP
      targetPort: 53
    - name: dns-tcp
      port: 53
      protocol: TCP
      targetPort: 53
  selector:
    app: pihole
```

> Ensure the MetalLB address pool contains `192.168.4.53` and that your Pi-hole deployment exposes TCP/UDP 53.

---

## Appendix: Gravity Sync Quick Commands

```bash
# On secondary (RPi) — install
curl -sSL https://raw.githubusercontent.com/vmstan/gravity-sync/main/install.sh | bash

# Configure and link to primary
gravity-sync configure
# Seed from primary to secondary (or reverse with pull)
gravity-sync push

# Check status and enable scheduled sync
gravity-sync status
systemctl --user enable gravity-sync.timer --now
```

> Use SSH keys and a minimal-privilege user. Do not attempt to sync FTL DB.

