# Monitoring Stack

This directory contains the monitoring stack for the homelab Kubernetes cluster.

## Components

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert handling and routing
- **Node Exporter**: Node/system metrics
- **kube-state-metrics**: Kubernetes cluster metrics
- **Loki**: Container log aggregation and storage
- **Alloy**: Log collector that ships container logs to Loki

## Access

After deployment, the following services will be available via MetalLB LoadBalancer:

- **Grafana**: `http://<grafana-external-ip>:3000`
  - Admin credentials stored in SOPS-encrypted secret
  - Anonymous access enabled (read-only)

- **Prometheus**: `http://<prometheus-external-ip>:9090`
  - Web UI for querying metrics and viewing targets

- **AlertManager**: `http://<alertmanager-external-ip>:9093`
  - Web UI for managing alerts

## Storage

- **Prometheus**: 15GB of storage with 30-day retention
- **Grafana**: 2GB for dashboards and configuration
- **AlertManager**: 2GB for alert state
- **Loki**: 3GB on `longhorn-single`, 7-day retention (compactor-enforced)

## Logs

Container logs are collected by Alloy (DaemonSet) and stored in Loki. Query them in
Grafana's **Explore** view against the **Loki** datasource, e.g. `{namespace="pihole"}`.

Alloy currently runs on the longhorn-enabled (replica) nodes only — the memory-tight
server/etcd nodes are intentionally excluded. Expanding to server nodes is a future change.

## Resource Limits

The stack is configured with resource limits appropriate for a homelab:
- **Prometheus**: 800Mi memory, 500m CPU
- **Grafana**: 256Mi memory, 200m CPU
- **AlertManager**: 128Mi memory, 100m CPU

## Dashboards

The stack includes default Kubernetes dashboards:
- Cluster overview
- Node metrics
- Pod metrics
- Deployment metrics
- PersistentVolume metrics