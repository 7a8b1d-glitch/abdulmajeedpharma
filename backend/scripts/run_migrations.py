#!/usr/bin/env python3
"""
Abdulmajeedpharma (APH) — Phase 02.4 Migration Runner

Applies SQL migration files in stable version order with:
  * Idempotent reapplication (skips already-applied migrations)
  * Checksum verification (SHA256 of each migration file)
  * Failure reporting (stops on first failure, records in schema_migrations)
  * Order enforcement (applies 001, 002, ... sequentially)
  * Migration tracking (records each applied version in schema_migrations)

Designed to run against a live PostgreSQL database. Includes a --dry-run
mode that validates migration files statically (parse with sqlglot/pglast
when available) without connecting to a database.

Usage:
  cd backend && source .venv/bin/activate
  python scripts/run_migrations.py --dry-run
  python scripts/run_migrations.py --dsn "postgresql://user:pass@host:5432/db"
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
MIGRATION_DIR = REPO_ROOT / "database" / "migrations"

# Stable version order — migrations must be applied in this exact order.
# Each entry: (version, filename)
MIGRATION_ORDER = [
    ("001", "001_extensions_and_helpers.sql"),
    ("002", "002_geography_and_classification.sql"),
    ("003", "003_drug_catalog.sql"),
    ("004", "004_companies_and_market.sql"),
    ("005", "005_scientific_evidence_and_reviews.sql"),
    ("006", "006_users_and_permissions.sql"),
    ("007", "007_messaging_and_notifications.sql"),
    ("008", "008_imports_and_audit.sql"),
    ("009", "009_indexes_and_search.sql"),
    ("010", "010_rls_and_storage_policies.sql"),
    ("011", "011_seed_reference_data.sql"),
    ("012", "012_review_trigger.sql"),
    ("013", "013_migration_tracking_and_legacy_compat.sql"),
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def sha256_file(path: Path) -> str:
    """Return the SHA-256 hex digest of a file's contents."""
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def list_migration_files() -> list[tuple[str, str, Path, str]]:
    """Return [(version, filename, path, checksum)] in stable order."""
    result = []
    for version, filename in MIGRATION_ORDER:
        path = MIGRATION_DIR / filename
        if not path.is_file():
            print(f"ERROR: Migration file missing: {path}", file=sys.stderr)
            sys.exit(1)
        checksum = sha256_file(path)
        result.append((version, filename, path, checksum))
    return result


# ---------------------------------------------------------------------------
# Dry-run / static validation mode
# ---------------------------------------------------------------------------


def dry_run_validate() -> int:
    """Validate all migration files statically without a database connection.

    Checks:
      * All migration files exist
      * Checksums are deterministic
      * Files parse with pglast/sqlglot if available
      * No obvious forward dependencies (005 must not reference user_profiles,
        012 must not appear before 010, etc.)

    Returns exit code 0 on success, 1 on failure.
    """
    print("=== Phase 02.4 Migration Runner — Dry Run ===\n")
    migrations = list_migration_files()
    failures = 0

    # Try to import pglast / sqlglot for static parsing
    pglast_available = False
    sqlglot_available = False
    try:
        import pglast  # type: ignore
        pglast_available = True
    except ImportError:
        pass
    try:
        import sqlglot  # type: ignore
        sqlglot_available = True
    except ImportError:
        pass

    if not pglast_available and not sqlglot_available:
        print("WARNING: Neither pglast nor sqlglot installed — skipping SQL parse validation.")
        print("         Install with: pip install pglast sqlglot\n")

    for version, filename, path, checksum in migrations:
        sql = path.read_text(encoding="utf-8")
        print(f"  [{version}] {filename}  (sha256={checksum[:12]}...)")

        # Basic structural checks
        if not sql.strip():
            print(f"    FAIL: Empty migration file")
            failures += 1
            continue

        # Static parse if available
        if pglast_available:
            try:
                pglast.parse_sql(sql)
            except Exception as exc:
                print(f"    FAIL: pglast parse error: {exc}")
                failures += 1
        elif sqlglot_available:
            try:
                sqlglot.parse(sql, read="postgres")
            except Exception as exc:
                print(f"    FAIL: sqlglot parse error: {exc}")
                failures += 1

    # Cross-migration dependency checks
    print("\n=== Cross-migration dependency checks ===")
    sql005 = (MIGRATION_DIR / "005_scientific_evidence_and_reviews.sql").read_text(encoding="utf-8")
    if "user_profiles" in sql005:
        print("  FAIL: 005 references user_profiles (created in 006)")
        failures += 1
    else:
        print("  PASS: 005 does not reference user_profiles")

    sql012 = (MIGRATION_DIR / "012_review_trigger.sql").read_text(encoding="utf-8")
    if "assert_no_self_review" in sql012 and "trg_content_reviews_no_self_review" in sql012:
        print("  PASS: 012 contains assert_no_self_review function and trigger")
    else:
        print("  FAIL: 012 missing trigger function or trigger")
        failures += 1

    print(f"\n{'=' * 50}")
    if failures:
        print(f"DRY RUN FAILED: {failures} issue(s) found.")
        return 1
    print(f"DRY RUN PASSED: {len(migrations)} migrations validated.")
    return 0


# ---------------------------------------------------------------------------
# Live database mode
# ---------------------------------------------------------------------------


def apply_migrations(dsn: str, baseline: bool = False) -> int:
    """Apply migrations against a live PostgreSQL database.

    Args:
        dsn: PostgreSQL connection string.
        baseline: If True, record all existing migrations as applied without
            executing them. Only for operator-controlled baseline of legacy
            databases that were already migrated outside this runner.

    Returns exit code 0 on success, 1 on failure.
    """
    try:
        import psycopg2  # type: ignore
    except ImportError:
        print("ERROR: psycopg2 not installed. Install with: pip install psycopg2-binary")
        return 1

    print(f"=== Phase 02.4 Migration Runner — Live Mode ===\n")
    print(f"DSN: {dsn}\n")
    if baseline:
        print("*** BASELINE MODE: recording existing migrations as applied ***\n")

    conn = None
    lock_held = False
    try:
        conn = psycopg2.connect(dsn)
        conn.autocommit = False
        cur = conn.cursor()

        # --- Advisory lock: prevent concurrent migration runners ---
        # Lock key is derived from a stable integer so all runners
        # contend on the same lock.
        cur.execute("SELECT pg_advisory_lock(2024011901)")
        lock_held = True
        print("Acquired advisory lock (2024011901).")

        # --- Bootstrap: ensure schema_migrations table exists ---
        _ensure_tracking_table(cur)
        conn.commit()

        # --- Detect legacy state ---
        # Check if any migration-managed tables exist without tracking records.
        # This indicates a legacy database migrated outside this runner.
        cur.execute("""
            SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema = 'public'
              AND table_name IN (
                  'user_profiles', 'content_reviews', 'drug_evidence',
                  'audit_logs', 'schema_migrations'
              )
        """)
        existing_tables = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM public.schema_migrations WHERE success = TRUE")
        tracked_count = cur.fetchone()[0]

        if existing_tables > 0 and tracked_count == 0 and not baseline:
            print("=" * 60)
            print("LEGACY DATABASE DETECTED")
            print("=" * 60)
            print(f"Found {existing_tables} migration-managed tables but zero")
            print("tracked migrations in schema_migrations.")
            print("")
            print("This database was likely migrated outside this runner.")
            print("Do NOT blindly execute all historical migrations — they may")
            print("fail on existing data or duplicate objects.")
            print("")
            print("To baseline this database (record all migrations as applied")
            print("without executing them), re-run with --baseline:")
            print(f"  python scripts/run_migrations.py --dsn \"{dsn}\" --baseline")
            print("")
            print("To apply only missing migrations, first run the baseline,")
            print("then apply new migrations normally.")
            print("=" * 60)
            cur.execute("SELECT pg_advisory_unlock(2024011901)")
            lock_held = False
            return 1

        # --- Get already-applied migrations ---
        cur.execute("SELECT version, checksum FROM public.schema_migrations WHERE success = TRUE")
        applied = {row[0]: row[1] for row in cur.fetchall()}

        migrations = list_migration_files()
        failures = 0
        applied_count = 0
        skipped_count = 0

        for version, filename, path, checksum in migrations:
            if version in applied:
                # Verify checksum matches
                stored_checksum = applied[version]
                if stored_checksum != checksum:
                    print(f"  [{version}] {filename} — CHECKSUM MISMATCH")
                    print(f"    Expected: {stored_checksum}")
                    print(f"    Got:      {checksum}")
                    print(f"    FAIL: Migration {version} has been modified since it was applied.")
                    failures += 1
                    break
                print(f"  [{version}] {filename} — already applied (checksum OK)")
                skipped_count += 1
                continue

            if baseline:
                # Baseline mode: record as applied without executing.
                # Only use for legacy databases already migrated externally.
                cur.execute(
                    """
                    INSERT INTO public.schema_migrations (version, name, checksum, applied_at, success)
                    VALUES (%s, %s, %s, now(), TRUE)
                    ON CONFLICT (version) DO UPDATE
                    SET name = EXCLUDED.name,
                        checksum = EXCLUDED.checksum,
                        applied_at = now(),
                        success = TRUE
                    """,
                    (version, filename, checksum),
                )
                conn.commit()
                skipped_count += 1
                print(f"  [{version}] {filename} — baselined (not executed).")
                continue

            print(f"  [{version}] {filename} — applying...")
            sql = path.read_text(encoding="utf-8")

            try:
                cur.execute(sql)
                # Record the migration in the same transaction
                cur.execute(
                    """
                    INSERT INTO public.schema_migrations (version, name, checksum, applied_at, success)
                    VALUES (%s, %s, %s, now(), TRUE)
                    ON CONFLICT (version) DO UPDATE
                    SET name = EXCLUDED.name,
                        checksum = EXCLUDED.checksum,
                        applied_at = now(),
                        success = TRUE
                    """,
                    (version, filename, checksum),
                )
                conn.commit()
                applied_count += 1
                print(f"    OK: applied and recorded.")
            except Exception as exc:
                conn.rollback()
                # Record the failure safely
                try:
                    cur.execute(
                        """
                        INSERT INTO public.schema_migrations (version, name, checksum, applied_at, success)
                        VALUES (%s, %s, %s, now(), FALSE)
                        ON CONFLICT (version) DO UPDATE
                        SET name = EXCLUDED.name,
                            checksum = EXCLUDED.checksum,
                            applied_at = now(),
                            success = FALSE
                        """,
                        (version, filename, checksum),
                    )
                    conn.commit()
                except Exception:
                    conn.rollback()
                print(f"    FAIL: {exc}")
                print("")
                print("Recovery: fix the error, then re-run this script.")
                print("Already-applied migrations will be skipped; the failed")
                print("migration will be retried on the next run.")
                failures += 1
                break

        if not failures and lock_held:
            print(f"\n{'=' * 60}")
            print(f"Applied: {applied_count}, Skipped: {skipped_count}, Failures: {failures}")
            print("MIGRATION RUN COMPLETED SUCCESSFULLY.")

        cur.close()

        if failures:
            print("MIGRATION RUN FAILED — see errors above.")
            return 1
        return 0

    finally:
        if lock_held and conn:
            try:
                cur = conn.cursor()
                cur.execute("SELECT pg_advisory_unlock(2024011901)")
                conn.commit()
                cur.close()
            except Exception:
                pass
        if conn:
            conn.close()


def _ensure_tracking_table(cur) -> None:
    """Create the schema_migrations table if it doesn't exist (bootstrap)."""
    cur.execute("""
        CREATE TABLE IF NOT EXISTS public.schema_migrations (
            version        VARCHAR(20) NOT NULL PRIMARY KEY,
            name           VARCHAR(255) NOT NULL,
            checksum       VARCHAR(64) NOT NULL,
            applied_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
            success        BOOLEAN NOT NULL DEFAULT TRUE
        );
    """)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description="APH Phase 02.4 Migration Runner — apply SQL migrations with tracking."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate migration files statically without a database connection.",
    )
    parser.add_argument(
        "--dsn",
        type=str,
        default=None,
        help="PostgreSQL connection string (e.g. postgresql://user:pass@host:5432/db).",
    )
    parser.add_argument(
        "--baseline",
        action="store_true",
        help="Record all migrations as applied without executing them. "
             "For operator-controlled baseline of legacy databases only.",
    )
    args = parser.parse_args()

    if args.dry_run:
        return dry_run_validate()

    if not args.dsn:
        print("ERROR: Either --dry-run or --dsn is required.", file=sys.stderr)
        parser.print_help()
        return 1

    return apply_migrations(args.dsn, baseline=args.baseline)


if __name__ == "__main__":
    sys.exit(main())
