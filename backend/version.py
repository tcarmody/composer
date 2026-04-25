"""Resolves the backend's git commit at import time so /v1/health can
report it. Used by the Mac client to detect a stale running backend."""

import os
import subprocess


def _resolve_commit() -> str:
    if override := os.environ.get("COMPOSER_BACKEND_COMMIT"):
        return override
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=repo,
            stderr=subprocess.DEVNULL,
            timeout=2,
        )
        return out.decode("ascii").strip() or "unknown"
    except (subprocess.SubprocessError, OSError):
        return "unknown"


BACKEND_COMMIT: str = _resolve_commit()
