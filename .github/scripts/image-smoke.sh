#!/usr/bin/env bash
# Boot every container image this branch changes and wait for the health check its own
# workload declares. Catches tags that do not resolve, images with no linux/amd64
# variant, and containers that fail to start.
#
# The probe, the port and the environment all come from the manifest, so this stays
# correct when an app changes its URL base or its port.
#
# A container is only started when it can run truthfully here: it must declare a probe
# to check against, and its environment must not depend on a Secret or ConfigMap this
# runner has no access to. Everything else still has its image reference verified
# against the registry.
#
# usage: image-smoke.sh <base-ref> [scope]
set -o errexit -o nounset -o pipefail

BASE_REF="${1:?usage: image-smoke.sh <base-ref> [scope]}"
SCOPE="${2:-.}"

READY_TIMEOUT=180
POLL_INTERVAL=3

for tool in docker jq yq git curl; do
  command -v "$tool" >/dev/null || { echo "required tool not found: ${tool}" >&2; exit 1; }
done

cid=""
failures=0
booted=0
checked=0

# GitHub renders these as annotations on the pull request. Failures point at the manifest
# that introduced the image, so the reviewer lands on the right file instead of digging
# through the job log.
current_file=""
fail() { echo "::error file=${current_file},title=${1}::${2}"; }
warn() { echo "::warning file=${current_file},title=${1}::${2}"; }

cleanup() {
  [ -n "$cid" ] || return 0
  docker rm -f "$cid" >/dev/null 2>&1 || true
  cid=""
}
trap cleanup EXIT

# A registry reference must resolve and offer linux/amd64. Single-architecture images
# return a bare manifest with no .manifests list; docker run would surface any mismatch.
assert_amd64() {
  local image="$1" inspect
  if ! inspect=$(docker manifest inspect "$image" 2>&1); then
    fail "Image not found" "${image} does not resolve in its registry"
    echo "$inspect"
    return 1
  fi
  if jq -e 'has("manifests")' >/dev/null 2>&1 <<<"$inspect"; then
    if ! jq -e '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64")] | length > 0' \
      >/dev/null <<<"$inspect"; then
      fail "No amd64 variant" "${image} publishes no linux/amd64 variant"
      jq -r '.manifests[] | "  \(.platform.os)/\(.platform.architecture)"' <<<"$inspect"
      return 1
    fi
  fi
  echo "registry: resolves, linux/amd64 present"
}

# An env entry with no literal value refers to a Secret or ConfigMap, and envFrom pulls in
# a whole one. Starting such a container here would exercise a configuration that is not
# the real one, so it is left to the registry check.
needs_credentials() {
  jq -e '((.env // [] | map(select(has("value") | not)) | length) + (.envFrom // [] | length)) > 0' \
    >/dev/null <<<"$1"
}

# Probe ports may be named, in which case the name refers to a declared containerPort.
resolve_port() {
  local spec="$1" port="$2"
  if [[ "$port" =~ ^[0-9]+$ ]]; then
    printf '%s' "$port"
    return 0
  fi
  jq -r --arg n "$port" '.ports[]? | select(.name == $n) | .containerPort' <<<"$spec"
}

wait_http() {
  local hostport="$1" path="$2" started="$3" code=000 deadline=$((SECONDS + READY_TIMEOUT))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$cid")" != "true" ]; then
      fail "Container exited" "${name} exited before it served a response"
      return 1
    fi
    code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${hostport}${path}" || echo 000)
    # kubelet treats 2xx and 3xx as a passing httpGet probe.
    if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
      echo "ready: HTTP ${code} on ${path} after $((SECONDS - started))s"
      return 0
    fi
    sleep "$POLL_INTERVAL"
  done
  fail "Never became ready" "no healthy response within ${READY_TIMEOUT}s, last status ${code}"
  return 1
}

# The port must be probed from inside the container. Docker's userland proxy binds the
# published host port as soon as the container starts, so a host-side connect succeeds
# whether or not anything is listening, and would pass every single time.
tcp_probe_tool() {
  if docker exec "$cid" bash -c 'exit 0' >/dev/null 2>&1; then
    echo bash
  elif docker exec "$cid" sh -c 'command -v nc' >/dev/null 2>&1; then
    echo nc
  fi
}

container_port_open() {
  local tool="$1" port="$2"
  case "$tool" in
    bash) docker exec "$cid" bash -c "exec 3<>/dev/tcp/127.0.0.1/${port}" >/dev/null 2>&1 ;;
    nc) docker exec "$cid" sh -c "nc -z 127.0.0.1 ${port}" >/dev/null 2>&1 ;;
  esac
}

wait_tcp() {
  local port="$1" started="$2" tool="$3" deadline=$((SECONDS + READY_TIMEOUT))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$cid")" != "true" ]; then
      fail "Container exited" "${name} exited before it opened its port"
      return 1
    fi
    if container_port_open "$tool" "$port"; then
      echo "ready: port open after $((SECONDS - started))s"
      return 0
    fi
    sleep "$POLL_INTERVAL"
  done
  fail "Never became ready" "port never opened within ${READY_TIMEOUT}s"
  return 1
}

smoke_one() {
  local file="$1" spec="$2"
  local image name path http_port tcp_port port hostport started
  image=$(jq -r '.image' <<<"$spec")
  name=$(jq -r '.name' <<<"$spec")

  current_file="$file"
  echo "declared in ${file}"
  assert_amd64 "$image" || return 1

  if needs_credentials "$spec"; then
    echo "not started: environment depends on a Secret or ConfigMap unavailable here"
    return 0
  fi

  path=$(jq -r '(.readinessProbe.httpGet.path // .livenessProbe.httpGet.path) // ""' <<<"$spec")
  http_port=$(jq -r '(.readinessProbe.httpGet.port // .livenessProbe.httpGet.port) // ""' <<<"$spec")
  tcp_port=$(jq -r '(.readinessProbe.tcpSocket.port // .livenessProbe.tcpSocket.port) // ""' <<<"$spec")

  if [ -n "$http_port" ]; then
    port=$(resolve_port "$spec" "$http_port")
  elif [ -n "$tcp_port" ]; then
    port=$(resolve_port "$spec" "$tcp_port")
  else
    echo "not started: declares no probe to check against"
    return 0
  fi

  if [ -z "$port" ]; then
    fail "Bad probe port" "probe names a port ${name} does not declare"
    return 1
  fi

  local docker_args=()
  local pair
  while IFS= read -r pair; do
    [ -n "$pair" ] && docker_args+=(-e "$pair")
  done < <(jq -r '.env[]? | select(.value != null) | "\(.name)=\(.value)"' <<<"$spec")

  # No volumes on purpose: an empty /config is what a fresh start must survive.
  if ! cid=$(docker run -d -p "127.0.0.1::${port}" "${docker_args[@]}" "$image"); then
    fail "Could not start" "docker run failed for ${image}"
    cid=""
    return 1
  fi
  hostport=$(docker port "$cid" "${port}/tcp" | head -1 | sed 's/.*://')
  if [ -z "$hostport" ]; then
    fail "No host port" "nothing published for container port ${port}"
    docker logs "$cid" 2>&1 | tail -50
    cleanup
    return 1
  fi
  echo "started ${name} on container port ${port}"
  booted=$((booted + 1))

  started=$SECONDS
  local rc=0
  if [ -n "$http_port" ]; then
    wait_http "$hostport" "$path" "$started" || rc=1
  else
    local tool
    tool=$(tcp_probe_tool)
    if [ -z "$tool" ]; then
      warn "Port not verified" "${name} provides neither bash nor nc, so its port could not be probed from inside"
      cleanup
      return 0
    fi
    wait_tcp "$port" "$started" "$tool" || rc=1
  fi

  if [ "$rc" -ne 0 ]; then
    echo "--- last 50 log lines ---"
    docker logs "$cid" 2>&1 | tail -50
  fi
  cleanup
  return "$rc"
}

# CI hands us a branch name that exists as a remote ref; a local run may name any commit.
if git rev-parse --verify --quiet "origin/${BASE_REF}" >/dev/null; then
  BASE="origin/${BASE_REF}"
else
  BASE="$BASE_REF"
fi
DIFF_RANGE="${BASE}...HEAD"

mapfile -t files < <(git diff --name-only "$DIFF_RANGE" -- "$SCOPE" | grep -E '\.ya?ml$' || true)

if [ "${#files[@]}" -eq 0 ]; then
  echo "no YAML changed under ${SCOPE}"
  exit 0
fi

for file in "${files[@]}"; do
  [ -f "$file" ] || continue
  added=$(git diff "$DIFF_RANGE" -- "$file" | grep -E '^\+' || true)
  [ -n "$added" ] || continue

  # Non-Kubernetes YAML elsewhere in the repo simply yields no workloads.
  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    image=$(jq -r '.image // ""' <<<"$spec")
    [ -n "$image" ] || continue
    # Only test images this branch actually introduced.
    grep -qF "image: ${image}" <<<"$added" || continue

    checked=$((checked + 1))
    echo "::group::$(jq -r '.name' <<<"$spec") — ${image}"
    smoke_one "$file" "$spec" || failures=$((failures + 1))
    echo "::endgroup::"
    # CronJob nests the pod spec one level deeper than every other workload kind.
  done < <(yq e -o=json -I=0 \
    'select(.kind == "Deployment" or .kind == "DaemonSet" or .kind == "StatefulSet"
            or .kind == "Job" or .kind == "CronJob" or .kind == "ReplicaSet")
     | (.spec.template.spec // .spec.jobTemplate.spec.template.spec)
     | (.containers[]?, .initContainers[]?)' \
    "$file" 2>/dev/null || true)
done

if [ "$checked" -eq 0 ]; then
  echo "no image changes under ${SCOPE}"
  exit 0
fi

summary="checked ${checked} image(s), started ${booted}, ${failures} failed"
if [ "$failures" -eq 0 ]; then
  echo "::notice title=Image smoke::${summary}"
else
  echo "::error title=Image smoke::${summary}"
fi
[ "$failures" -eq 0 ]
