# Third-Party Licenses and Compliance Notice

This document describes third-party software and data included in this repository and in container images built from `Dockerfile.custom`.

It is intended to support practical license compliance for redistribution through GHCR and other registries.

## Scope

- Primary artifact: `ghcr.io/carvvf/unoserver-docker` (images built from `Dockerfile.custom`)
- Build definition: `Dockerfile.custom`
- Upstream compatibility note: `Dockerfile` is kept close to upstream for merge friendliness and is not the primary release artifact in this fork.

## First-Party License

- Repository license: MIT (see `LICENSE`)

## Third-Party Runtime Components (Container Image)

The image includes software from multiple upstream projects and package ecosystems.

Key components:

| Component | Version (observed) | Declared license signal | Upstream |
|---|---|---|---|
| Eclipse Temurin JRE (OpenJDK) | `25.0.2+10` | GPL-2.0 with OpenJDK exceptions (see in-image legal files) | https://github.com/adoptium/containers |
| Alpine Linux packages | Alpine `3.23` ecosystem | Mixed (MIT, Apache-2.0, BSD, MPL, GPL/LGPL, OFL, others) | https://www.alpinelinux.org/ |
| LibreOffice | `25.8.1.1-r5` | MPL-2.0 | https://www.libreoffice.org/ |
| unoserver (Python) | `3.4` | MIT | https://github.com/unoconv/unoserver |
| supervisor | `4.3.0` | BSD-family | http://supervisord.org/ |

Fonts installed by the image include packages under OFL-1.1, Apache-2.0, MIT, and GPL-family licenses (for example `font-freefont` and `font-liberation-sans-narrow`).

## Compliance-Relevant Copyleft Signals

License scans over the published image (`ghcr.io/carvvf/unoserver-docker:latest`, digest `sha256:eb9b064c9af6eccbbdb83acb97822d6f4f1b100e94cb300ea135fc75bbf70116`) identified copyleft packages in the OS layer (examples: `bash`, `coreutils`, `readline`, `qt6-*`, `font-freefont`).

This is expected for a full document-conversion stack and does not automatically prohibit distribution, but it creates redistribution obligations.

Focused denylist scan for strong network/commercial copyleft signals:

- AGPL: not detected
- SSPL: not detected
- BUSL-1.1: not detected

## Redistribution Obligations

When redistributing container images from this repository:

1. Keep copyright and license notices intact.
2. Preserve in-image legal files, especially:
   - `/opt/java/openjdk/legal`
   - `/usr/share/licenses` (where available)
3. Provide recipients access to corresponding source code where required by copyleft licenses (GPL/LGPL/MPL components).
4. Preserve this document and the root `LICENSE` file in source distributions.
5. If you modify and redistribute covered components, provide required modification notices and offer corresponding sources for your modified parts.

## Source Code Availability and Written Offer Process

For third-party components included through Alpine, PyPI, LibreOffice, and OpenJDK ecosystems, source is available from upstream project/package sources.

Project policy for redistributed images:

- Source and license requests can be submitted via GitHub Issues:
  - https://github.com/carvvf/unoserver-docker/issues
  - Suggested issue title prefix: `[license-request]`
- Requesters should include image digest/tag and architecture.
- Maintainers should respond with:
  - exact component/version mapping from SBOM
  - upstream source locations
  - any fork-local patches applied to third-party code (if applicable)

Useful upstream source locations:

- Alpine package/build recipes: https://gitlab.alpinelinux.org/alpine/aports
- Alpine package index: https://pkgs.alpinelinux.org/packages
- LibreOffice source releases: https://download.documentfoundation.org/libreoffice/src/
- OpenJDK project sources: https://openjdk.org/
- unoserver source: https://github.com/unoconv/unoserver

## Repository Third-Party Test Data

This repository also ships fixture files under third-party content licenses:

- `fixtures/office/*`: CC0 1.0 (public domain dedication), provenance documented in `fixtures/office/README.md`
- `fixtures/zenodo/*`: CC BY 4.0, provenance and record mapping documented in `fixtures/zenodo/README.md`

When redistributing repository sources, keep those fixture README files and attribution/provenance metadata.

## Operational Compliance Workflow (Recommended)

For each release tag:

1. Build from `Dockerfile.custom`.
2. Generate an SBOM (SPDX and/or CycloneDX).
3. Run vulnerability and license scans.
4. Archive artifacts with the release:
   - SBOM
   - license scan report
   - vulnerability scan report
   - this `THIRD_PARTY_LICENSES.md`

Example commands:

```bash
docker build -f Dockerfile.custom -t ghcr.io/carvvf/unoserver-docker:local .

# existing repository task/script
scripts/trivy/scan-image.sh

# optional SBOM generation (if syft is available)
syft ghcr.io/carvvf/unoserver-docker:local -o spdx-json > reports/sbom.spdx.json
syft ghcr.io/carvvf/unoserver-docker:local -o cyclonedx-json > reports/sbom.cdx.json

# optional dedicated license scan (if trivy supports scanner in your environment)
trivy image --scanners license ghcr.io/carvvf/unoserver-docker:local
```

## Notes

- OCI label `org.opencontainers.image.licenses` is a compact metadata field and is not a complete license inventory for a multi-package container image.
- This file is the canonical human-readable compliance companion in this repository.
- This document is operational guidance and not legal advice.
