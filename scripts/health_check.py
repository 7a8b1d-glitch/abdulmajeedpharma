#!/usr/bin/env python3
"""Abdulmajeedpharma (APH) — Phase 01 Project Health Check.

Verifies expected directories, required project files, JSON validity,
Python source syntax, and missing configuration (without exposing secrets).
Prints a clear PASS / FAIL summary.
"""

from __future__ import annotations

import ast
import json
import os
import sys
from pathlib import Path

# Repository root is the parent of the scripts/ directory.
ROOT = Path(__file__).resolve().parent.parent

RESULTS: list[tuple[str, str, str]] = []  # (check, status, detail)
FAILURES = 0


def record(check: str, status: str, detail: str = "") -> None:
    global FAILURES
    RESULTS.append((check, status, detail))
    if status == "FAIL":
        FAILURES += 1
    print(f"  [{status}] {check}: {detail}")


def check_dir(rel: str) -> None:
    path = ROOT / rel
    if path.is_dir():
        record(f"Directory {rel}", "PASS", "exists")
    else:
        record(f"Directory {rel}", "FAIL", "missing")


def check_file(rel: str) -> None:
    path = ROOT / rel
    if path.is_file():
        record(f"File {rel}", "PASS", "exists")
    else:
        record(f"File {rel}", "FAIL", "missing")


def check_json(rel: str) -> None:
    path = ROOT / rel
    if not path.is_file():
        record(f"JSON {rel}", "FAIL", "missing")
        return
    try:
        with path.open("r", encoding="utf-8") as fh:
            json.load(fh)
        record(f"JSON {rel}", "PASS", "valid")
    except json.JSONDecodeError as exc:
        record(f"JSON {rel}", "FAIL", f"invalid JSON: {exc}")


def check_python_syntax(rel: str) -> None:
    path = ROOT / rel
    if not path.is_file():
        record(f"Python syntax {rel}", "FAIL", "missing")
        return
    try:
        source = path.read_text(encoding="utf-8")
        ast.parse(source, filename=str(path))
        record(f"Python syntax {rel}", "PASS", "valid syntax")
    except SyntaxError as exc:
        record(f"Python syntax {rel}", "FAIL", f"syntax error: {exc}")


def check_config_placeholders() -> None:
    """Report missing configuration without exposing secrets."""
    env_example = ROOT / ".env.example"
    if not env_example.is_file():
        record("Configuration .env.example", "FAIL", "missing")
        return

    required_keys = [
        "DATABASE_URL",
        "SUPABASE_URL",
        "SUPABASE_PUBLIC_KEY",
        "SUPABASE_SERVICE_KEY",
        "REDIS_URL",
        "AI_PROVIDER",
        "AI_API_KEY",
        "GOOGLE_CLOUD_PROJECT",
        "SEARCH_SERVICE_URL",
        "JWT_SECRET",
        "SUPPORT_EMAIL",
    ]

    content = env_example.read_text(encoding="utf-8")
    missing = [k for k in required_keys if f"{k}=" not in content]
    if missing:
        record("Configuration placeholders", "FAIL", f"missing: {', '.join(missing)}")
    else:
        record("Configuration placeholders", "PASS", "all required keys present")

    # Warn if a real-looking .env exists (do not print its contents).
    if (ROOT / ".env").is_file():
        record("Configuration .env", "PASS", "present (contents not inspected)")


def check_gitignore() -> None:
    path = ROOT / ".gitignore"
    if not path.is_file():
        record("File .gitignore", "FAIL", "missing")
        return
    content = path.read_text(encoding="utf-8")
    expected = [".env", "node_modules", "__pycache__", ".venv", "*.jks", "*.keystore"]
    missing = [e for e in expected if e not in content]
    if missing:
        record(".gitignore coverage", "FAIL", f"missing patterns: {', '.join(missing)}")
    else:
        record(".gitignore coverage", "PASS", "covers env, node_modules, cache, venv, signing keys")


def main() -> int:
    print("=" * 68)
    print("  APH — Phase 01 Project Health Check")
    print("=" * 68)
    print()

    # --- Directories ---
    print("--- Directories ---")
    expected_dirs = [
        "mobile",
        "mobile/lib",
        "mobile/lib/app",
        "mobile/lib/core",
        "mobile/lib/core/config",
        "mobile/lib/core/constants",
        "mobile/lib/core/errors",
        "mobile/lib/core/localization",
        "mobile/lib/core/network",
        "mobile/lib/core/storage",
        "mobile/lib/core/theme",
        "mobile/lib/core/utils",
        "mobile/lib/shared",
        "mobile/lib/shared/widgets",
        "mobile/lib/shared/models",
        "mobile/lib/features",
        "backend",
        "backend/app",
        "backend/app/core",
        "backend/app/api",
        "backend/app/models",
        "backend/app/schemas",
        "backend/app/services",
        "backend/app/repositories",
        "backend/tests",
        "admin",
        "database",
        "database/migrations",
        "database/seeds",
        "data-import",
        "data-import/csv",
        "data-import/excel",
        "data-import/json",
        "data-import/images",
        "ai",
        "ai/rag",
        "ai/prompts",
        "infrastructure",
        "infrastructure/docker",
        "docs",
        "scripts",
    ]
    for d in expected_dirs:
        check_dir(d)

    # --- Required files ---
    print("\n--- Required Files ---")
    expected_files = [
        "README.md",
        "LICENSE",
        ".gitignore",
        ".env.example",
        "mobile/README.md",
        "mobile/pubspec.yaml",
        "mobile/analysis_options.yaml",
        "mobile/lib/main.dart",
        "mobile/lib/app/app.dart",
        "mobile/lib/app/app_router.dart",
        "mobile/lib/core/config/app_config.dart",
        "mobile/lib/core/constants/app_constants.dart",
        "mobile/lib/core/errors/app_exception.dart",
        "mobile/lib/core/localization/app_localizations.dart",
        "mobile/lib/core/network/api_client.dart",
        "mobile/lib/core/storage/local_storage.dart",
        "mobile/lib/core/theme/app_theme.dart",
        "mobile/lib/core/utils/helpers.dart",
        "mobile/lib/shared/widgets/shimmer_loading.dart",
        "mobile/lib/shared/models/drug.dart",
        "backend/README.md",
        "backend/requirements.txt",
        "backend/app/main.py",
        "backend/app/core/config.py",
        "backend/app/api/api_router.py",
        "backend/app/models/base.py",
        "backend/app/models/drug.py",
        "backend/app/schemas/drug.py",
        "backend/app/services/drug_service.py",
        "backend/app/repositories/drug_repository.py",
        "backend/tests/test_placeholder.py",
        "admin/package.json",
        "database/README.md",
        "data-import/README.md",
        "ai/README.md",
        "infrastructure/README.md",
        "docs/ARCHITECTURE.md",
        "docs/DEVELOPMENT_STATUS.md",
        "docs/SECURITY.md",
        "docs/ROADMAP.md",
        "scripts/health_check.py",
    ]
    for f in expected_files:
        check_file(f)

    # --- JSON validation ---
    print("\n--- JSON Validation ---")
    check_json("admin/package.json")

    # --- Python syntax validation ---
    print("\n--- Python Syntax Validation ---")
    python_files = [
        "scripts/health_check.py",
        "backend/app/main.py",
        "backend/app/core/config.py",
        "backend/app/api/api_router.py",
        "backend/app/models/base.py",
        "backend/app/models/drug.py",
        "backend/app/schemas/drug.py",
        "backend/app/services/drug_service.py",
        "backend/app/repositories/drug_repository.py",
        "backend/tests/test_placeholder.py",
    ]
    for pf in python_files:
        check_python_syntax(pf)

    # --- Configuration ---
    print("\n--- Configuration ---")
    check_config_placeholders()
    check_gitignore()

    # --- Summary ---
    print("\n" + "=" * 68)
    total = len(RESULTS)
    passed = sum(1 for _, s, _ in RESULTS if s == "PASS")
    failed = sum(1 for _, s, _ in RESULTS if s == "FAIL")
    print(f"  Total checks: {total}")
    print(f"  Passed:       {passed}")
    print(f"  Failed:       {failed}")
    print("=" * 68)

    if failed == 0:
        print("RESULT: PASS — Phase 01 foundation is healthy.")
        return 0
    print("RESULT: FAIL — one or more checks failed. Review details above.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
