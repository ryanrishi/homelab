# Upgrading media app images

Renovate proposes new tags for the apps in this directory. This is how those tags get
tested before they reach the running cluster, and how to recover when one goes bad.

## Why these upgrades need care

Every app here runs as a single replica with `strategy: Recreate` and a ReadWriteOnce
Longhorn config volume. Sonarr, Radarr, Prowlarr and Ombi migrate their config database
the first time a new version starts.

**That migration is one way.** If you revert the image tag afterwards, the old binary
cannot read the new schema, and the app stays broken. A git revert alone is not a
rollback. This is the reason for the snapshot step below.

## The three layers

| Layer | Runs | Catches |
|---|---|---|
| `validate` job | every PR, automatic | manifest schema and removed APIs |
| `image-smoke` job | every PR, automatic | tags that do not exist, no linux/amd64, containers that fail to start |
| `canary.sh` | by hand, before merge | config migrations that fail against your real data |

`image-smoke` covers every workload manifest in the repo, not just this directory. It
starts a container only when it can do so truthfully: the workload must declare a probe,
and its environment must not depend on a Secret or ConfigMap that CI cannot read.
Everything else still has its image reference checked against the registry, which is what
catches a tag that does not exist. Images set inside HelmRelease values are **not**
covered — they are not workload manifests.

It starts the image with an **empty** config. It proves the container boots. It says
nothing about your data. That is what the canary is for.

## Patch bumps

The smoke test proves the container starts from scratch. It does not exercise your config
database, and *arr patch releases do sometimes carry schema changes, so a patch bump is
lower risk than a minor one rather than risk free.

Merge on green CI. If that app matters to you at the time, snapshot it first — the
snapshot is cheap and is the only thing that makes a bad migration recoverable.

## Minor and major bumps

Take a snapshot, run the canary, then merge.

### 1. Snapshot the config volume

Longhorn names its volumes after the PV, so look that up first.

```bash
kubectl -n media get pvc sonarr-config -o jsonpath='{.spec.volumeName}'
```

Create the snapshot with that value as `spec.volume`:

```bash
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: sonarr-pre-4-0-19
  namespace: longhorn-system
spec:
  volume: <pvc-uuid-from-above>
  createSnapshot: true
EOF
```

### 2. Run the canary

```bash
./kubernetes/scripts/canary.sh sonarr lscr.io/linuxserver/sonarr:4.0.19
```

This clones the config volume, starts the candidate image against the clone, and waits
for the app's own readiness probe. The running app is never touched, and the canary
mounts no media shares.

If it fails, the script prints the logs and leaves everything in place so you can look.
The upgrade is simply not merged.

If it passes, open the UI and confirm the app reads your real data — a clean start with
an empty library also passes a readiness probe, so the probe alone does not prove the
migration worked. The script prints the exact `port-forward` command.

Then clean up:

```bash
./kubernetes/scripts/canary.sh sonarr --cleanup
```

Check `pve002` has headroom before starting a canary. It is the constrained host.

### 3. Merge

Flux reconciles within its interval. Watch the Recreate cycle:

```bash
kubectl -n media get pods -w
```

## Rollback

The canary makes this rare, but the procedure matters when you need it.

1. Revert the tag in git and push. Wait for Flux, or reconcile it.
2. Scale the app to zero. Longhorn cannot revert a volume that is attached.
   ```bash
   kubectl -n media scale deployment/sonarr --replicas=0
   ```
3. In the Longhorn UI, open the volume, find the snapshot from step 1, and revert to it.
4. Scale back up.
   ```bash
   kubectl -n media scale deployment/sonarr --replicas=1
   ```

Steps 2 to 4 are downtime for that one app. Nothing else is affected.

## What the canary does not cover

- **byparr** is pinned by digest and **plex** is pinned to a frozen tag, so Renovate does
  not propose updates for either. See `plex/README.md`.
- **gluetun** needs VPN credentials, so CI checks that its image resolves but does not
  start it. The same applies to cloudflared, camping-bot and anything else reading a
  Secret. Watch qbittorrent connectivity by hand after a gluetun bump.
- The canary migrates the **clone's** database. The running app still performs its own
  migration when you merge. The canary proves the migration succeeds against your data;
  it does not do the migration for you.
