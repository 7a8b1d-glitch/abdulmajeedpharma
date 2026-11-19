"""Phase 02 — Static database schema validation tests.

These tests do NOT require a live PostgreSQL connection. They statically
validate the SQL migration files and SQLAlchemy models for structure,
constraints, indexes, and seed data correctness.

Run with:  cd backend && source .venv/bin/activate && python -m pytest tests/
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.models import Base  # noqa: F401  (ensures all models import)

MIGRATION_DIR = (
    Path(__file__).resolve().parent.parent.parent / "database" / "migrations"
)


# ---------------------------------------------------------------------------
# Helpers — SQL uses unquoted identifiers (public.table_name, column_name)
# ---------------------------------------------------------------------------

def _migration_sql(name: str) -> str:
    path = MIGRATION_DIR / name
    assert path.is_file(), f"Migration {name} is missing"
    return path.read_text(encoding="utf-8")


def _assert_table_exists(sql: str, table: str) -> None:
    # Matches: CREATE TABLE public.table_name (
    pattern = rf'CREATE\s+TABLE\s+public\.{table}\s*\('
    assert re.search(pattern, sql, re.IGNORECASE), (
        f"Table '{table}' not found in migration SQL"
    )


def _table_block(sql: str, table: str) -> str:
    """Extract the CREATE TABLE block (column definitions) for a table."""
    m = re.search(
        rf'CREATE\s+TABLE\s+public\.{table}\s*\((.*?)\);',
        sql, re.IGNORECASE | re.DOTALL,
    )
    assert m, f"Could not locate CREATE TABLE block for '{table}'"
    return m.group(1)


def _assert_column_exists(sql: str, table: str, column: str) -> None:
    block = _table_block(sql, table)
    pattern = rf'{column}\s+'
    assert re.search(pattern, block, re.IGNORECASE), (
        f"Column '{column}' not found in table '{table}'"
    )


def _assert_fk_exists(sql: str, table: str, column: str, ref_table: str, ref_column: str = "id") -> None:
    # Match either inline (column REFERENCES ...) or table-level
    # (FOREIGN KEY (column) REFERENCES ...) foreign keys.
    inline_pattern = (
        rf'{column}\s+\w+\s+.*REFERENCES\s+public\.{ref_table}\s*\(\s*{ref_column}\s*\)'
    )
    table_pattern = (
        rf'FOREIGN\s+KEY\s*\(\s*{column}\s*\)\s*'
        rf'REFERENCES\s+public\.{ref_table}\s*\(\s*{ref_column}\s*\)'
    )
    block = _table_block(sql, table)
    assert (
        re.search(inline_pattern, block, re.IGNORECASE | re.DOTALL)
        or re.search(table_pattern, block, re.IGNORECASE)
    ), (
        f"Foreign key {table}.{column} -> {ref_table}.{ref_column} not found"
    )


def _assert_unique_constraint(sql: str, table: str, *columns: str) -> None:
    # Match table-level UNIQUE (col1, col2) or inline col TYPE ... UNIQUE.
    block = _table_block(sql, table)
    if len(columns) == 1:
        col = columns[0]
        # Table-level: UNIQUE (col)
        table_level = rf'UNIQUE\s*\(\s*{col}\s*\)'
        # Inline: col <type> ... UNIQUE (may span multiple tokens, use DOTALL)
        inline = rf'{col}\b[\s\S]*?\bUNIQUE\b'
    else:
        cols = ", ".join(columns)
        inline = None
        table_level = rf'UNIQUE\s*\(\s*{cols}\s*\)'
    found = bool(re.search(table_level, block, re.IGNORECASE))
    if inline and not found:
        found = bool(re.search(inline, block, re.IGNORECASE))
    assert found, f"Unique constraint on {table}({', '.join(columns)}) not found"


def _assert_check_constraint(sql: str, table: str, check_pattern: str) -> None:
    # Match either a named CONSTRAINT name CHECK or an inline CHECK(pattern).
    block = _table_block(sql, table)
    named = rf'CONSTRAINT\s+\w+\s+CHECK\s*\(\s*{check_pattern}'
    inline = rf'CHECK\s*\(\s*{check_pattern}'
    assert (
        re.search(named, block, re.IGNORECASE | re.DOTALL)
        or re.search(inline, block, re.IGNORECASE | re.DOTALL)
    ), f"Check constraint pattern '{check_pattern}' not found on table '{table}'"


def _assert_index_exists(sql: str, table: str, column: str) -> None:
    pattern = rf'CREATE\s+INDEX\s+.+ON\s+public\.{table}\s*\(\s*{column}\s*\)'
    assert re.search(pattern, sql, re.IGNORECASE), (
        f"Index on {table}.{column} not found"
    )


# ---------------------------------------------------------------------------
# Migration existence tests
# ---------------------------------------------------------------------------

MIGRATION_FILES = [
    "001_extensions_and_helpers.sql",
    "002_geography_and_classification.sql",
    "003_drug_catalog.sql",
    "004_companies_and_market.sql",
    "005_scientific_evidence_and_reviews.sql",
    "006_users_and_permissions.sql",
    "007_messaging_and_notifications.sql",
    "008_imports_and_audit.sql",
    "009_indexes_and_search.sql",
    "010_rls_and_storage_policies.sql",
    "011_seed_reference_data.sql",
]


@pytest.mark.parametrize("migration_file", MIGRATION_FILES)
def test_migration_file_exists(migration_file: str) -> None:
    """Every planned migration file must exist."""
    assert (MIGRATION_DIR / migration_file).is_file()


# ---------------------------------------------------------------------------
# Table existence tests
# ---------------------------------------------------------------------------

REQUIRED_TABLES = [
    "countries", "body_systems", "therapeutic_classes",
    "pharmacological_classes", "drug_classes",
    "active_ingredients", "drugs", "drug_ingredients", "drug_class_links",
    "drug_indications", "drug_contraindications", "drug_adverse_effects",
    "drug_interactions", "drug_dosage_information", "drug_special_populations",
    "drug_images",
    "manufacturers", "marketing_authorization_holders", "suppliers",
    "distributors", "brand_products", "product_presentations",
    "product_markets", "product_registration_records",
    "scientific_sources", "drug_evidence", "content_reviews",
    "user_profiles",
    "conversations", "conversation_participants", "messages",
    "message_attachments", "message_read_receipts", "notifications",
    "import_batches", "import_batch_items", "import_errors",
    "audit_logs", "sync_records",
]


def _all_migration_sql() -> str:
    parts = []
    for f in sorted(MIGRATION_DIR.glob("*.sql")):
        parts.append(f.read_text(encoding="utf-8"))
    return "\n".join(parts)


ALL_SQL = _all_migration_sql()


@pytest.mark.parametrize("table", REQUIRED_TABLES)
def test_required_table_exists(table: str) -> None:
    """Each required table must be created by the migrations."""
    _assert_table_exists(ALL_SQL, table)


# ---------------------------------------------------------------------------
# Column tests
# ---------------------------------------------------------------------------

COLUMN_TESTS = [
    ("countries", "id"), ("countries", "code"), ("countries", "name_en"),
    ("countries", "name_ar"), ("countries", "is_yemen"), ("countries", "created_at"),
    ("countries", "updated_at"),
    ("body_systems", "id"), ("body_systems", "code"), ("body_systems", "name_en"),
    ("body_systems", "name_ar"), ("body_systems", "created_at"), ("body_systems", "updated_at"),
    ("drugs", "id"), ("drugs", "code"), ("drugs", "name_en"), ("drugs", "name_ar"),
    ("drugs", "generic_name_en"), ("drugs", "is_active"), ("drugs", "created_at"),
    ("drugs", "updated_at"),
    ("active_ingredients", "id"), ("active_ingredients", "code"),
    ("active_ingredients", "name_en"), ("active_ingredients", "name_ar"),
    ("active_ingredients", "is_active"),
    ("brand_products", "id"), ("brand_products", "code"),
    ("brand_products", "brand_name_en"), ("brand_products", "brand_name_ar"),
    ("brand_products", "is_active"),
    ("product_presentations", "id"), ("product_presentations", "barcode"),
    ("product_presentations", "dosage_form_en"), ("product_presentations", "route_en"),
    ("product_presentations", "strength_value"), ("product_presentations", "strength_unit"),
    ("product_registration_records", "id"),
    ("product_registration_records", "registration_number"),
    ("product_registration_records", "registration_status"),
    ("scientific_sources", "id"), ("scientific_sources", "title"),
    ("scientific_sources", "doi"), ("scientific_sources", "reliability_level"),
    ("drug_evidence", "id"), ("drug_evidence", "claim_category"),
    ("drug_evidence", "is_verified"),
    ("content_reviews", "id"), ("content_reviews", "review_status"),
    ("content_reviews", "review_notes"), ("content_reviews", "content_version"),
    ("user_profiles", "user_id"), ("user_profiles", "email"), ("user_profiles", "role"),
    ("conversations", "id"), ("conversations", "status"),
    ("messages", "id"), ("messages", "body_en"), ("messages", "sender_id"),
    ("message_attachments", "id"), ("message_attachments", "storage_path"),
    ("notifications", "id"), ("notifications", "type"), ("notifications", "is_read"),
    ("import_batches", "id"), ("import_batches", "original_filename"),
    ("import_batches", "import_format"), ("import_batches", "status"),
    ("audit_logs", "id"), ("audit_logs", "action"), ("audit_logs", "entity_type"),
    ("sync_records", "id"), ("sync_records", "client_id"), ("sync_records", "sync_status"),
]


@pytest.mark.parametrize("table,column", COLUMN_TESTS)
def test_required_column_exists(table: str, column: str) -> None:
    """Each required column must exist on its table."""
    _assert_column_exists(ALL_SQL, table, column)


# ---------------------------------------------------------------------------
# Foreign key tests
# ---------------------------------------------------------------------------

FK_TESTS = [
    ("therapeutic_classes", "body_system_id", "body_systems", "id"),
    ("pharmacological_classes", "therapeutic_class_id", "therapeutic_classes", "id"),
    ("drug_classes", "pharmacological_class_id", "pharmacological_classes", "id"),
    ("drug_ingredients", "drug_id", "drugs", "id"),
    ("drug_ingredients", "active_ingredient_id", "active_ingredients", "id"),
    ("drug_class_links", "drug_id", "drugs", "id"),
    ("drug_class_links", "drug_class_id", "drug_classes", "id"),
    ("drug_indications", "drug_id", "drugs", "id"),
    ("drug_contraindications", "drug_id", "drugs", "id"),
    ("drug_adverse_effects", "drug_id", "drugs", "id"),
    ("drug_interactions", "drug_id", "drugs", "id"),
    ("drug_interactions", "interacting_drug_id", "drugs", "id"),
    ("drug_dosage_information", "drug_id", "drugs", "id"),
    ("drug_special_populations", "drug_id", "drugs", "id"),
    ("drug_images", "drug_id", "drugs", "id"),
    ("brand_products", "manufacturer_id", "manufacturers", "id"),
    ("product_presentations", "brand_product_id", "brand_products", "id"),
    ("product_markets", "brand_product_id", "brand_products", "id"),
    ("product_markets", "country_id", "countries", "id"),
    ("product_registration_records", "product_market_id", "product_markets", "id"),
    ("drug_evidence", "scientific_source_id", "scientific_sources", "id"),
    ("content_reviews", "drug_evidence_id", "drug_evidence", "id"),
    ("conversation_participants", "conversation_id", "conversations", "id"),
    ("messages", "conversation_id", "conversations", "id"),
    ("message_attachments", "message_id", "messages", "id"),
    ("message_read_receipts", "message_id", "messages", "id"),
    ("notifications", "user_id", "user_profiles", "user_id"),
]


@pytest.mark.parametrize("table,column,ref_table,ref_column", FK_TESTS)
def test_foreign_key_exists(table: str, column: str, ref_table: str, ref_column: str) -> None:
    """Each required foreign key must be defined."""
    _assert_fk_exists(ALL_SQL, table, column, ref_table, ref_column)


# ---------------------------------------------------------------------------
# Unique constraint tests
# ---------------------------------------------------------------------------

UNIQUE_TESTS = [
    ("countries", ("code",)),
    ("body_systems", ("code",)),
    ("therapeutic_classes", ("code",)),
    ("pharmacological_classes", ("code",)),
    ("drug_classes", ("code",)),
    ("active_ingredients", ("code",)),
    ("drugs", ("code",)),
    ("drug_ingredients", ("drug_id", "active_ingredient_id")),
    ("drug_class_links", ("drug_id", "drug_class_id")),
    ("brand_products", ("code",)),
    ("product_presentations", ("presentation_code",)),
    ("product_markets", ("brand_product_id", "country_id")),
    ("conversation_participants", ("conversation_id", "user_id")),
    ("message_read_receipts", ("message_id", "user_id")),
]


@pytest.mark.parametrize("table,columns", UNIQUE_TESTS)
def test_unique_constraint_exists(table: str, columns: tuple[str, ...]) -> None:
    """Each required unique constraint must exist."""
    _assert_unique_constraint(ALL_SQL, table, *columns)


# ---------------------------------------------------------------------------
# Check constraint tests
#
# Each entry: (table, regex pattern to find inside a CHECK (...))
# ---------------------------------------------------------------------------

CHECK_CONSTRAINT_TESTS = [
    ("drug_interactions", r"severity\s+IN\s*\("),
    ("drug_interactions", r"drug_id\s*<>\s*interacting_drug_id"),
    ("drug_special_populations", r"risk_level\s+IN\s*\("),
    ("product_registration_records", r"registration_status\s+IN\s*\("),
    ("product_registration_records", r"availability_status\s+IN\s*\("),
    ("scientific_sources", r"source_type\s+IN\s*\("),
    ("scientific_sources", r"reliability_level\s+IN\s*\("),
    ("drug_evidence", r"claim_category\s+IN\s*\("),
    ("drug_evidence", r"drug_id\s+IS\s+NOT\s+NULL\s+OR\s+brand_product_id\s+IS\s+NOT\s+NULL"),
    ("drug_evidence", r"NOT\s*\(\s*drug_id\s+IS\s+NOT\s+NULL\s+AND\s+brand_product_id\s+IS\s+NOT\s+NULL\s*\)"),
    ("content_reviews", r"review_status\s+IN\s*\("),
    ("user_profiles", r"role\s+IN\s*\("),
    ("conversations", r"status\s+IN\s*\("),
    ("messages", r"message_type\s+IN\s*\("),
    ("notifications", r"type\s+IN\s*\("),
    ("import_batches", r"import_format\s+IN\s*\("),
    ("import_batches", r"status\s+IN\s*\("),
    ("import_batch_items", r"status\s+IN\s*\("),
    ("sync_records", r"operation\s+IN\s*\("),
    ("sync_records", r"sync_status\s+IN\s*\("),
    ("audit_logs", r"change_metadata\s+\?\s+'password'"),
]


@pytest.mark.parametrize("table,check_pattern", CHECK_CONSTRAINT_TESTS)
def test_check_constraint_exists(table: str, check_pattern: str) -> None:
    """Each required check constraint must exist (inline or named)."""
    _assert_check_constraint(ALL_SQL, table, check_pattern)


# ---------------------------------------------------------------------------
# RLS policy tests
# ---------------------------------------------------------------------------

def test_rls_enabled_on_all_tables() -> None:
    """Every table must have ROW LEVEL SECURITY enabled."""
    for table in REQUIRED_TABLES:
        pattern = rf'ALTER\s+TABLE\s+public\.{table}\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY'
        assert re.search(pattern, ALL_SQL, re.IGNORECASE), (
            f"RLS not enabled on table '{table}'"
        )


def test_no_unrestricted_public_policy_on_private_tables() -> None:
    """Private tables must not have an unrestricted USING (true) policy."""
    private_tables = [
        "user_profiles", "conversations", "conversation_participants",
        "messages", "message_attachments", "message_read_receipts",
        "notifications", "import_batches", "import_batch_items",
        "import_errors", "audit_logs", "sync_records",
        "content_reviews", "drug_evidence",
    ]
    for table in private_tables:
        pattern = (
            rf'CREATE\s+POLICY\s+\S+\s+ON\s+public\.{table}\s+.*'
            rf'USING\s*\(\s*true\s*\)'
        )
        assert not re.search(pattern, ALL_SQL, re.IGNORECASE | re.DOTALL), (
            f"Unrestricted USING (true) policy found on private table '{table}'"
        )


def test_rls_uses_auth_uid() -> None:
    """RLS policies on user-owned tables must reference auth.uid()."""
    assert re.search(r'auth\.uid\(\)', ALL_SQL), (
        "No RLS policy references auth.uid()"
    )


# ---------------------------------------------------------------------------
# Seed data tests
# ---------------------------------------------------------------------------

def test_18_body_systems_seeded() -> None:
    """Exactly 18 body systems must be seeded with stable codes."""
    seed_sql = _migration_sql("011_seed_reference_data.sql")
    expected_codes = [
        "NERVOUS_SYSTEM", "CARDIOVASCULAR_SYSTEM", "BLOOD_HEMATOPOIETIC",
        "RESPIRATORY_SYSTEM", "GASTROINTESTINAL_SYSTEM", "HEPATOBILIARY_SYSTEM",
        "ENDOCRINE_SYSTEM", "RENAL_URINARY_SYSTEM", "REPRODUCTIVE_SYSTEM",
        "MUSCULOSKELETAL_SYSTEM", "SKIN_SYSTEM", "EYE", "ENT",
        "IMMUNE_SYSTEM", "ANTI-INFECTIVE_SYSTEM", "ONCOLOGY",
        "EMERGENCY_TOXICOLOGY", "DIAGNOSTIC_MISCELLANEOUS",
    ]
    for code in expected_codes:
        pattern = rf"\('{code}'"
        assert re.search(pattern, seed_sql), (
            f"Body system code '{code}' not found in seed data"
        )


def test_yemen_country_seeded() -> None:
    """Yemen must be seeded as a country with code YE."""
    seed_sql = _migration_sql("011_seed_reference_data.sql")
    assert re.search(r"\('YE'", seed_sql), "Yemen country code YE not found in seed data"
    assert "Yemen" in seed_sql, "Yemen country name not found in seed data"
    assert "اليمن" in seed_sql, "Yemen Arabic name not found in seed data"


def test_seed_is_idempotent() -> None:
    """Seed must use ON CONFLICT DO NOTHING (idempotent)."""
    seed_sql = _migration_sql("011_seed_reference_data.sql")
    assert "ON CONFLICT" in seed_sql, "Seed is not idempotent (missing ON CONFLICT)"
    assert "DO NOTHING" in seed_sql, "Seed is not idempotent (missing DO NOTHING)"


def test_no_fake_drug_records_in_seed() -> None:
    """No invented drug products, manufacturers, or suppliers in seed data."""
    seed_sql = _migration_sql("011_seed_reference_data.sql")
    assert "INSERT INTO public.countries" in seed_sql
    assert "INSERT INTO public.body_systems" in seed_sql
    assert "INSERT INTO public.drugs" not in seed_sql
    assert "INSERT INTO public.brand_products" not in seed_sql
    assert "INSERT INTO public.manufacturers" not in seed_sql


# ---------------------------------------------------------------------------
# SQLAlchemy model consistency tests
# ---------------------------------------------------------------------------

def test_sqlalchemy_models_match_tables() -> None:
    """Every SQLAlchemy model must map to a migration-created table."""
    model_tables = set(Base.metadata.tables.keys())
    migration_tables = set(REQUIRED_TABLES)
    missing_in_migrations = model_tables - migration_tables
    missing_in_models = migration_tables - model_tables
    assert not missing_in_migrations, (
        f"Models without migrations: {missing_in_migrations}"
    )
    assert not missing_in_models, (
        f"Migrations without models: {missing_in_models}"
    )


def test_all_models_have_timestamps() -> None:
    """Every model must have a creation timestamp (created_at or timestamp)."""
    for table_name, table in Base.metadata.tables.items():
        assert "created_at" in table.columns or "timestamp" in table.columns, (
            f"Model '{table_name}' missing creation timestamp column"
        )


def test_uuid_primary_keys() -> None:
    """Every model must use a UUID-typed primary key (String(36))."""
    from sqlalchemy import String
    for table_name, table in Base.metadata.tables.items():
        pk_cols = [c for c in table.primary_key.columns]
        assert len(pk_cols) >= 1, f"Table '{table_name}' has no primary key"
        for pk in pk_cols:
            assert isinstance(pk.type, String), (
                f"Table '{table_name}' PK '{pk.name}' is not String/UUID"
            )
            assert pk.type.length == 36, (
                f"Table '{table_name}' PK '{pk.name}' length is not 36"
            )


# ---------------------------------------------------------------------------
# Backend import consistency
# ---------------------------------------------------------------------------

def test_backend_app_imports() -> None:
    """The FastAPI app must import without errors (Phase 01 compatibility)."""
    from app.main import app  # noqa: F401
    assert app is not None
    routes = [r.path for r in app.routes]
    assert "/health" in routes
    assert "/api/v1/health" in routes
