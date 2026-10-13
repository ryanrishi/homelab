# Longhorn

## Daily config snapshots

`recurringjob-config-snapshot.yaml` snapshots every volume in the `config` group once a day
and keeps a week of them. It exists so that an upgrade that migrates a config database
always has a recent point to revert to.

A volume joins the group through 2 labels on its PVC. Longhorn copies them to the volume:

```yaml
recurring-job.longhorn.io/source: enabled
recurring-job-group.longhorn.io/config: enabled
```

The Prometheus TSDB and Loki are deliberately left out. Their data is rewritten constantly,
so each snapshot would keep every overwritten block alive and fill the data disks.

### PVCs labeled by hand

Most members carry the labels in this repo: the media config PVCs and Grafana's PVC (through
`grafana.persistence.extraPvcLabels` in the kube-prometheus-stack values).

Two PVCs cannot. They come from StatefulSet `volumeClaimTemplates`, which are immutable, so
adding the labels through the chart would make the Helm upgrade fail. They were labeled
directly on the cluster:

| PVC | Namespace |
|---|---|
| `home-assistant-home-assistant-0` | `home-assistant` |
| `alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0` | `monitoring` |

Nothing in git restores these labels. If either PVC is recreated — a reinstall, a restore,
a storage migration — label it again:

```bash
kubectl -n <namespace> label pvc <pvc> \
  recurring-job.longhorn.io/source=enabled \
  recurring-job-group.longhorn.io/config=enabled
```

### Checking membership

```bash
kubectl -n longhorn-system get volumes.longhorn.io \
  -l recurring-job-group.longhorn.io/config=enabled
```

Volume names are PV names; `kubectl get pv` maps them back to their PVCs.
