#!/usr/bin/env bash
# Run a candidate image against a clone of an app's real config volume.
#
# The *arr apps migrate their config database the first time a new version starts, and
# the migration is one way. Reverting the image tag afterwards leaves the old binary
# unable to read the new schema. This runs that migration against a throwaway copy
# first, so a failure costs nothing.
#
# The canary carries its own labels, so no Service or IngressRoute selects it, and it
# mounts only the cloned config, so it cannot touch the media shares. The running app is
# never modified.
#
# Flux does not prune these objects: it only prunes what it applied itself.
#
# usage: canary.sh <app> <image>     start a canary
#        canary.sh <app> --cleanup   remove pod and clone
set -o errexit -o nounset -o pipefail

NAMESPACE=media
READY_TIMEOUT=300
POLL_INTERVAL=5

usage() {
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
  exit 64
}

[ $# -eq 2 ] || usage

APP="$1"
TARGET="$2"
POD="${APP}-canary"
CLONE="${APP}-config-canary"

k() { kubectl -n "$NAMESPACE" "$@"; }

cleanup() {
  echo "removing canary for ${APP}"
  k delete pod "$POD" --ignore-not-found --wait=true --timeout=120s
  k delete pvc "$CLONE" --ignore-not-found --wait=true --timeout=120s
  echo "done"
}

if [ "$TARGET" = "--cleanup" ]; then
  cleanup
  exit 0
fi

# --- gates -------------------------------------------------------------------------

if ! deployment=$(k get deployment "$APP" -o json 2>/dev/null); then
  echo "no deployment ${APP} in namespace ${NAMESPACE}" >&2
  exit 1
fi

available=$(jq -r '.status.conditions[]? | select(.type == "Available") | .status' <<<"$deployment")
if [ "$available" != "True" ]; then
  echo "deployment ${APP} is not Available; fix that before running a canary" >&2
  exit 1
fi

# The claim name is read from the deployment rather than assumed, so a rename cannot
# silently point the canary at the wrong volume.
source_pvc=$(jq -r '.spec.template.spec.volumes[]? | select(.name == "config") | .persistentVolumeClaim.claimName' <<<"$deployment")
if [ -z "$source_pvc" ] || [ "$source_pvc" = "null" ]; then
  echo "deployment ${APP} has no volume named config" >&2
  exit 1
fi

if [ "$(k get pvc "$source_pvc" -o jsonpath='{.status.phase}')" != "Bound" ]; then
  echo "pvc ${source_pvc} is not Bound" >&2
  exit 1
fi

if k get pod "$POD" >/dev/null 2>&1 || k get pvc "$CLONE" >/dev/null 2>&1; then
  echo "a canary for ${APP} already exists; run: $0 ${APP} --cleanup" >&2
  exit 1
fi

size=$(k get pvc "$source_pvc" -o jsonpath='{.spec.resources.requests.storage}')
class=$(k get pvc "$source_pvc" -o jsonpath='{.spec.storageClassName}')

echo "app          ${APP}"
echo "candidate    ${TARGET}"
echo "cloning      ${source_pvc} (${size}, ${class}) -> ${CLONE}"

# --- clone -------------------------------------------------------------------------

# Longhorn implements CSI volume cloning natively, so this needs no snapshot controller.
# The copy is crash consistent, which is what the app would see after a hard power loss.
k apply -f - <<EOF
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${CLONE}
  labels:
    lab.ryanrishi.com/canary: "true"
spec:
  storageClassName: ${class}
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${size}
  dataSource:
    kind: PersistentVolumeClaim
    name: ${source_pvc}
EOF

# --- pod ---------------------------------------------------------------------------

# Built from the live deployment so the canary keeps the real environment, probes,
# resources and node placement. Three things change: the image, the labels, and the
# volumes, which are reduced to the clone alone. Sidecars are dropped because they need
# credentials the canary has no reason to hold.
pod_manifest=$(jq -n \
  --argjson d "$deployment" \
  --arg app "$APP" \
  --arg image "$TARGET" \
  --arg pod "$POD" \
  --arg clone "$CLONE" \
  --arg ns "$NAMESPACE" '
  $d.spec.template.spec as $s |
  {
    apiVersion: "v1",
    kind: "Pod",
    metadata: {
      name: $pod,
      namespace: $ns,
      labels: { app: $pod, "lab.ryanrishi.com/canary": "true" }
    },
    spec: {
      restartPolicy: "Never",
      nodeSelector: $s.nodeSelector,
      dnsConfig: $s.dnsConfig,
      containers: [
        $s.containers[]
        | select(.name == $app)
        | .image = $image
        | .volumeMounts = [ .volumeMounts[]? | select(.name == "config") ]
      ],
      volumes: [ { name: "config", persistentVolumeClaim: { claimName: $clone } } ]
    }
  }
  | .spec |= with_entries(select(.value != null))')

if [ "$(jq '.spec.containers | length' <<<"$pod_manifest")" -ne 1 ]; then
  echo "deployment ${APP} has no container named ${APP}" >&2
  cleanup
  exit 1
fi

jq -r '.' <<<"$pod_manifest" | k apply -f -

# --- wait --------------------------------------------------------------------------

echo "waiting for ${POD} to become ready"
deadline=$((SECONDS + READY_TIMEOUT))
ready=""
while [ "$SECONDS" -lt "$deadline" ]; do
  phase=$(k get pod "$POD" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [ "$phase" = "Failed" ] || [ "$phase" = "Succeeded" ]; then
    echo "canary pod ended in phase ${phase} — the migration did not survive"
    break
  fi
  if [ "$(k get pod "$POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]; then
    ready=1
    break
  fi
  sleep "$POLL_INTERVAL"
done

if [ -z "$ready" ]; then
  echo
  echo "FAILED after ${SECONDS}s. Last 50 log lines:"
  k logs "$POD" --tail=50 2>&1 || true
  echo
  echo "The running ${APP} is untouched. Inspect further, then clean up:"
  echo "  $0 ${APP} --cleanup"
  exit 1
fi

port=$(jq -r '(.spec.containers[0].readinessProbe.httpGet.port // .spec.containers[0].livenessProbe.httpGet.port // .spec.containers[0].livenessProbe.tcpSocket.port) // empty' <<<"$pod_manifest")
path=$(jq -r '(.spec.containers[0].readinessProbe.httpGet.path // .spec.containers[0].livenessProbe.httpGet.path) // ""' <<<"$pod_manifest")

echo
echo "${APP} started on the migrated clone and passed its own health check."
echo "Open the UI and confirm it reads your real data:"
echo "  kubectl -n ${NAMESPACE} port-forward pod/${POD} 8${port}:${port}"
echo "  open http://127.0.0.1:8${port}${path}"
echo
echo "When finished:"
echo "  $0 ${APP} --cleanup"
