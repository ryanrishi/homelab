# Plex migration to k3s

Brings Plex off the legacy media VM (id 108, `192.168.4.101`, `docker-htpc` Ansible role,
`linuxserver/plex:1.32.0`) into k3s.

The canonical Plex library already lives on the NAS (`192.168.4.127`) at
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

LoadBalancer IP is `SVC_PLEX_IP` = `192.168.4.235` (`.232`/`.233` are taken by the two traefik
installs).

## Step 1 — Push storage + service scaffolding

Commit and push (Flux reconciles): the `nfs-plex-library-pv` PV, the `plex-config` (Longhorn) +
`plex-library` PVCs, the LoadBalancer service (`SVC_PLEX_IP` = `192.168.4.235`).

```bash
kubectl get pvc -n media plex-config plex-library   # both Bound
```

## Step 2 — Migrate Plex config into the Longhorn PVC

Stop the VM's Plex so the SQLite DB is quiesced (begins brief Plex downtime), then stream the
~1.6 GB config straight into the PVC via a helper pod.

```bash
# quiesce the source
ssh ryan@192.168.4.101 'cd /opt/docker-htpc && docker compose stop plex'

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
ssh ryan@192.168.4.101 'sudo tar czf - -C /opt/docker-htpc/plex/config .' \
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
   kubectl get svc -n media plex          # EXTERNAL-IP == 192.168.4.235
   kubectl logs -n media -l app=plex --tail=50
   ```
   Browse `http://192.168.4.235:32400/web` — library, posters, watch history intact, items play.
5. Update DNS / reverse proxy and Plex's custom server access URL if needed.

### Rollback
Remove the deployment line + push (Flux removes the pod), then
`ssh ryan@192.168.4.101 'cd /opt/docker-htpc && docker compose start plex'`. The migrated PVC is a
copy — the VM's original config is untouched. (Do not run both Plex servers at once.)

## Later: unify media (kills the manual NAS copy)

Decide one canonical location so Plex and the *arr stack share it:
- **Keep `/volume1/Plex/complete`** (current Plex library): repoint Sonarr/Radarr root folders +
  download handling there. Smallest data move (only the unmerged *arr delta in
  `/volume1/k3s/media/media`).
- **Move to the k3s tree** (`/volume1/k3s/media/media`): consolidate the Plex library onto it and
  switch the Plex `plex-library` PV/PVC to it (keep the same `/tv`,`/movies`,`/concerts`
  in-container paths so the library DB is undisturbed).

## Phase 4 — Hardware transcoding (follow-on)

The NUC iGPU is **already** passed to VM 108 (`hostpci0: 0000:00:02.0`). HW transcode = *moving*
that PCI device to `k3s-replica-0` (Terraform `hostpci`), deploying the Intel GPU device plugin,
labeling the node, and adding a `gpu.intel.com/i915` request + `/dev/dri` to the deployment.
Pins Plex to that node. Folds into VM 108 decommission (it must release the iGPU first).

## Phase 5 — Decommission VM 108

After a soak, remove Plex from the `docker-htpc` role, then retire the `media` module in
`terraform/main.tf` and the related plays in `site.yml`.
Backup taken before migration:
`local:/var/lib/vz/dump/vzdump-qemu-108-2026_06_22-23_51_34.vma.zst`.
