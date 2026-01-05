# Pi-hole FTL Database Repair Runbook (k3s)

This runbook fixes a blank Query Log caused by a corrupted Pi-hole FTL SQLite database and documents mitigation options.

## Symptoms
- Web UI Query Log is empty.
- Pod logs show SQLite errors such as:
  - `database disk image is malformed`
  - `Database not available` / `Failed to attach disk database`

## Quick Fix (Rebuild DB)

1) Identify the Pi-hole pod

```bash
kubectl get pods -n pihole -l app=pihole
```

2) Back up the corrupted DB inside the pod

```bash
POD=$(kubectl get pods -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}')
TS=$(date +%Y%m%d-%H%M%S)
kubectl exec -n pihole "$POD" -- sh -lc "set -e; cd /etc/pihole; cp -p pihole-FTL.db pihole-FTL.db.corrupt-$TS"
```

3) Move the corrupted DB out of the way so FTL creates a new one

```bash
kubectl exec -n pihole "$POD" -- sh -lc "set -e; cd /etc/pihole; mv -f pihole-FTL.db pihole-FTL.db.corrupt-$TS"
```

4) Restart the deployment

```bash
kubectl -n pihole rollout restart deployment/pihole
kubectl -n pihole rollout status deployment/pihole --timeout=120s
```

5) Verify in logs

```bash
POD=$(kubectl get pods -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n pihole "$POD" --tail=200 | sed -n '1,120p'
```

Expected:
- Message indicating no DB found and creation of a new DB
- No `malformed` SQLite errors
- Query log begins populating with new traffic

## Notes on NFS and FTL DB
- The Pi-hole data PVC here uses NFS. SQLite file locks on NFS can be unreliable, leading to messages like `Cannot get exclusive lock ... Bad file descriptor` and increased risk of corruption.
- Mitigations:
  - Reduce DB retention to keep the file smaller (e.g., 30 days). For TOML-based FTL config, set `database.maxDBdays = 30` (env var `FTLCONF_database_maxDBdays=30`). Apply via your Helm/manifest and restart.
  - Consider storing only the FTL DB on local disk (e.g., a separate `emptyDir` volume mounted at `/etc/pihole` for the DB file only) while keeping the rest of Pi-hole data on NFS. This requires adjusting mounts so the DB path is on non-NFS storage.
  - Ensure clean shutdowns and avoid abrupt node restarts to reduce corruption risk.

## Optional: Attempt DB Salvage
If historical data is important, you can try to salvage with `sqlite3` inside the pod (only if `sqlite3` is available):

```bash
# Export as SQL; errors may still occur on severe corruption
kubectl exec -n pihole "$POD" -- sh -lc \
  'cd /etc/pihole && sqlite3 pihole-FTL.db.corrupt-$TS \
   ".mode insert" \
   ".output export-$TS.sql" \
   ".dump"'

# Create a new DB and import (stop FTL by restarting the pod after replacing DB)
kubectl exec -n pihole "$POD" -- sh -lc \
  'cd /etc/pihole && rm -f pihole-FTL.db && sqlite3 pihole-FTL.db < export-$TS.sql || true'

# Then restart the deployment again
kubectl -n pihole rollout restart deployment/pihole
```

This may only partially recover data and is not guaranteed on malformed schema.

## Validation
- Query Log shows new entries
- No SQLite errors in pod logs
- `ls -lh /etc/pihole/pihole-FTL.db` shows a small, newly created DB file

## Post-Fix Hardening (Recommended)
- Set DB retention lower (e.g., 30 days) to minimize file size:
  - `FTLCONF_database_maxDBdays=30`
- Evaluate moving FTL DB off NFS onto local storage to avoid NFS locking quirks.
- Ensure regular Pi-hole updates (Core/Web/FTL) via your deployment method.

