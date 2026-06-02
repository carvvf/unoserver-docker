# AppArmor profile for unoserver Docker

This repository ships an optional host-side AppArmor profile for Ubuntu 24.04
and compatible AppArmor-enabled Linux hosts. The profile is named
`docker-unoserver` and is intended to be used in addition to the existing
container hardening options:

- non-root container user
- `no-new-privileges`
- dropped Linux capabilities
- read-only root filesystem
- explicit writable tmpfs path for `/tmp`

## Threat model

The profile limits what a compromised LibreOffice or unoserver process can do
inside the container namespace. It denies raw and packet network sockets,
mounting, device creation, ptrace, writes to kernel-facing pseudo filesystems,
and writes to common immutable image paths. It also denies access to `/data`
because the network service is stateless and must not depend on Docker volumes
or host bind mounts.

This is defense in depth. Docker's default AppArmor profile already provides a
broad baseline, while this profile documents the expected writable paths for
this image and makes accidental non-read-only runs less permissive.

## Operational impact

The profile expects conversion workloads to write only to:

- `/tmp`
- `/run`
- `/var/run`

For the hardened local runtime, keep `HOME=/tmp`, `--read-only`, and
`--tmpfs /tmp`. Do not configure Docker volumes or host bind mounts for this
service. If an operator adds a mount, that change must be reviewed as a contract
change before production use.

AppArmor cannot prevent the Docker daemon from attaching a bind mount or Docker
volume before the container process starts. This profile instead makes `/data`
unusable to the confined process and denies mount operations from inside the
container. Enforce the "no volumes, no host bind mounts" rule in Docker Compose,
CI checks, or a Docker authorization policy.

## Enable or disable the profile

Run the helper from the repository root:

```bash
scripts/apparmor/unoserver-profile.sh check
sudo scripts/apparmor/unoserver-profile.sh enable
scripts/apparmor/unoserver-profile.sh status
```

Disable and unload the profile:

```bash
sudo scripts/apparmor/unoserver-profile.sh disable
```

Remove the installed host copy:

```bash
sudo scripts/apparmor/unoserver-profile.sh remove
```

The script installs the profile to `/etc/apparmor.d/docker-unoserver` by
default. Override the profile name or AppArmor directory with:

```bash
APPARMOR_PROFILE=docker-unoserver \
APPARMOR_DIR=/etc/apparmor.d \
scripts/apparmor/unoserver-profile.sh status
```

## Use with Docker

After enabling the profile on the host:

```bash
docker run \
  --security-opt no-new-privileges:true \
  --security-opt apparmor=docker-unoserver \
  --cap-drop ALL \
  --read-only \
  --tmpfs /tmp \
  -e HOME=/tmp \
  -p 127.0.0.1:2003:2003 \
  ghcr.io/carvvf/unoserver-docker:latest
```

For the local helper:

```bash
APPARMOR_PROFILE=docker-unoserver scripts/unoserver/run-local.sh
```

For Docker Compose:

```bash
sudo scripts/apparmor/unoserver-profile.sh enable
docker compose \
  -f docker-compose.latest.yml \
  -f docker-compose.apparmor.yml \
  up
```

## Troubleshooting

Check host status:

```bash
sudo apparmor_status
```

Look for denials:

```bash
sudo journalctl -k -g 'apparmor="DENIED"'
```

For production tuning, reproduce the expected conversion workload with the
profile enabled and review denials before widening the policy. Prefer adding
explicit writable paths over broadening access to the full filesystem.

## Upstream merge impact

The implementation is additive: it does not change the upstream `Dockerfile`.
The only runtime integration point is an optional `APPARMOR_PROFILE` environment
variable in local tooling and an optional Compose override file.
