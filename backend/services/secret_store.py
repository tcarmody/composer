"""
LLM API key storage.

Persists UI-set keys in a JSON file at `data/secrets.json` (mode 0600).
UI-set values take precedence over env vars; env vars are the fallback.

Callers read keys via `get(name)` instead of touching `config.*_API_KEY`
directly so toggling between env and UI sources is transparent.
"""

from __future__ import annotations

import json
import os
import stat
import threading
from pathlib import Path

from ..config import config

# Canonical short names → env var fallback.
_KNOWN_KEYS: dict[str, str] = {
    "anthropic": "ANTHROPIC_API_KEY",
    "openai": "OPENAI_API_KEY",
    "voyage": "VOYAGE_API_KEY",
}

_LOCK = threading.Lock()


def known_keys() -> list[str]:
    return list(_KNOWN_KEYS.keys())


def _secrets_path() -> Path:
    return Path(config.DB_PATH).parent / "secrets.json"


def _load() -> dict[str, str]:
    path = _secrets_path()
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text())
        if not isinstance(data, dict):
            return {}
        return {k: str(v) for k, v in data.items() if isinstance(v, str)}
    except (OSError, json.JSONDecodeError):
        return {}


def _save(data: dict[str, str]) -> None:
    path = _secrets_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True))
    os.chmod(tmp, stat.S_IRUSR | stat.S_IWUSR)
    tmp.replace(path)


def get(name: str) -> str:
    """Return UI-set key, falling back to env var. Empty string if neither."""
    if name not in _KNOWN_KEYS:
        raise ValueError(f"Unknown secret name: {name}")
    with _LOCK:
        stored = _load()
    if value := stored.get(name):
        return value
    return os.getenv(_KNOWN_KEYS[name], "")


def set_value(name: str, value: str) -> None:
    if name not in _KNOWN_KEYS:
        raise ValueError(f"Unknown secret name: {name}")
    cleaned = value.strip()
    if not cleaned:
        raise ValueError("Value cannot be empty")
    with _LOCK:
        data = _load()
        data[name] = cleaned
        _save(data)


def clear(name: str) -> bool:
    if name not in _KNOWN_KEYS:
        raise ValueError(f"Unknown secret name: {name}")
    with _LOCK:
        data = _load()
        existed = name in data
        if existed:
            data.pop(name)
            _save(data)
    return existed


def status() -> dict[str, dict[str, object]]:
    """Per-key state. Never returns the raw key."""
    with _LOCK:
        stored = _load()
    out: dict[str, dict[str, object]] = {}
    for name, env_var in _KNOWN_KEYS.items():
        if stored.get(name):
            out[name] = {"set": True, "source": "file"}
        elif os.getenv(env_var):
            out[name] = {"set": True, "source": "env"}
        else:
            out[name] = {"set": False, "source": None}
    return out
