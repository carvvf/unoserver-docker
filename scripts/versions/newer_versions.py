#!/usr/bin/env python3
"""Report what a rebuild of the active image would take that the image does not have.

A rebuild of Dockerfile.custom takes the newest release behind the floating base image tag,
the newest unoserver release of UNOSERVER_MAJOR and every Alpine package upgrade. The daily
scan rebuilds when this script prints at least one reason, so a release without HIGH or
CRITICAL findings reaches the published image within a day instead of waiting for the next
commit. Each check asks the same source the rebuild would use:

1. base image: the base tag's layers must be the first layers of the image, per platform;
2. unoserver: pip resolves the requirement inside the image, as the build does;
3. Alpine packages: apk lists the upgrades inside the image after refreshing its index,
   a refresh build/retry.sh retries while a mirror is mid-sync.

Checks 2 and 3 run the image on the runner's platform; the arm64 image is built from the
same releases. Prints one reason per line and exits 0, also when nothing is newer. Any check
that cannot complete exits non-zero: an unknown state never passes as "up to date".

usage: newer_versions.py IMAGE_REF [DOCKERFILE]
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

# Mounted into the image to retry its index update while a mirror is mid-sync.
RETRY_HELPER = Path(__file__).resolve().parents[2] / "build" / "retry.sh"
APK_UPGRADABLE = re.compile(
    r"^(?P<new>\S+) \S+ \{[^}]*\} \([^)]*\) \[upgradable from: (?P<old>\S+)\]$"
)
SHOWN_PACKAGES = 5


class CheckError(Exception):
    """A check could not determine whether something newer exists."""


def parse_base_image(dockerfile: str) -> str:
    """The image of the first FROM instruction."""
    for line in dockerfile.splitlines():
        match = re.match(r"^\s*FROM\s+(?:--platform=\S+\s+)?(\S+)", line, re.IGNORECASE)
        if match:
            return match.group(1)
    raise CheckError("Dockerfile has no FROM instruction.")


def parse_unoserver_requirement(dockerfile: str) -> str:
    """The pip requirement the build installs, from ARG UNOSERVER_MAJOR."""
    match = re.search(r"^ARG UNOSERVER_MAJOR=(\d+)\s*$", dockerfile, re.MULTILINE)
    if not match:
        raise CheckError("Dockerfile has no ARG UNOSERVER_MAJOR=<major>.")
    return f"unoserver=={match.group(1)}.*"


def stale_base_platforms(base: dict[str, list[str]], image: dict[str, list[str]]) -> list[str]:
    """Platforms of the image whose first layers are not the base image's current layers."""
    if not image:
        raise CheckError("The image lists no platform.")
    stale = []
    for platform in sorted(image):
        if platform not in base:
            raise CheckError(f"The base image has no {platform} variant.")
        layers = base[platform]
        if not layers or image[platform][: len(layers)] != layers:
            stale.append(platform)
    return stale


def parse_pip_report(report: str) -> str:
    """The unoserver version of a `pip install --report` resolution."""
    try:
        installs = json.loads(report)["install"]
    except (ValueError, KeyError, TypeError) as error:
        raise CheckError(f"Unreadable pip report: {error}") from error
    versions = [
        item["metadata"]["version"]
        for item in installs
        if item.get("metadata", {}).get("name", "").lower() == "unoserver"
    ]
    if len(versions) != 1:
        raise CheckError(f"The pip report resolves {len(versions)} unoserver releases, not one.")
    return versions[0]


def parse_apk_upgradable(output: str) -> list[tuple[str, str]]:
    """(old, new) package versions from `apk list --upgradable`."""
    upgrades = []
    for line in output.splitlines():
        if not line.strip():
            continue
        match = APK_UPGRADABLE.match(line.strip())
        if not match:
            raise CheckError(f"Unexpected apk list line: {line!r}")
        upgrades.append((match.group("old"), match.group("new")))
    return upgrades


def describe_apk_upgrades(upgrades: list[tuple[str, str]]) -> str:
    shown = ", ".join(f"{old} -> {new}" for old, new in upgrades[:SHOWN_PACKAGES])
    more = len(upgrades) - SHOWN_PACKAGES
    suffix = f", and {more} more" if more > 0 else ""
    return f"{len(upgrades)} Alpine package upgrades: {shown}{suffix}"


def run(*command: str) -> str:
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise CheckError(f"{' '.join(command[:4])} ... failed ({result.returncode}): {detail}")
    return result.stdout


def platform_layers(image_ref: str) -> dict[str, list[str]]:
    output = run("docker", "buildx", "imagetools", "inspect", image_ref, "--format", "{{json .Image}}")
    try:
        configs = json.loads(output)
        if "rootfs" in configs:  # a single-platform image
            raise CheckError(f"{image_ref} is not a multi-platform index.")
        return {platform: config["rootfs"]["diff_ids"] for platform, config in configs.items()}
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        raise CheckError(f"Unreadable image configuration of {image_ref}: {error}") from error


def check_base(image_ref: str, base_ref: str) -> list[str]:
    stale = stale_base_platforms(platform_layers(base_ref), platform_layers(image_ref))
    return [f"newer base image {base_ref} ({', '.join(stale)})"] if stale else []


def check_unoserver(image_ref: str, requirement: str) -> list[str]:
    installed = run(
        "docker", "run", "--rm", "--entrypoint", "python3", image_ref, "-c",
        "import importlib.metadata as m; print(m.version('unoserver'))",
    ).strip()
    resolved = parse_pip_report(run(
        "docker", "run", "--rm", "--entrypoint", "python3", image_ref, "-m", "pip", "install",
        "--dry-run", "--quiet", "--no-cache-dir", "--break-system-packages",
        "--ignore-installed", "--no-deps", "--report", "-", requirement,
    ))
    return [f"unoserver {installed} -> {resolved}"] if resolved != installed else []


def check_apk(image_ref: str) -> list[str]:
    output = run(
        "docker", "run", "--rm", "--user", "root", "-v", f"{RETRY_HELPER}:/mnt/retry.sh:ro",
        "--entrypoint", "sh", image_ref, "-c",
        "sh /mnt/retry.sh apk update --quiet >/dev/null && apk list --upgradable",
    )
    upgrades = parse_apk_upgradable(output)
    return [describe_apk_upgrades(upgrades)] if upgrades else []


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    image_ref = argv[1]
    dockerfile_path = argv[2] if len(argv) == 3 else "Dockerfile.custom"
    try:
        with open(dockerfile_path, encoding="utf-8") as handle:
            dockerfile = handle.read()
        reasons = (
            check_base(image_ref, parse_base_image(dockerfile))
            + check_unoserver(image_ref, parse_unoserver_requirement(dockerfile))
            + check_apk(image_ref)
        )
    except (CheckError, OSError) as error:
        print(f"[newer-versions] {error}", file=sys.stderr)
        return 1
    for reason in reasons:
        print(reason)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
