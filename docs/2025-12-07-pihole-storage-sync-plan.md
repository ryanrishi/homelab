# Pi-hole Storage Split + Config Sync Plan

Goal
- Split Pi-hole storage so configs persist while the FTL DB lives on local disk (not NFS), and mirror configs between k3s Pi-hole and a Raspberry Pi Pi-hole using Gravity Sync.

Scope
- k3s Pi-hole: keep `/etc/pihole` on PVC; move FTL DB to local disk; lower DB retention.
- Raspberry Pi Pi-hole: local storage (USB SSD preferred); same retention; configure Gravity Sync.
- Config sync only (lists, regex, clients, local DNS) — no FTL DB sync.

Assumptions
- Namespace: `pihole`.
- k3s Pi-hole is reachable from RPi over SSH (or vice versa) for Gravity Sync.
- UniFi DHCP advertises both DNS servers (see `pihole-ha-plan-unifi.md`).

Decisions Needed
- Primary instance for config edits: `k3s` or `rpi` (recommended: pick one).
- RPi IP/hostname and SSH user for Gravity Sync.

Implementation Steps

1) Update k3s Pi-hole deployment for storage split
- Add env vars:
  - `FTLCONF_database_path=/var/lib/pihole/pihole-FTL.db`
  - `FTLCONF_database_maxDBdays=30` (tune as desired)
- Mounts:
  - Keep PVC at `/etc/pihole` (configs, gravity.db, custom lists)
  - Add `emptyDir` (or node-local storage) at `/var/lib/pihole` (FTL DB only)
- Roll out and verify logs show new DB creation and no SQLite corruption.

Example patch (conceptual):
```yaml
spec:
  template:
    spec:
      containers:
      - name: pihole
        env:
          - name: FTLCONF_database_path
            value: /var/lib/pihole/pihole-FTL.db
          - name: FTLCONF_database_maxDBdays
            value: "30"
        volumeMounts:
          - name: pihole-config
            mountPath: /etc/pihole
          - name: pihole-ftldb
            mountPath: /var/lib/pihole
      volumes:
        - name: pihole-config
          persistentVolumeClaim:
            claimName: pihole
        - name: pihole-ftldb
          emptyDir: {}
```

2) Prepare Raspberry Pi Pi-hole
- Install Raspberry Pi OS Lite (64-bit); update firmware.
- Install Pi-hole normally; set upstreams; set retention:
  - In `/etc/pihole/pihole.toml` (or env): `database.maxDBdays = 30`
- Prefer USB SSD to reduce SD card wear.

3) Configure Gravity Sync (one-way)
- Choose primary (`k3s` or `rpi`). Edit only on the primary.
- On secondary (the non-primary):
```bash
curl -sSL https://raw.githubusercontent.com/vmstan/gravity-sync/main/install.sh | bash
gravity-sync configure   # set primary host/user/path
# Seed from primary to secondary
gravity-sync pull        # if secondary should mirror primary now
# Enable scheduled sync (30–60 min)
systemctl --user enable gravity-sync.timer --now
```
- Verify:
```bash
gravity-sync status
```

4) UniFi DHCP/DNS validation
- Ensure both DNS servers are advertised via DHCP (Option A) or router-level forwarding is configured (Option B) per `pihole-ha-plan-unifi.md`.

5) Testing
- Resolve via each Pi-hole directly (`nslookup example.com <IP>`).
- Make a config change on the primary (e.g., add a blacklist entry), run `gravity-sync push/pull`, verify on secondary.
- Reboot k3s node (or stop Pi-hole deployment) to confirm RPi continues to serve DNS.

6) Rollback Plan
- Revert env/volume changes in the k3s deployment if issues arise.
- Restore previous DB if needed: stop pod, swap `pihole-FTL.db` with backup, restart.

7) Operations
- Keep Pi-hole and OS updated.
- Periodic Teleporter exports on the primary for DR.
- Monitor TCP/UDP 53 and Pi-hole API on both instances.

Acceptance Criteria
- k3s Pi-hole runs with FTL DB on local disk, no recurrent SQLite errors.
- RPi Pi-hole resolves DNS independently with the same config.
- Config edits on the primary sync to the secondary within 60 minutes.
- LAN DNS continues to function if either instance is offline.

Open Items
- Confirm which instance is PRIMARY for Gravity Sync: `k3s` or `rpi`.
- Decide retention window (default 30 days) based on storage and query volume.
