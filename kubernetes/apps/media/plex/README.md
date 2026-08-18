# Plex migration to k3s

Brings Plex off the legacy media VM (id 108, `<media-vm-ip>`, `docker-htpc` Ansible role,
`linuxserver/plex:1.32.0`) into k3s.

The canonical Plex library already lives on the NAS (`<nas-ip>`) at
`/volume1/Plex/complete/{tv,movies,concerts}` — the same paths the VM container mounts at
`/tv`, `/movies`, `/concerts`. The k3s Plex pod mounts **that same share** at the same
in-container paths, so with the migrated config it is byte-for-byte identical and every item
plays immediately. **No media is moved to bring Plex up.**

The *arr stack writes to a different share (`/volume1/k3s/media/media/{tv,movies}`), which is why
finished downloads currently need a manual copy. Eliminating that is a **separate, later** step
(see "Later: unify media").

Two prerequisites this share imposes (both hit during the 2026-06-22 cutover):
- The Synology **`Plex` shared folder must be NFS-exported to the k3s nodes** (DSM → Shared Folder
  → Plex → NFS Permissions), like the `k3s` share is. Without it the pod can't mount.
- The legacy library tree is **root/admin-owned** and the share squashes root→admin, so Plex runs
  as **root (`PUID/PGID=0`)** to read it; uid 1000 is denied. (Cleaner future option: set the
  share squash to "map all users to admin" and run Plex as `PUID 1000` like the other apps.)

The Deployment (`plex-deployment.yaml`) is intentionally **not** listed in `../kustomization.yaml`.
Storage (`plex-pvc.yaml`) and the LoadBalancer service (`plex-service.yaml`) are registered so they
exist ahead of cutover, but Plex only goes live after the config is migrated and the VM's Plex is
stopped — otherwise two servers fight over the same identity.

LoadBalancer IP is `SVC_PLEX_IP` = `<plex-lb-ip>` — pick a free address in the MetalLB pool (the
two traefik installs already hold a couple).

## Step 1 — Push storage + service scaffolding

Commit and push (Flux reconciles): the `nfs-plex-library-pv` PV, the `plex-config` (Longhorn) +
`plex-library` PVCs, the LoadBalancer service (`SVC_PLEX_IP` = `<plex-lb-ip>`).

```bash
kubectl get pvc -n media plex-config plex-library   # both Bound
```

## Step 2 — Migrate Plex config into the Longhorn PVC

Stop the VM's Plex so the SQLite DB is quiesced (begins brief Plex downtime), then stream the
~1.6 GB config straight into the PVC via a helper pod.

```bash
# quiesce the source
ssh ryan@<media-vm-ip> 'cd /opt/docker-htpc && docker compose stop plex'

# helper pod mounting the empty plex-config PVC
kubectl apply -n media -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: plex-config-loader
  namespace: media
spec:
  nodeSelector:
    lab.ryanrishi.com/longhorn-enabled: "true"
  containers:
    - name: loader
      image: alpine:3
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: config
          mountPath: /config
  volumes:
    - name: config
      persistentVolumeClaim:
        claimName: plex-config
EOF
kubectl wait -n media --for=condition=Ready pod/plex-config-loader --timeout=120s

# stream config from the VM into the PVC, fix ownership, clean up
ssh ryan@<media-vm-ip> 'sudo tar czf - -C /opt/docker-htpc/plex/config .' \
  | kubectl exec -i -n media plex-config-loader -- tar xzf - -C /config
kubectl exec -n media plex-config-loader -- chown -R 1000:1000 /config
kubectl delete pod -n media plex-config-loader
```

## Step 3 — Cutover

1. Confirm the VM's Plex is stopped (above).
2. Register the deployment in `../kustomization.yaml`:
   ```yaml
   - plex/plex-deployment.yaml
   ```
3. Commit + push; Flux deploys Plex.
4. Validate:
   ```bash
   kubectl get pods -n media -l app=plex -o wide
   kubectl get svc -n media plex          # EXTERNAL-IP == <plex-lb-ip>
   kubectl logs -n media -l app=plex --tail=50
   ```
   Browse `http://<plex-lb-ip>:32400/web` — library, posters, watch history intact, items play.
5. Update DNS / reverse proxy and Plex's custom server access URL if needed.

### Rollback
Remove the deployment line + push (Flux removes the pod), then
`ssh ryan@<media-vm-ip> 'cd /opt/docker-htpc && docker compose start plex'`. The migrated PVC is a
copy — the VM's original config is untouched. (Do not run both Plex servers at once.)

## Remote access & runtime settings (live in the PVC, NOT in git)

Plex server settings live in `Preferences.xml` inside the **`plex-config` Longhorn PVC**, not in
any manifest. linuxserver/plex exposes no env var for them, so they **cannot** be managed
declaratively / via GitOps — they are set once on the running server (Plex web UI, or the
`/:/prefs` API with the server's `PlexOnlineToken`) and **persist in the volume**. Flux reconciles
the manifest objects (Deployment/Service/PVC) and does **not** touch `Preferences.xml`, so it will
not reset these. This mirrors how the old VM stored config in its config dir. If the PVC is ever
wiped, re-set them once.

**Caveat — Plex may rewrite some keys on first boot.** After migration the new pod reset
`PublishServerOnPlexOnlineKey` to `0` even though the VM had `1`. Always confirm against the VM's
true config (read-only: mount the stopped VM disk on the Proxmox host, or extract from the vzdump)
rather than trusting the freshly-migrated values.

Remote access is **enabled**, matching the legacy VM. Settings of note (VM ground truth ==
current k3s):

| Key | Value | Meaning |
| --- | --- | --- |
| `PublishServerOnPlexOnlineKey` | `1` | Remote Access enabled (advertises to plex.tv) |
| `ManualPortMappingMode` | `1` | Manual port mapping (UPnP/NAT-PMP can't work behind MetalLB) |
| `ManualPortMappingPort` | `32400` | Public port. VM had this *unset* (Plex defaults to 32400); k3s has it explicit — behaviourally identical |
| `WanTotalMaxUploadRate` | `850000` | ~850 Mbps total WAN upload cap |
| `LanNetworksBandwidth` | `<lan-subnet>,<lan-subnet>` | Treated as LAN (unmetered). One entry is a stale subnet — harmless leftover |

**Network path for remote access (double NAT):** upstream router (`<wan-ip>`) forwards TCP `32400`
→ UniFi UDM WAN (`<udm-wan-ip>:32400`), which forwards → Plex `<plex-lb-ip>:32400`. Same port
end-to-end. The UDM's "WAN IP is private" warning is expected (it's behind the upstream NAT). If
remote access breaks for no reason, the upstream public IP likely changed — Plex re-detects it
automatically; a dynamic-DNS hostname is the clean long-term fix.

## Unify media — kills the manual NAS copy

Chosen direction: **the k3s tree (`/volume1/k3s/media/media`) is canonical.** Sonarr and Radarr
own the files; Plex follows them.

Never move a file out from under the *arr apps. They store an absolute path per episode/movie,
so a manual move on the NAS makes the item "missing from disk". Plex is a reader, not an owner.

Why a cross-share move is slow: `/volume1/k3s` and `/volume1/Plex` are separate DSM **shared
folders**, so on btrfs they are separate subvolumes. `rename()` returns `EXDEV` and DSM falls back
to copy-then-delete. Inside `/volume1/k3s`, downloads and media share a subvolume, so *arr imports
there are already instant.

### Step A — Plex reads the *arr tree (DONE)

`media-tv` and `media-movies` are mounted **readOnly** at `/media/tv` and `/media/movies`, so
imports appear in Plex with no copy. `plex-versions` is mounted **writable** at
`/media/plex-versions` — readOnly media mounts otherwise break Optimized Versions, which default
to writing `Plex Versions/` beside the source file. `/transcode` is capped at 3Gi (it is an
`emptyDir` on the 20G node root disk, and was previously unbounded).

In the Plex UI, add the new folders to the **existing** libraries — do not create new ones, or you
lose watch history:

- Settings → Libraries → Edit *TV Shows* → Add folder → `/media/tv`
- Settings → Libraries → Edit *Movies* → Add folder → `/media/movies`, and also
  `/media/plex-versions`

Optimized versions: the **Storage Location** dropdown only lists library folder paths when you
optimize a **single item**. Bulk or whole-library optimize collapses to "In folders with original
items", which fails against the readOnly mounts.

### Step B — Copy the legacy library onto the k3s tree

Use DSM → Control Panel → **Task Scheduler → Create → Scheduled Task → User-defined script**, run
as `root`. Do not use File Station: it has no resume, no incremental re-run, and it can reset
mtimes, which scrambles "recently added" in both Plex and Sonarr.

```bash
rsync -a --info=progress2 /volume1/Plex/complete/tv/     /volume1/k3s/media/media/tv/
rsync -a --info=progress2 /volume1/Plex/complete/movies/ /volume1/k3s/media/media/movies/
```

Re-runnable — a second pass copies only what is missing, so it is safe to stop and resume. Leave
the source in place until Plex and the *arr apps both look right.

Space is not a constraint: volume1 is 18T with 12T free. Note that static NFS PV `capacity` values
are decoration — Kubernetes does not enforce them. Only the DSM share quota and volume free space
are real.

### Step C — Adopt the copied files into Sonarr/Radarr

Check both of these **before** importing. Each can cause a lot of damage across a 1TB library:

- `Settings → Media Management → Rename Files`. If on, the import rewrites every filename in the
  legacy library to the *arr naming scheme.
- Quality profile cutoffs. Legacy files below cutoff are treated as upgradable, and the *arr apps
  will queue a redownload for all of them.

Then: Sonarr → `Series → Library Import` → `/tv`, and Radarr → `Movies → Library Import` →
`/movies`.

### Step D — Concerts, then retire the legacy share

Nothing in the *arr stack manages concerts, so it just needs a home on the k3s tree.

1. Create `/volume1/k3s/media/media/concerts` on the NAS.
2. `rsync -a --info=progress2 /volume1/Plex/complete/concerts/ /volume1/k3s/media/media/concerts/`
3. Add a `media-concerts` PV/PVC alongside the others in `../../../infra/nfs-pv/media.yaml`, and
   mount it readOnly at `/media/concerts`.
4. In Plex, add `/media/concerts` to the Concerts library.

Once all three libraries are served from the k3s tree, drop the `plex-library` PV/PVC and the
three `complete/*` subPath mounts from the Deployment. `/volume1/Plex` then holds nothing Plex
needs, and the DSM NFS export rule for that share can go too.

Verify before deleting anything:

```bash
kubectl exec -n media deploy/plex -- df -h /media/tv /media/movies /media/concerts
kubectl exec -n media deploy/plex -- sh -c 'touch /media/tv/.w 2>&1 || echo readOnly-ok'
```

## Phase 4 — Hardware transcoding (DONE 2026-06-22)

iGPU (`0000:00:02`) moved from VM 108 → `k3s-replica-0` (VMID 105). Notes for anyone redoing this:
- VM 108 released it first (`qm set 108 --delete hostpci0`; 108 stopped).
- **Raw passthrough must be set as `root@pam`** — Proxmox forbids the non-root Terraform user
  (`only root can set 'hostpci0' for non-mapped devices`). Set manually:
  `qm stop 105 && qm set 105 --hostpci0 0000:00:02,pcie=1,rombar=1 && qm start 105`.
  Terraform manages `machine=q35` but **ignores `hostpci`** (`ignore_changes`).
- VM needs **q35** for PCIe passthrough. The q35 switch is NIC-safe here because netplan matches
  by MAC (`set-name: eth0`), so it returns on `eth0`/DHCP without console.
- After reboot: `i915` binds, `/dev/dri/renderD128` appears. (Missing DMC firmware warning is
  display-only and irrelevant to transcode.)
- `kubernetes/infra/intel-gpu-plugin/` DaemonSet advertises `gpu.intel.com/i915`; the Plex
  deployment requests `gpu.intel.com/i915: "1"`, which auto-pins it to replica-0 and injects
  `/dev/dri` (no privileged). `HardwareAcceleratedCodecs="1"` enabled in Plex.

## Phase 5 — Decommission VM 108

After a soak, remove Plex from the `docker-htpc` role, then retire the `media` module in
`terraform/main.tf` and the related plays in `site.yml`.
Backup taken before migration:
`local:/var/lib/vz/dump/vzdump-qemu-108-2026_06_22-23_51_34.vma.zst`.
