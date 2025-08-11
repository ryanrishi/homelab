# K3s Cluster Memory Optimization - August 2025

## Problem Summary
The k3s cluster was experiencing severe stability issues due to memory constraints and resource allocation problems:

- **SystemOOM crashes** on control plane nodes causing constant restarts
- **Monitoring stack pods stuck in Pending** state unable to schedule
- **MetalLB FRR containers OOMKilled** repeatedly, causing network instability  
- **Flux reconciliation blocked** by failed MetalLB Helm releases
- **Node memory overcommit** reaching 100-148% on some nodes
- **Memory ballooning enabled** in Proxmox causing unpredictable allocation

## Root Causes Identified

### 1. **Proxmox Memory Ballooning**
- VMs configured with 4GB but actually receiving much less due to ballooning
- k3s-replica-0: Only 516Mi available vs 4GB configured
- k3s-server-0: Only 1.2GB available vs expected 2GB
- Kubernetes resource scheduling based on incorrect capacity reporting

### 2. **Resource Limit Gaps**
- MetalLB FRR containers had no memory limits, causing unlimited growth
- SystemOOM killer targeting essential routing processes (zebra, bgpd, staticd)
- Memory leaks in FRR v9.0.2 components

### 3. **Dead Node Issues**  
- k3s-replica-2 was deleted but not removed from cluster
- PersistentVolumeClaims bound to dead node preventing pod scheduling
- Stale cluster state blocking workload distribution

### 4. **Flux Configuration Problems**
- Invalid PriorityClass name using reserved `system-` prefix
- MetalLB Helm release stuck in failed state due to etcd leader changes
- Dependency chain blocked: MetalLB failure → Infrastructure failure → Apps blocked

## Solutions Attempted

### ❌ **What Didn't Work**
1. **kubectl patch attempts** - Resource limits couldn't be live-patched effectively
2. **Temporary helm uninstall** - Too risky for LoadBalancer services
3. **Node cordoning only** - DaemonSets continued consuming memory
4. **DNS troubleshooting** - Was symptom, not cause of instability

### ✅ **What Worked**

#### 1. **Proxmox Memory Configuration**
```bash
# For each VM in Proxmox UI:
# - Set Memory to 2048MB (not 4096MB due to 6GB total constraint)
# - Disable "Ballooning Device"  
# - Reboot VM
```

#### 2. **MetalLB Resource Limits** (Permanent Fix)
```yaml
# kubernetes/infra/metallb/release.yaml
speaker:
  resources:
    limits:
      cpu: 100m
      memory: 64Mi
  frr:
    resources:
      limits:
        cpu: 200m
        memory: 128Mi
  frrMetrics:
    resources:
      limits:
        cpu: 100m
        memory: 64Mi
```

#### 3. **Cluster Cleanup**
```bash
# Remove dead node and stuck resources
kubectl delete node k3s-replica-2
kubectl delete pvc prometheus-* -n monitoring  
kubectl delete pvc alertmanager-* -n monitoring
kubectl patch pv <stuck-pv> -p '{"metadata":{"finalizers":null}}'
```

#### 4. **Flux Fixes**
```yaml
# Fixed forbidden PriorityClass name
name: infrastructure-priority  # was: system-infrastructure
```

```bash
# Force MetalLB reconciliation after etcd stabilized
flux reconcile helmrelease metallb -n metallb-system
```

## Final Architecture

### **Before (5 nodes, 6GB+ allocated)**
- k3s-server-0: 1.2GB (90% usage - SystemOOM)
- k3s-server-1: 2GB (scheduling disabled)  
- k3s-server-2: 2GB (healthy)
- k3s-replica-0: 516Mi (148% usage - overcommit)
- k3s-replica-1: ~550Mi (121% usage - overcommit)

### **After (4 nodes, 8GB total)**
- k3s-server-0: 2GB (53% usage - healthy)
- k3s-server-1: 2GB (67% usage - healthy)
- k3s-server-2: 2GB (54% usage - healthy)
- k3s-replica-0: 2GB (33% usage - excellent)

## Key Learnings

### **Memory Ballooning & Kubernetes**
- **Never use memory ballooning** on Kubernetes nodes
- Kubernetes scheduler needs predictable, fixed memory allocation
- VM memory reporting to k8s can be completely wrong with ballooning enabled

### **Resource Limits Are Critical**
- **Always set memory limits** on system components like MetalLB
- Unlimited memory containers can crash entire nodes via SystemOOM
- Resource limits prevent cascading failures across cluster

### **Cluster State Hygiene**  
- **Remove dead nodes immediately** to prevent scheduling issues
- Stuck PersistentVolumes block new workload scheduling
- Clean cluster state is essential for Flux reconciliation

### **Flux Dependency Management**
- Failed infrastructure components block entire application layer
- **Fix infrastructure issues first** before troubleshooting apps
- PriorityClass names with `system-` prefix are reserved by Kubernetes

## Commands for Future Reference

### **Memory Diagnostics**
```bash
kubectl top nodes
kubectl describe nodes | grep -A10 "Allocated resources"
kubectl get events --field-selector type=Warning -A
```

### **Resource Constraint Troubleshooting**
```bash
kubectl get pods -A --field-selector=status.phase=Pending
kubectl describe pod <pending-pod> | grep -A10 Events
```

### **Flux Health Check**
```bash
kubectl get kustomization,helmrelease -A
flux reconcile kustomization <name> -n flux-system
```

### **Safe Node Operations**
```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force
# Perform maintenance
kubectl uncordon <node>
```

## Final Status
✅ **All SystemOOM issues resolved** - No node restarts in 2+ hours  
✅ **Monitoring stack operational** - AlertManager and Prometheus running  
✅ **Flux reconciliation working** - All kustomizations and helm releases healthy  
✅ **Memory usage optimal** - All nodes 33-67% utilization  
✅ **Cluster stability achieved** - Ready for additional physical server expansion  

Total time: ~3 hours of systematic troubleshooting and fixes.