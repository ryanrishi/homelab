#!/usr/bin/env bash
# Boot every container image this branch changes and wait for the health check its own
# Deployment declares. Catches tags that do not resolve, images with no linux/amd64
# variant, and containers that fail to start.
#
# The probe, the port and the environment all come from the manifest, so this stays
# correct when an app changes its URL base or its port.
#
# usage: image-smoke.sh <base-ref> [scope]
set -o errexit -o nounset -o pipefail

BASE_REF="${1:?usage: image-smoke.sh <base-ref> [scope]}"
SCOPE="${2:-kubernetes/apps/media}"

# Images that cannot start without credentials this runner does not hold. They get the
# registry check only.
NO_BOOT=(qmcgaw/gluetun)

READY_TIMEOUT=180
POLL_INTERVAL=3

cid=""
failures=0
checked=0

cleanup() {
  [ -n "$cid" ] || return 0
  docker rm -f "$cid" >/dev/null 2>&1 || true
  cid=""
}
trap cleanup EXIT

repo_of() {
  local ref="${1%%@*}"
  printf '%s' "${ref%%:*}"
}

boots() {
  local repo
  repo=$(repo_of "$1")
  local skip
  for skip in "${NO_BOOT[@]}"; do
    [ "$repo" = "$skip" ] && return 1
  done
  return 0
}

# A registry reference must resolve and offer linux/amd64. Single-architecture images
# return a bare manifest with no .manifests list; docker run would surface any mismatch.
assert_amd64() {
  local image="$1" inspect
  if ! inspect=$(docker manifest inspect "$image" 2>&1); then
    echo "FAIL: ${image} does not resolve in its registry"
    echo "$inspect"
    return 1
  fi
  if jq -e 'has("manifests")' >/dev/null 2>&1 <<<"$inspect"; then
    if ! jq -e '[.manifests[] | select(.platform.os == "linux" and .platform.architecture == "amd64")] | length > 0' \
      >/dev/null <<<"$inspect"; then
      echo "FAIL: ${image} publishes no linux/amd64 variant"
      jq -r '.manifests[] | "  \(.platform.os)/\(.platform.architecture)"' <<<"$inspect"
      return 1
    fi
  fi
  echo "registry: resolves, linux/amd64 present"
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
  local hostport="$1" path="$2" code=000 deadline=$((SECONDS + READY_TIMEOUT))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$cid")" != "true" ]; then
      echo "FAIL: container exited before it served a response"
      return 1
    fi
    code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${hostport}${path}" || echo 000)
    # kubelet treats 2xx and 3xx as a passing httpGet probe.
    if [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
      echo "ready: HTTP ${code} on ${path} after ${SECONDS}s"
      return 0
    fi
    sleep "$POLL_INTERVAL"
  done
  echo "FAIL: no healthy response within ${READY_TIMEOUT}s, last status ${code}"
  return 1
}

wait_tcp() {
  local hostport="$1" deadline=$((SECONDS + READY_TIMEOUT))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$cid")" != "true" ]; then
      echo "FAIL: container exited before it opened its port"
      return 1
    fi
    if timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/${hostport}" 2>/dev/null; then
      echo "ready: port open after ${SECONDS}s"
      return 0
    fi
    sleep "$POLL_INTERVAL"
  done
  echo "FAIL: port never opened within ${READY_TIMEOUT}s"
  return 1
}

smoke_one() {
  local file="$1" spec="$2"
  local image name path http_port tcp_port port hostport
  image=$(jq -r '.image' <<<"$spec")
  name=$(jq -r '.name' <<<"$spec")

  echo "declared in ${file}"
  assert_amd64 "$image" || return 1

  if ! boots "$image"; then
    echo "skipping boot: needs credentials unavailable in CI"
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
    echo "skipping boot: container declares no probe to check against"
    return 0
  fi

  local docker_args=()
  local pair
  while IFS= read -r pair; do
    [ -n "$pair" ] && docker_args+=(-e "$pair")
  done < <(jq -r '.env[]? | select(.value != null) | "\(.name)=\(.value)"' <<<"$spec")

  # No volumes on purpose: an empty /config is what a fresh start must survive.
  if ! cid=$(docker run -d -p "127.0.0.1::${port}" "${docker_args[@]}" "$image"); then
    echo "FAIL: could not start ${image}"
    cid=""
    return 1
  fi
  hostport=$(docker port "$cid" "${port}/tcp" | head -1 | sed 's/.*://')
  if [ -z "$hostport" ]; then
    echo "FAIL: no host port published for container port ${port}"
    docker logs "$cid" 2>&1 | tail -50
    cleanup
    return 1
  fi
  echo "started ${name} on container port ${port}"

  local rc=0
  if [ -n "$http_port" ]; then
    wait_http "$hostport" "$path" || rc=1
  else
    wait_tcp "$hostport" || rc=1
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
  echo "no manifests changed under ${SCOPE}"
  exit 0
fi

for file in "${files[@]}"; do
  [ -f "$file" ] || continue
  added=$(git diff "$DIFF_RANGE" -- "$file" | grep -E '^\+' || true)
  [ -n "$added" ] || continue

  while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    image=$(jq -r '.image' <<<"$spec")
    # Only test images this branch actually introduced.
    grep -qF "image: ${image}" <<<"$added" || continue

    checked=$((checked + 1))
    echo "::group::$(jq -r '.name' <<<"$spec") — ${image}"
    smoke_one "$file" "$spec" || failures=$((failures + 1))
    echo "::endgroup::"
  done < <(yq e -o=json -I=0 \
    'select(.kind == "Deployment") | (.spec.template.spec.containers[], .spec.template.spec.initContainers[]?)' \
    "$file")
done

if [ "$checked" -eq 0 ]; then
  echo "no image changes under ${SCOPE}"
  exit 0
fi

echo "checked ${checked} image(s), ${failures} failed"
[ "$failures" -eq 0 ]
