#!/usr/bin/env python3
"""Sync and verify vendored Heddle wire schemas.

The canonical JSON Schemas are exported by the sibling ``getheddle/heddle``
repository. This tool copies those schemas into ``schemas/v1`` and maintains a
small manifest of hashes so CI can detect accidental local drift.
"""

from __future__ import annotations

import argparse
import filecmp
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SCHEMA_VERSION = "v1"
MANIFEST_PATH = ROOT / "schemas" / "manifest.json"
UPSTREAM_REPOSITORY = "getheddle/heddle"


def _schema_dir(root: Path, version: str) -> Path:
    return root / "schemas" / version


def _schema_files(schema_dir: Path) -> list[Path]:
    if not schema_dir.exists():
        raise SystemExit(f"Schema directory does not exist: {schema_dir}")
    files = sorted(schema_dir.glob("*.schema.json"))
    if not files:
        raise SystemExit(f"No schema files found in: {schema_dir}")
    return files


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _git_commit(path: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(path), "rev-parse", "HEAD"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return result.stdout.strip()


def _manifest(schema_root: Path, version: str, upstream: Path | None) -> dict[str, Any]:
    schemas = {
        path.name: {"sha256": _sha256(path)}
        for path in _schema_files(_schema_dir(schema_root, version))
    }
    source: dict[str, Any] = {
        "repository": UPSTREAM_REPOSITORY,
        "path": f"schemas/{version}",
    }
    if upstream is not None:
        commit = _git_commit(upstream)
        if commit is not None:
            source["commit"] = commit
    return {
        "schema_version": version,
        "source": source,
        "schemas": schemas,
    }


def _render_manifest(data: dict[str, Any]) -> str:
    return json.dumps(data, indent=2, sort_keys=True) + "\n"


def _load_manifest() -> dict[str, Any]:
    if not MANIFEST_PATH.exists():
        raise SystemExit(f"Missing schema manifest: {MANIFEST_PATH}")
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def _write_manifest(version: str, upstream: Path | None) -> None:
    MANIFEST_PATH.write_text(
        _render_manifest(_manifest(ROOT, version, upstream)),
        encoding="utf-8",
    )


def _check_manifest(version: str) -> int:
    expected = _render_manifest(_manifest(ROOT, version, upstream=None))
    actual_data = _load_manifest()

    # The upstream commit is historical sync metadata. Do not require a local
    # upstream checkout for CI; compare only local schema version and hashes.
    if "source" in actual_data:
        actual_data["source"].pop("commit", None)
    actual = _render_manifest(actual_data)

    if expected == actual:
        print("schema manifest is in sync")
        return 0

    print("schema manifest is out of sync", file=sys.stderr)
    print(
        "Run: python tools/sync_schemas.py --update --upstream ../heddle",
        file=sys.stderr,
    )
    return 1


def _copy_schemas(upstream: Path, version: str) -> None:
    source_dir = _schema_dir(upstream, version)
    target_dir = _schema_dir(ROOT, version)
    target_dir.mkdir(parents=True, exist_ok=True)

    copied_names: set[str] = set()
    for source in _schema_files(source_dir):
        target = target_dir / source.name
        shutil.copyfile(source, target)
        copied_names.add(source.name)
        print(f"copied {source.relative_to(upstream)}")

    for stale in _schema_files(target_dir):
        if stale.name not in copied_names:
            stale.unlink()
            print(f"removed stale {stale.relative_to(ROOT)}")

    _write_manifest(version, upstream)
    print(f"wrote {MANIFEST_PATH.relative_to(ROOT)}")


def _check_upstream(upstream: Path, version: str) -> int:
    source_dir = _schema_dir(upstream, version)
    target_dir = _schema_dir(ROOT, version)

    source_files = {path.name: path for path in _schema_files(source_dir)}
    target_files = {path.name: path for path in _schema_files(target_dir)}

    missing = sorted(source_files.keys() - target_files.keys())
    extra = sorted(target_files.keys() - source_files.keys())
    changed = sorted(
        name
        for name in source_files.keys() & target_files.keys()
        if not filecmp.cmp(source_files[name], target_files[name], shallow=False)
    )

    if not missing and not extra and not changed:
        print("local schemas match upstream checkout")
        return 0

    if missing:
        print(f"missing local schemas: {', '.join(missing)}", file=sys.stderr)
    if extra:
        print(f"extra local schemas: {', '.join(extra)}", file=sys.stderr)
    if changed:
        print(f"changed schemas: {', '.join(changed)}", file=sys.stderr)
    print(
        "Run: python tools/sync_schemas.py --update --upstream ../heddle",
        file=sys.stderr,
    )
    return 1


def _default_upstream() -> Path:
    return Path(os.environ.get("HEDDLE_REPO", ROOT.parent / "heddle")).resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--schema-version",
        default=DEFAULT_SCHEMA_VERSION,
        help="Schema version directory to sync or check.",
    )
    parser.add_argument(
        "--upstream",
        type=Path,
        default=_default_upstream(),
        help="Path to a local getheddle/heddle checkout.",
    )
    action = parser.add_mutually_exclusive_group()
    action.add_argument(
        "--update",
        action="store_true",
        help="Copy schemas from the upstream checkout and rewrite the manifest.",
    )
    action.add_argument(
        "--check",
        action="store_true",
        help="Verify the local schema manifest matches checked-in schemas.",
    )
    action.add_argument(
        "--check-upstream",
        action="store_true",
        help="Compare checked-in schemas with the upstream checkout.",
    )
    args = parser.parse_args()

    if args.update:
        _copy_schemas(args.upstream.resolve(), args.schema_version)
        return 0
    if args.check_upstream:
        return _check_upstream(args.upstream.resolve(), args.schema_version)
    return _check_manifest(args.schema_version)


if __name__ == "__main__":
    raise SystemExit(main())
