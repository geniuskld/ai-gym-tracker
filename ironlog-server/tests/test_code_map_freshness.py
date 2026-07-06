"""Freshness guards for docs/architecture/code-map.md.

Keeps the code map honest: every path it names must exist, and every Swift
source / server module must be named somewhere in the map. This forces stale
rows to be pruned and new modules to be documented in the same change.

The checks are skipped when the full repo checkout is not present (e.g. inside
the server Docker image, which copies only ironlog-server/ and schemas/), so
they only run against a developer working tree.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
CODE_MAP = REPO / "docs" / "architecture" / "code-map.md"
APP = REPO / "ironlog-server" / "app"
SWIFT_ROOT = REPO / "IronLog"

# Files that are structural, not navigation targets.
MODULE_ALLOWLIST = {"__init__.py"}

# Generated build outputs that can appear in-tree but are never source; excluding
# them keeps the coverage checks from failing on generated .swift/.py files.
BUILD_DIRS = {"build", ".build", "DerivedData", "__pycache__", ".venv"}

# Anchor to a token start (not mid-path) so shorthand like `app/schemas/__init__.py`
# in prose is not mis-captured as a bogus top-level `schemas/__init__.py`.
_PATH = re.compile(
    r"(?<![\w/])(?:IronLog|ironlog-server|schemas)/[\w./-]+\.(?:swift|py|json)"
)

pytestmark = pytest.mark.skipif(
    not CODE_MAP.exists(),
    reason="code-map.md not present (partial checkout / container build)",
)


def _map_text() -> str:
    return CODE_MAP.read_text(encoding="utf-8")


def _referenced_paths() -> set[str]:
    return set(_PATH.findall(_map_text()))


def test_code_map_paths_exist() -> None:
    """Every file path named in the map must exist on disk."""
    missing = sorted(p for p in _referenced_paths() if not (REPO / p).exists())
    assert not missing, (
        "code-map references missing files; update or remove these rows: "
        + ", ".join(missing)
    )


def test_code_map_covers_all_server_modules() -> None:
    """Every non-trivial app/*.py module must appear in the map."""
    referenced = _referenced_paths()
    missing: list[str] = []
    for f in sorted(APP.rglob("*.py")):
        if f.name in MODULE_ALLOWLIST or "__pycache__" in f.parts:
            continue
        rel = str(f.relative_to(REPO))
        if rel not in referenced:
            missing.append(rel)
    assert not missing, (
        "server modules absent from code-map; add a row: " + ", ".join(missing)
    )


def test_code_map_covers_all_swift_sources() -> None:
    """Every Swift source must appear in the map."""
    if not SWIFT_ROOT.exists():
        pytest.skip("IronLog/ Swift tree not present in this checkout")
    referenced = _referenced_paths()
    missing: list[str] = []
    for f in sorted(SWIFT_ROOT.rglob("*.swift")):
        if BUILD_DIRS & set(f.parts):
            continue
        rel = str(f.relative_to(REPO))
        if rel not in referenced:
            missing.append(rel)
    assert not missing, (
        "Swift sources absent from code-map; add a row: " + ", ".join(missing)
    )
