#!/usr/bin/env python3
"""Pytest integration test for office fixture conversion via live unoserver XML-RPC."""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import xmlrpc.client
from pathlib import Path

import pytest

SUPPORTED_SUFFIXES = {
    ".doc",
    ".docx",
    ".xls",
    ".xlsx",
    ".ppt",
    ".pptx",
    ".odt",
    ".ods",
    ".odp",
}

REPO_ROOT = Path(__file__).resolve().parents[1]


def _resolve_dir(env_name: str, default: Path) -> Path:
    raw_value = os.getenv(env_name)
    value = Path(raw_value) if raw_value else default
    return value.expanduser().resolve()


def _collect_supported_files(fixtures_dir: Path) -> list[Path]:
    if not fixtures_dir.is_dir():
        return []
    return sorted(
        p for p in fixtures_dir.iterdir() if p.is_file() and p.suffix.lower() in SUPPORTED_SUFFIXES
    )


def _resolve_endpoint() -> str:
    container_name = os.getenv("CONTAINER_NAME", "unoserver-docker-local")
    container_port = os.getenv("CONTAINER_PORT", "2003")
    protocol = os.getenv("API_PROTOCOL", "http")

    if shutil.which("docker") is None:
        pytest.fail("docker is required on the host to run live conversion tests.")

    ps_cmd = ["docker", "ps", "--format", "{{.Names}}"]
    ps_result = subprocess.run(ps_cmd, check=False, capture_output=True, text=True)
    if ps_result.returncode != 0:
        pytest.fail(f"failed to list running containers: {ps_result.stderr.strip()}")

    running_names = {line.strip() for line in ps_result.stdout.splitlines() if line.strip()}
    if container_name not in running_names:
        pytest.fail(
            f"required running container not found: {container_name}. "
            "Start it first and publish the XML-RPC port."
        )

    port_cmd = ["docker", "port", container_name, f"{container_port}/tcp"]
    port_result = subprocess.run(port_cmd, check=False, capture_output=True, text=True)
    if port_result.returncode != 0:
        pytest.fail(
            f"failed to inspect container port mapping for {container_name}: "
            f"{port_result.stderr.strip()}"
        )

    lines = [line.strip() for line in port_result.stdout.splitlines() if line.strip()]
    if not lines:
        pytest.fail(
            f"container {container_name} is running but port {container_port}/tcp is not published."
        )

    match = re.search(r"(.+):([0-9]+)$", lines[0])
    if not match:
        pytest.fail(f"unable to parse published port mapping: {lines[0]}")

    endpoint_host = match.group(1).strip("[]")
    endpoint_port = match.group(2)
    if endpoint_host in {"0.0.0.0", "::", ""}:
        endpoint_host = "127.0.0.1"

    return f"{protocol}://{endpoint_host}:{endpoint_port}"


OFFICE_FIXTURES_DIR = _resolve_dir("OFFICE_FIXTURES_DIR", _resolve_dir("FIXTURES_DIR", REPO_ROOT / "fixtures/office"))
ZENODO_FIXTURES_DIR = _resolve_dir("ZENODO_FIXTURES_DIR", REPO_ROOT / "fixtures/zenodo")

OFFICE_FILES = _collect_supported_files(OFFICE_FIXTURES_DIR)
ZENODO_FILES = _collect_supported_files(ZENODO_FIXTURES_DIR)
ALL_FILES = [("office", path) for path in OFFICE_FILES] + [("zenodo", path) for path in ZENODO_FILES]
ALL_FILE_IDS = [f"{fixture_set}:{fixture_path.name}" for fixture_set, fixture_path in ALL_FILES]


@pytest.fixture(scope="session")
def endpoint_url() -> str:
    return _resolve_endpoint()


@pytest.fixture(scope="session")
def api_proxy(endpoint_url: str) -> xmlrpc.client.ServerProxy:
    return xmlrpc.client.ServerProxy(endpoint_url, allow_none=True)


def test_fixture_directories_exist() -> None:
    assert OFFICE_FIXTURES_DIR.is_dir(), f"fixtures directory not found: {OFFICE_FIXTURES_DIR}"
    assert ZENODO_FIXTURES_DIR.is_dir(), f"fixtures directory not found: {ZENODO_FIXTURES_DIR}"


def test_supported_fixtures_found() -> None:
    assert OFFICE_FILES, f"no supported fixtures found in {OFFICE_FIXTURES_DIR}"
    assert ZENODO_FILES, f"no supported fixtures found in {ZENODO_FIXTURES_DIR}"


def test_endpoint_info(api_proxy: xmlrpc.client.ServerProxy) -> None:
    info = api_proxy.info()
    assert isinstance(info, dict), f"info() returned unexpected type: {type(info)!r}"
    assert "api" in info, "info() response does not include API version metadata."


@pytest.mark.parametrize(
    ("fixture_set", "fixture_path"),
    ALL_FILES,
    ids=ALL_FILE_IDS,
)
def test_convert_fixture_to_pdf(
    api_proxy: xmlrpc.client.ServerProxy, fixture_set: str, fixture_path: Path
) -> None:
    payload = fixture_path.read_bytes()
    assert payload, f"{fixture_set} fixture is empty: {fixture_path}"

    result = api_proxy.convert(
        None,
        xmlrpc.client.Binary(payload),
        None,
        "pdf",
        None,
        [],
        True,
        None,
    )

    assert result is not None, f"conversion returned no payload for {fixture_set}:{fixture_path.name}"
    pdf_bytes = getattr(result, "data", None)
    assert isinstance(pdf_bytes, (bytes, bytearray)), (
        f"conversion returned unexpected payload type for {fixture_set}:{fixture_path.name}: "
        f"{type(pdf_bytes)!r}"
    )
    assert pdf_bytes, f"conversion returned empty PDF payload for {fixture_set}:{fixture_path.name}"
    assert bytes(pdf_bytes[:4]) == b"%PDF", (
        f"invalid PDF header for {fixture_set}:{fixture_path.name}: "
        f"{bytes(pdf_bytes[:8])!r}"
    )
