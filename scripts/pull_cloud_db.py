#!/usr/bin/env python3
"""
Pull the cloud Composer database down to this machine.

One-time seeding step before switching to local-primary operation: the
Railway instance has been the writer, so copy its DB here, then let the
local backend's sync worker push changes back up incrementally.

Usage:
    python scripts/pull_cloud_db.py --url https://<composer>.up.railway.app \
        --api-key <AUTH_API_KEY> [--dest ./data/composer.db]

Stop the local backend before running this. The existing local DB (and
its WAL sidecars) are saved with a .bak suffix.
"""

import argparse
import os
import shutil
import sys
from pathlib import Path

import httpx


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="Cloud Composer base URL")
    parser.add_argument(
        "--api-key",
        default=os.getenv("AUTH_API_KEY", ""),
        help="Cloud AUTH_API_KEY (default: AUTH_API_KEY env var)",
    )
    parser.add_argument(
        "--dest",
        type=Path,
        default=Path(os.getenv("DB_PATH", "./data/composer.db")),
        help="Local DB path to overwrite (default: DB_PATH env or ./data/composer.db)",
    )
    args = parser.parse_args()

    export_url = args.url.rstrip("/") + "/v1/admin/export/db"
    headers = {"X-API-Key": args.api_key} if args.api_key else {}

    print(f"Downloading {export_url} ...")
    tmp_path = args.dest.with_suffix(".download")
    with httpx.stream("GET", export_url, headers=headers, timeout=300.0) as resp:
        if resp.status_code != 200:
            print(f"ERROR: cloud returned {resp.status_code}", file=sys.stderr)
            return 1
        args.dest.parent.mkdir(parents=True, exist_ok=True)
        with open(tmp_path, "wb") as f:
            for chunk in resp.iter_bytes():
                f.write(chunk)
    size_mb = tmp_path.stat().st_size / 1e6
    print(f"Downloaded {size_mb:.1f} MB")

    if args.dest.exists():
        backup = args.dest.with_suffix(".db.bak")
        shutil.copy2(args.dest, backup)
        print(f"Backed up existing DB to {backup}")
    # remove stale WAL sidecars so SQLite doesn't replay old local state
    # over the freshly pulled file
    for suffix in ("-wal", "-shm"):
        sidecar = Path(str(args.dest) + suffix)
        if sidecar.exists():
            sidecar.unlink()

    tmp_path.replace(args.dest)
    print(f"Installed cloud DB at {args.dest}")
    print("Start the local backend; it will add the sync_outbox table on boot.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
