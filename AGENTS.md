# AGENTS.md

## Purpose and context

This repository is a fork of `unoserver-docker`. The goal is to build a **custom, hardened, network-ready** container image and runtime setup for document conversion (LibreOffice headless + unoserver), suitable for deployment in production-like environments.

“Network-ready” means the image can be deployed as a service exposed over the network with clear operational characteristics: stable interfaces, predictable configuration, safe defaults, and practical observability.

## Working principles

### Proactive engineering
Do not limit yourself to executing the user’s instructions. While implementing requested changes, you must **proactively propose** improvements and best practices that help achieve the repository’s main objective (hardening + network readiness). This includes (but is not limited to):

- hardening measures (least privilege, filesystem restrictions, safe defaults)
- supply-chain hygiene (pinning, reproducibility, provenance)
- operational readiness (health checks, logging, metrics hooks where appropriate)
- maintainability and clarity (documentation, rationale, trade-offs)

When proposing improvements, explain **why** they matter and what the trade-offs are.

### Upstream-friendly changes
Changes must be designed to keep future merges from the upstream repository as smooth as possible.

**Branching rule:** the `main` branch must be kept as close as possible to the upstream `main` (or default) branch and treated as a clean reference for upstream syncs. Customizations should be developed on dedicated branches and/or clearly scoped branches (for example: `hardened/*`, `feature/*`), then integrated with minimal, well-documented deltas.

Guidelines:
- minimize diff footprint where feasible
- avoid large refactors unless clearly justified and discussed
- isolate customizations (for example: additive files, overlays, build arguments, or clearly delimited blocks)
- prefer configuration over code changes when it reduces divergence
- keep commit history clean and well-scoped (small commits with focused intent)

If a requested change would increase divergence, propose an alternative with lower merge friction.

### Language policy
- Chat interaction: **Italian**
- Repository content: **English only**, including:
  - code, comments, docstrings
  - commit messages (when you suggest them)
  - documentation (README, CHANGELOG, SECURITY, etc.)
  - configuration files and error messages intended for operators

Never introduce Italian text into repository files.

## Hardening and security baseline

Apply a “secure by default” stance, consistent with the upstream intent and practicality:

- run as non-root whenever possible
- drop Linux capabilities by default (add only with justification)
- avoid writable filesystem by default where feasible (use explicit writable paths)
- minimize installed packages and image layers
- pin versions where it improves reproducibility and security review
- verify downloads (checksums/signatures) when practical
- avoid embedding secrets in images; use environment variables and mounted secrets

When you add or change security-related behavior, document:
- what threat it mitigates
- what operational impact it has
- how users can override it safely (if needed)

## Tooling recommendations (propose and integrate when appropriate)

You should proactively recommend and, when asked to implement, wire in tools for:

### Linting and style
- `hadolint` for Dockerfile linting
- `shellcheck` for shell scripts

### Vulnerability and configuration scanning
- `trivy` for Common Vulnerabilities and Exposures (CVE) scanning of images and dependencies
- `grype` as an alternative scanner (optional)
- `dockle` for container image best-practices checks
- **`docker-bench-security`** for auditing Docker host and container configuration against the CIS Docker Benchmark

When integrating `docker-bench-security`, clearly state:
- which checks are expected to pass in containerized CI environments
- which findings are informational vs actionable
- any justified deviations from CIS recommendations (with rationale)

### Supply-chain and provenance
- `cosign` for signing images (optional, if the release workflow includes it)
- `syft` for Software Bill of Materials (SBOM) generation; SBOM means Software Bill of Materials (SBOM)

### Continuous Integration
Propose a Continuous Integration (CI) workflow (for example GitHub Actions) that runs:
- Dockerfile linting
- image build
- vulnerability scanning with a clear severity policy
- Docker Bench Security checks (when feasible in the CI environment)
- basic runtime smoke test (container starts, health endpoint responds, sample conversion if feasible)

If the user wants to avoid specific platforms, propose an alternative CI runner.

## Operational interface expectations

When implementing “network-ready” features, prefer predictable, documented interfaces:

- explicit ports and bind addresses
- timeouts and resource limits configurable via environment variables
- health checks (readiness and liveness semantics when applicable)
- structured logging (at least consistent and parseable)
- clear error codes/messages for operators

## Decision-making and communication

When you encounter ambiguity, do the following in order:
1. propose a safe default aligned with the repo goal
2. explain the rationale and trade-offs
3. proceed with an implementation that is easy to adjust (configuration knobs)

Avoid “clever” solutions that reduce transparency or increase merge friction.

## Deliverable expectations

For each meaningful change, provide:
- a short summary of what changed
- why it changed (goal alignment)
- how to test it locally
- notes on upstream merge impact (if any)
- any security implications and operational considerations
