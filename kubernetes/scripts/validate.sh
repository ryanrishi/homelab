#!/usr/bin/env bash

# Taken from https://github.com/fluxcd/flux2-kustomize-helm-example/blob/21486401be9bcdc37e6ebda48a3b68f8350777c9/scripts/validate.sh

# This script downloads the Flux OpenAPI schemas, then it validates the
# Flux custom resources and the kustomize overlays using kubeconform.
# This script is meant to be run locally and in CI before the changes
# are merged on the main branch that's synced by Flux.

# Copyright 2023 The Flux authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Prerequisites
# - yq v4.34
# - kustomize v5.3
# - kubeconform v0.6

set -o errexit
set -o pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plan_file="${script_dir}/../infra/system-upgrade/plan-server.yaml"
gotk_components="clusters/liberty/flux-system/gotk-components.yaml"
schema_dir="/tmp/flux-crd-schemas"

# the Kubernetes version the cluster will run, taken from the k3s version the
# system-upgrade-controller rolls nodes to
KUBERNETES_VERSION="${KUBERNETES_VERSION:-$(yq e '.spec.version' "${plan_file}" | sed 's/^v//; s/+k3s.*//')}"

flux_version="$(awk '/^# Flux Version:/ {print $4; exit}' "${gotk_components}")"

# mirror kustomize-controller build options
kustomize_flags=("--load-restrictor=LoadRestrictionsNone")
kustomize_config="kustomization.yaml"

# SOPS-encrypted documents carry a top-level `sops` key that fails strict validation,
# and are filtered out of the kustomize output below
kubeconform_flags=("-skip=Secret")
kubeconform_config=("-strict" "-ignore-missing-schemas" "-kubernetes-version" "${KUBERNETES_VERSION}" "-schema-location" "default" "-schema-location" "${schema_dir}" "-verbose")

echo "INFO - Validating against Kubernetes ${KUBERNETES_VERSION}"

echo "INFO - Downloading Flux ${flux_version} OpenAPI schemas"
rm -rf "${schema_dir}"
mkdir -p "${schema_dir}/master-standalone-strict"
curl -sL "https://github.com/fluxcd/flux2/releases/download/${flux_version}/crd-schemas.tar.gz" | tar zxf - -C "${schema_dir}/master-standalone-strict"

while IFS= read -r -d $'\0' file;
  do
    echo "INFO - Validating $file"
    yq e 'true' "$file" > /dev/null
done < <(find . -type f -name '*.yaml' -print0)

echo "INFO - Validating clusters"
while IFS= read -r -d $'\0' file;
  do
    kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}" "${file}"
done < <(find ./clusters -maxdepth 2 -type f -name '*.yaml' -print0)

echo "INFO - Validating kustomize overlays"
while IFS= read -r -d $'\0' file;
  do
    echo "INFO - Validating kustomization ${file/%$kustomize_config}"
    kustomize build "${file/%$kustomize_config}" "${kustomize_flags[@]}" | \
      yq e 'select(has("sops") | not)' - | \
      kubeconform "${kubeconform_flags[@]}" "${kubeconform_config[@]}"
done < <(find . -type f -name $kustomize_config -print0)
