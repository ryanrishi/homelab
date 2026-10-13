#!/usr/bin/env bash
# Render the Flux cluster at the base branch and at this commit, and write a pull request
# comment describing what the change does to the rendered resources. A one-line chart bump
# can change dozens of objects; this is where that becomes visible.
#
# Writes into <out-dir>:
#   comment.md  the comment body
#   full.diff   the complete diff, every kind included
#
# usage: flux-diff.sh <base-ref> <out-dir> [run-url]
set -o errexit -o nounset -o pipefail

BASE_REF="${1:?usage: flux-diff.sh <base-ref> <out-dir> [run-url]}"
OUT="${2:?usage: flux-diff.sh <base-ref> <out-dir> [run-url]}"
RUN_URL="${3:-}"

# GitHub rejects comments over 65536 characters. The rest of the comment is small, so
# this leaves room for it and for multibyte characters.
DIFF_BUDGET=50000

# Grafana dashboards (ConfigMaps of minified JSON) and Prometheus alert rules are long
# generated text. Left in, one chart bump fills the comment with them and pushes the
# workload, Service and ServiceMonitor changes out. They stay in full.diff.
OMITTED_KINDS=(ConfigMap PrometheusRule)

mkdir -p "$OUT"
render() { flate diff all --path kubernetes --base "$BASE_REF" -o github "$@"; }

render >"$OUT/full.diff"
skip_args=()
for kind in "${OMITTED_KINDS[@]}"; do
  skip_args+=(--skip-kinds "$kind")
done
render "${skip_args[@]}" >"$OUT/review.diff"
flate diff images --path kubernetes --base "$BASE_REF" >"$OUT/images.txt"

mapfile -t resources < <(grep '^# ' "$OUT/full.diff" | cut -c3- | sort -u)
mapfile -t images < <(grep -v '^\s*$' "$OUT/images.txt" || true)

{
  echo '<!-- flux-diff -->'
  echo '### Rendered Flux diff'
  echo

  if [ "${#resources[@]}" -eq 0 ]; then
    echo 'This change does not alter any rendered resource.'
    exit 0
  fi

  echo "**${#resources[@]}** rendered resources change. **${#images[@]}** images are newly referenced."
  echo

  if [ "${#images[@]}" -gt 0 ]; then
    echo '<details><summary>Newly referenced images</summary>'
    echo
    printf -- '- `%s`\n' "${images[@]}"
    echo
    echo '</details>'
    echo
  fi

  echo '<details><summary>Changed resources</summary>'
  echo
  printf -- '- `%s`\n' "${resources[@]}"
  echo
  echo '</details>'
  echo

  truncated=""
  if [ "$(wc -c <"$OUT/review.diff")" -gt "$DIFF_BUDGET" ]; then
    truncated=", truncated"
  fi
  omitted=$(IFS=,; echo "${OMITTED_KINDS[*]}" | sed 's/,/s and /g')
  echo "<details><summary>Diff (${omitted}s omitted${truncated})</summary>"
  echo
  # Four backticks, so a fence inside a rendered value cannot close this one.
  echo '````diff'
  # Cut at a line boundary so the last line shown is whole.
  awk -v budget="$DIFF_BUDGET" '{ size += length($0) + 1; if (size > budget) exit; print }' "$OUT/review.diff"
  echo '````'
  echo
  echo '</details>'

  if [ -n "$RUN_URL" ]; then
    echo
    echo "The full diff, every kind included, is the \`flux-diff\` artifact of [this run](${RUN_URL})."
  fi
} >"$OUT/comment.md"
