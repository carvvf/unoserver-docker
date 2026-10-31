#!/usr/bin/env bash
set -euo pipefail

# Prints the newest aquasec/trivy image on the reviewed release line, for example
# aquasec/trivy:0.76.1. Trivy is still 0.x, so a new minor line can change flags and
# results and needs a review before TRIVY_LINE moves. Patch releases on the line carry
# backported fixes (0.76.1 ships Go 1.27.3 for CVE-2026-111943) and are taken as soon
# as they are published. CI and scan-image.sh resolve the scanner here.
TRIVY_LINE="0.76"
TRIVY_FLOOR="0.76.1"
TAGS_URL="https://hub.docker.com/v2/repositories/aquasec/trivy/tags?page_size=100&name=${TRIVY_LINE}."

fail() {
  printf '%s\n' "${1}" >&2
  exit "${2:-1}"
}

command -v curl >/dev/null 2>&1 || fail "[Trivy] curl is required to resolve the scanner image." 127
command -v python3 >/dev/null 2>&1 || fail "[Trivy] python3 is required to resolve the scanner image." 127

# A registry error stops the caller instead of falling back to an older scanner.
version="$(
  TAGS_URL="${TAGS_URL}" TRIVY_LINE="${TRIVY_LINE}" python3 -I -c '
import json, os, re, sys, urllib.request

line = os.environ["TRIVY_LINE"]
pattern = re.compile(r"^" + re.escape(line) + r"\.(\d+)$")
url, patches = os.environ["TAGS_URL"], []
while url:
    with urllib.request.urlopen(url, timeout=30) as response:
        page = json.load(response)
    patches += [int(m.group(1)) for t in page["results"] if (m := pattern.match(t["name"]))]
    url = page.get("next")
if not patches:
    sys.exit(f"[Trivy] No aquasec/trivy:{line}.N tag found on Docker Hub.")
print(f"{line}.{max(patches)}")
'
)" || fail "[Trivy] Cannot resolve the newest aquasec/trivy ${TRIVY_LINE}.x image." 1

lowest="$(printf '%s\n%s\n' "${version}" "${TRIVY_FLOOR}" | sort -V | head -n 1)"
if [ "${version}" != "${TRIVY_FLOOR}" ] && [ "${lowest}" = "${version}" ]; then
  fail "[Trivy] Newest aquasec/trivy ${TRIVY_LINE}.x is ${version}, below the ${TRIVY_FLOOR} floor." 1
fi

printf 'aquasec/trivy:%s\n' "${version}"
