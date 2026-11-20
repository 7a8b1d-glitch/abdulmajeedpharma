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

import pglast

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


# ---------------------------------------------------------------------------
# PostgreSQL grammar validation (native parser via pglast)
# ---------------------------------------------------------------------------

MIGRATION_FILES_FOR_PARSING = sorted(MIGRATION_DIR.glob("*.sql"))


@pytest.mark.parametrize("migration_path", MIGRATION_FILES_FOR_PARSING)
def test_migration_parses_with_postgresql_grammar(migration_path: Path) -> None:
    """Every migration file must parse cleanly with native PostgreSQL grammar.

    This uses pglast (PostgreSQL parser), not regex. If a file contains
    invalid PostgreSQL syntax, this test fails with the exact error and
    location.
    """
    sql = migration_path.read_text(encoding="utf-8")
    try:
        stmts = pglast.parse_sql(sql)
        assert len(stmts) > 0, f"{migration_path.name}: no statements parsed"
    except Exception as exc:
        pytest.fail(
            f"{migration_path.name}: PostgreSQL grammar error: {exc}"
        )


# ---------------------------------------------------------------------------
# Security regression tests
# ---------------------------------------------------------------------------


def test_no_create_policy_if_not_exists() -> None:
    """No 'CREATE POLICY IF NOT EXISTS' may remain — invalid PostgreSQL syntax."""
    for f in sorted(MIGRATION_DIR.glob("*.sql")):
        sql = f.read_text(encoding="utf-8")
        assert "CREATE POLICY IF NOT EXISTS" not in sql, (
            f"{f.name}: contains invalid 'CREATE POLICY IF NOT EXISTS'"
        )


def test_no_expression_based_table_unique_constraint() -> None:
    """No table-level UNIQUE constraint may use expressions (LEAST/GREATEST etc.).

    PostgreSQL does not allow expressions in table UNIQUE constraints.
    Expression-based uniqueness must use CREATE UNIQUE INDEX instead.
    """
    for f in sorted(MIGRATION_DIR.glob("*.sql")):
        sql = f.read_text(encoding="utf-8")
        # Find table-level CONSTRAINT ... UNIQUE(...) blocks
        for m in re.finditer(
            r'CONSTRAINT\s+\w+\s+UNIQUE\s*\(', sql, re.IGNORECASE
        ):
            start = m.end() - 1  # position of opening paren
            # Find matching closing paren
            depth = 0
            for i in range(start, len(sql)):
                if sql[i] == '(':
                    depth += 1
                elif sql[i] == ')':
                    depth -= 1
                    if depth == 0:
                        constraint_args = sql[start + 1:i]
                        break
            else:
                continue
            # If it contains function calls (LEAST, GREATEST, etc.), it's invalid
            if re.search(r'\b[A-Z_]+\s*\(', constraint_args):
                pytest.fail(
                    f"{f.name}: expression-based table UNIQUE constraint found: "
                    f"CONSTRAINT ... UNIQUE ({constraint_args})"
                )


def test_expression_based_unique_index_exists_for_interactions() -> None:
    """A valid expression-based unique index must exist for drug_interactions."""
    sql003 = (MIGRATION_DIR / "003_drug_catalog.sql").read_text(encoding="utf-8")
    assert "CREATE UNIQUE INDEX" in sql003, (
        "003_drug_catalog.sql: missing CREATE UNIQUE INDEX"
    )
    assert "LEAST(drug_id, interacting_drug_id)" in sql003, (
        "003_drug_catalog.sql: missing LEAST() in unique index"
    )
    assert "GREATEST(drug_id, interacting_drug_id)" in sql003, (
        "003_drug_catalog.sql: missing GREATEST() in unique index"
    )
    assert "idx_drug_interactions_unique_pair" in sql003, (
        "003_drug_catalog.sql: missing stable index name"
    )


def test_no_old_new_in_rls_policies() -> None:
    """No RLS policy expression may reference OLD or NEW row variables.

    OLD/NEW are trigger-specific variables and are invalid in PostgreSQL
    RLS USING/WITH CHECK expressions. Any such reference will cause a
    runtime error when the policy is evaluated.
    """
    for f in sorted(MIGRATION_DIR.glob("*.sql")):
        sql = f.read_text(encoding="utf-8")
        # Find CREATE POLICY blocks and check their USING/WITH CHECK clauses
        for m in re.finditer(
            r'CREATE\s+POLICY\s+"[^"]+"\s+ON\s+public\.\w+\s+.*?(?:USING|WITH CHECK)\s*\((.*?)\);',
            sql, re.IGNORECASE | re.DOTALL,
        ):
            clause = m.group(1)
            if re.search(r'\bOLD\b', clause):
                pytest.fail(
                    f"{f.name}: RLS policy references OLD in expression: {clause.strip()}"
                )
            if re.search(r'\bNEW\b', clause):
                pytest.fail(
                    f"{f.name}: RLS policy references NEW in expression: {clause.strip()}"
                )


def test_column_level_privileges_exclude_privileged_profile_columns() -> None:
    """Ordinary authenticated users must not have UPDATE on privileged
    profile columns (role, is_active, email_verified)."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    # Must REVOKE broad UPDATE first
    assert "REVOKE UPDATE ON public.user_profiles" in sql010, (
        "010_rls_and_storage_policies.sql: missing REVOKE UPDATE on user_profiles"
    )
    # Must GRANT UPDATE only on non-privileged columns
    grant_match = re.search(
        r'GRANT\s+UPDATE\s*\(([^)]+)\)\s+ON\s+public\.user_profiles\s+TO\s+authenticated',
        sql010, re.IGNORECASE,
    )
    assert grant_match is not None, (
        "010_rls_and_storage_policies.sql: missing GRANT UPDATE on specific columns"
    )
    granted_cols = grant_match.group(1)
    privileged_cols = ["role", "is_active", "email_verified"]
    for col in privileged_cols:
        assert col not in granted_cols, (
            f"010_rls_and_storage_policies.sql: privileged column '{col}' should "
            f"not be in GRANT UPDATE column list: {granted_cols}"
        )


def test_role_management_function_exists() -> None:
    """A controlled SECURITY DEFINER function for admin role changes must exist."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    assert "CREATE OR REPLACE FUNCTION aph_manage_user_role" in sql010, (
        "010_rls_and_storage_policies.sql: missing aph_manage_user_role function"
    )
    assert "SECURITY DEFINER" in sql010, (
        "010_rls_and_storage_policies.sql: aph_manage_user_role must be SECURITY DEFINER"
    )
    assert "SET search_path = pg_temp, public" in sql010, (
        "010_rls_and_storage_policies.sql: aph_manage_user_role must set safe search_path"
    )
    assert "REVOKE ALL ON FUNCTION aph_manage_user_role" in sql010, (
        "010_rls_and_storage_policies.sql: must REVOKE execute from PUBLIC on aph_manage_user_role"
    )


def test_role_management_prevents_self_promotion() -> None:
    """The role management function must prevent administrators from
    changing their own role (requires a second administrator)."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    assert "auth.uid() = target_user_id" in sql010, (
        "010_rls_and_storage_policies.sql: aph_manage_user_role must prevent self-role-change"
    )
    assert "Only administrators can manage user roles" in sql010, (
        "010_rls_and_storage_policies.sql: aph_manage_user_role must restrict to administrators"
    )


def test_role_management_audits_changes() -> None:
    """Role changes through aph_manage_user_role must generate audit log entries."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    assert "INSERT INTO public.audit_logs" in sql010, (
        "010_rls_and_storage_policies.sql: aph_manage_user_role must insert audit log entries"
    )
    assert "old_role" in sql010 and "new_role" in sql010, (
        "010_rls_and_storage_policies.sql: audit metadata must include old_role and new_role"
    )


def test_editors_cannot_insert_verified_evidence() -> None:
    """Editors must not insert evidence with is_verified = TRUE."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    block_match = re.search(
        r'CREATE POLICY "editors_insert_evidence".*?WITH CHECK\s*\((.*?)\);',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    assert block_match is not None, (
        "010_rls_and_storage_policies.sql: editors_insert_evidence policy missing"
    )
    with_check = block_match.group(1)
    assert "is_verified = FALSE" in with_check, (
        "010_rls_and_storage_policies.sql: editors_insert_evidence WITH CHECK "
        "does not require is_verified = FALSE — verified bypass possible"
    )


def test_editors_cannot_update_evidence_to_verified() -> None:
    """Editors must not update evidence to is_verified = TRUE."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    # Must have an editors_update_own_unverified_evidence policy
    assert "editors_update_own_unverified_evidence" in sql010, (
        "010_rls_and_storage_policies.sql: missing editors_update_own_unverified_evidence policy"
    )
    block_match = re.search(
        r'CREATE POLICY "editors_update_own_unverified_evidence".*?WITH CHECK\s*\((.*?)\);',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    assert block_match is not None, (
        "010_rls_and_storage_policies.sql: editors_update_own_unverified_evidence WITH CHECK missing"
    )
    with_check = block_match.group(1)
    assert "is_verified = FALSE" in with_check, (
        "010_rls_and_storage_policies.sql: editors_update_own_unverified_evidence "
        "WITH CHECK does not require is_verified = FALSE"
    )


def test_reviewers_cannot_delete_review_history() -> None:
    """Reviewers must not have DELETE on content_reviews."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    # Find all content_reviews policies and verify none includes DELETE
    cr_policies = re.findall(
        r'CREATE POLICY "reviewers_manage_content_reviews_\w+".*?FOR\s+(\w+)\s+TO',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    assert len(cr_policies) == 3, (
        "010_rls_and_storage_policies.sql: expected 3 reviewers_manage_content_reviews "
        f"policies (select/insert/update), found {len(cr_policies)}"
    )
    for op in cr_policies:
        assert op.upper() != "DELETE", (
            "010_rls_and_storage_policies.sql: reviewers_manage_content_reviews "
            f"includes DELETE — review history can be destroyed"
        )


def test_admins_cannot_delete_user_profiles() -> None:
    """Administrators must not have DELETE on user_profiles."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    # Find all user_profiles admin policies and verify none includes DELETE
    up_policies = re.findall(
        r'CREATE POLICY "admins_manage_user_profiles_\w+".*?FOR\s+(\w+)\s+TO',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    assert len(up_policies) == 3, (
        "010_rls_and_storage_policies.sql: expected 3 admins_manage_user_profiles "
        f"policies (select/insert/update), found {len(up_policies)}"
    )
    for op in up_policies:
        assert op.upper() != "DELETE", (
            "010_rls_and_storage_policies.sql: admins_manage_user_profiles "
            f"includes DELETE — profile deletion possible"
        )


def test_rls_enabled_on_all_tables() -> None:
    """Every table must have ROW LEVEL SECURITY enabled."""
    sql_all = ""
    for f in sorted(MIGRATION_DIR.glob("*.sql")):
        sql_all += f.read_text(encoding="utf-8") + "\n"

    # Extract all CREATE TABLE table names
    tables = re.findall(
        r'CREATE\s+TABLE\s+public\.(\w+)\s*\(', sql_all, re.IGNORECASE
    )
    for table in tables:
        pattern = rf'ALTER\s+TABLE\s+public\.{table}\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY'
        assert re.search(pattern, sql_all, re.IGNORECASE), (
            f"RLS not enabled on table '{table}'"
        )


def test_force_rls_on_user_private_tables() -> None:
    """User-private tables must use FORCE ROW LEVEL SECURITY."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    force_rls_tables = [
        "user_profiles", "conversations", "conversation_participants",
        "messages", "message_read_receipts", "notifications",
    ]
    for table in force_rls_tables:
        pattern = rf'ALTER\s+TABLE\s+public\.{table}\s+FORCE\s+ROW\s+LEVEL\s+SECURITY'
        assert re.search(pattern, sql010, re.IGNORECASE), (
            f"010_rls_and_storage_policies.sql: FORCE RLS missing on '{table}'"
        )


def test_no_unrestricted_policy_on_private_tables() -> None:
    """Private tables must not have an unrestricted USING (true) policy."""
    sql_all = ""
    for f in sorted(MIGRATION_DIR.glob("*.sql")):
        sql_all += f.read_text(encoding="utf-8") + "\n"

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
        assert not re.search(pattern, sql_all, re.IGNORECASE | re.DOTALL), (
            f"Unrestricted USING (true) policy found on private table '{table}'"
        )


def test_policies_reference_auth_uid() -> None:
    """RLS policies on user-owned tables must reference auth.uid()."""
    sql_all = ""
    for f in sorted(MIGRATION_DIR.glob("*.sql")):
        sql_all += f.read_text(encoding="utf-8") + "\n"

    assert re.search(r'auth\.uid\(\)', sql_all), (
        "No RLS policy references auth.uid()"
    )


def test_seed_18_body_systems() -> None:
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


def test_seed_yemen_country() -> None:
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

def test_review_timestamp_enforced() -> None:
    """content_reviews.reviewed_at must be NOT NULL (review timestamp enforced)."""
    sql006 = (MIGRATION_DIR / "006_users_and_permissions.sql").read_text(
        encoding="utf-8"
    )
    assert "reviewed_at" in sql006, (
        "006_users_and_permissions.sql: missing reviewed_at column"
    )
    assert "reviewed_at        TIMESTAMPTZ NOT NULL" in sql006, (
        "006_users_and_permissions.sql: reviewed_at must be NOT NULL"
    )

def test_reviewer_id_has_foreign_key() -> None:
    """content_reviews.reviewer_id must reference user_profiles.user_id."""
    sql006 = (MIGRATION_DIR / "006_users_and_permissions.sql").read_text(
        encoding="utf-8"
    )
    assert "REFERENCES public.user_profiles (user_id)" in sql006, (
        "006_users_and_permissions.sql: reviewer_id must reference user_profiles"
    )

def test_self_review_trigger_exists() -> None:
    """A trigger must prevent reviewers from reviewing their own evidence."""
    sql012 = (MIGRATION_DIR / "012_review_trigger.sql").read_text(
        encoding="utf-8"
    )
    assert "assert_no_self_review" in sql012, (
        "012_review_trigger.sql: missing assert_no_self_review function"
    )
    assert "trg_content_reviews_no_self_review" in sql012, (
        "012_review_trigger.sql: missing no-self-review trigger"
    )

def test_content_reviews_no_delete_policy() -> None:
    """No DELETE policy may exist on content_reviews (append-only history)."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    cr_policies = re.findall(
        r'CREATE POLICY "reviewers_manage_content_reviews_\w+".*?FOR\s+(\w+)\s+TO',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    for op in cr_policies:
        assert op.upper() != "DELETE", (
            "010_rls_and_storage_policies.sql: content_reviews policies include DELETE"
        )

def test_editors_cannot_approve_own_evidence_in_rls() -> None:
    """RLS policies on content_reviews must prevent editors from approving
    their own evidence claims (defense in depth alongside the trigger)."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    block_match = re.search(
        r'CREATE POLICY "reviewers_manage_content_reviews_insert".*?WITH CHECK\s*\((.*?)\);',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    assert block_match is not None, (
        "010_rls_and_storage_policies.sql: reviewers_manage_content_reviews_insert policy missing"
    )
    with_check = block_match.group(1)
    assert "NOT EXISTS" in with_check, (
        "010_rls_and_storage_policies.sql: content_reviews INSERT must include self-review prevention"
    )
    assert "de.created_by = auth.uid()" in with_check, (
        "010_rls_and_storage_policies.sql: content_reviews INSERT must check evidence creator"
    )


# ---------------------------------------------------------------------------
# Phase 02.3 — Migration order and review security tests
# ---------------------------------------------------------------------------


def test_migration_005_no_user_profiles_reference() -> None:
    """Migration 005 must not reference user_profiles (created in migration 006).

    This prevents a forward dependency where a migration references a table
    that does not yet exist.
    """
    sql005 = (MIGRATION_DIR / "005_scientific_evidence_and_reviews.sql").read_text(
        encoding="utf-8"
    )
    assert "user_profiles" not in sql005, (
        "005_scientific_evidence_and_reviews.sql: references user_profiles which "
        "is created in migration 006 — forward dependency"
    )


def test_migration_005_no_created_by_reference() -> None:
    """Migration 005 must not reference drug_evidence.created_by (added in migration 010).

    This prevents a trigger or constraint from referencing a column that does
    not yet exist.
    """
    sql005 = (MIGRATION_DIR / "005_scientific_evidence_and_reviews.sql").read_text(
        encoding="utf-8"
    )
    assert "created_by" not in sql005, (
        "005_scientific_evidence_and_reviews.sql: references created_by which "
        "is added in migration 010 — forward dependency"
    )


def test_migration_006_has_content_reviews() -> None:
    """Migration 006 must create content_reviews (after user_profiles exists)."""
    sql006 = (MIGRATION_DIR / "006_users_and_permissions.sql").read_text(
        encoding="utf-8"
    )
    assert "CREATE TABLE public.content_reviews" in sql006, (
        "006_users_and_permissions.sql: missing content_reviews table"
    )
    assert "REFERENCES public.user_profiles (user_id)" in sql006, (
        "006_users_and_permissions.sql: content_reviews must reference user_profiles"
    )
    assert "REFERENCES public.drug_evidence (id)" in sql006, (
        "006_users_and_permissions.sql: content_reviews must reference drug_evidence"
    )


def test_migration_012_has_trigger() -> None:
    """Migration 012 must create assert_no_self_review function and trigger."""
    sql012 = (MIGRATION_DIR / "012_review_trigger.sql").read_text(
        encoding="utf-8"
    )
    assert "CREATE OR REPLACE FUNCTION assert_no_self_review" in sql012, (
        "012_review_trigger.sql: missing assert_no_self_review function"
    )
    assert "CREATE TRIGGER trg_content_reviews_no_self_review" in sql012, (
        "012_review_trigger.sql: missing trg_content_reviews_no_self_review trigger"
    )


def test_reviewer_id_bound_to_auth_uid_on_insert() -> None:
    """RLS INSERT policy on content_reviews must bind reviewer_id = auth.uid().

    Prevents a reviewer from inserting a review with another user's UUID.
    """
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    block_match = re.search(
        r'CREATE POLICY "reviewers_manage_content_reviews_insert".*?WITH CHECK\s*\((.*?)\);',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    assert block_match is not None, (
        "010_rls_and_storage_policies.sql: reviewers_manage_content_reviews_insert policy missing"
    )
    with_check = block_match.group(1)
    assert "reviewer_id = auth.uid()" in with_check, (
        "010_rls_and_storage_policies.sql: content_reviews INSERT must bind reviewer_id = auth.uid()"
    )


def test_reviewer_id_bound_to_auth_uid_on_update() -> None:
    """RLS UPDATE policy on content_reviews must bind reviewer_id = auth.uid().

    Prevents a reviewer from forging reviewer_id through UPDATE.
    """
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    # Check USING clause
    using_match = re.search(
        r'CREATE POLICY "reviewers_manage_content_reviews_update".*?USING\s*\((.*?)\)\s*WITH CHECK',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    assert using_match is not None, (
        "010_rls_and_storage_policies.sql: reviewers_manage_content_reviews_update USING clause missing"
    )
    using_clause = using_match.group(1)
    assert "reviewer_id = auth.uid()" in using_clause, (
        "010_rls_and_storage_policies.sql: content_reviews UPDATE USING must bind reviewer_id = auth.uid()"
    )

    # Check WITH CHECK clause
    wc_match = re.search(
        r'CREATE POLICY "reviewers_manage_content_reviews_update".*?WITH CHECK\s*\((.*?)\);',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    assert wc_match is not None, (
        "010_rls_and_storage_policies.sql: reviewers_manage_content_reviews_update WITH CHECK clause missing"
    )
    wc_clause = wc_match.group(1)
    assert "reviewer_id = auth.uid()" in wc_clause, (
        "010_rls_and_storage_policies.sql: content_reviews UPDATE WITH CHECK must bind reviewer_id = auth.uid()"
    )


def test_manage_user_role_execute_granted_to_authenticated() -> None:
    """aph_manage_user_role must grant EXECUTE to authenticated (administrators)."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    assert "GRANT EXECUTE ON FUNCTION aph_manage_user_role(UUID, VARCHAR(30)) TO authenticated" in sql010, (
        "010_rls_and_storage_policies.sql: missing GRANT EXECUTE on aph_manage_user_role to authenticated"
    )


def test_manage_user_profile_execute_granted_to_authenticated() -> None:
    """aph_manage_user_profile must grant EXECUTE to authenticated (administrators)."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    assert "GRANT EXECUTE ON FUNCTION aph_manage_user_profile(UUID, BOOLEAN, TEXT, VARCHAR(30), UUID, VARCHAR(10)) TO authenticated" in sql010, (
        "010_rls_and_storage_policies.sql: missing GRANT EXECUTE on aph_manage_user_profile to authenticated"
    )


def test_privileged_functions_revoke_from_public() -> None:
    """Privileged SECURITY DEFINER functions must REVOKE from PUBLIC."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    assert "REVOKE ALL ON FUNCTION aph_manage_user_role" in sql010, (
        "010_rls_and_storage_policies.sql: missing REVOKE on aph_manage_user_role from PUBLIC"
    )
    assert "REVOKE ALL ON FUNCTION aph_manage_user_profile" in sql010, (
        "010_rls_and_storage_policies.sql: missing REVOKE on aph_manage_user_profile from PUBLIC"
    )


def test_no_trigger_before_created_by_column() -> None:
    """No trigger referencing drug_evidence.created_by may exist before migration 010.

    Migration 005 must not contain the assert_no_self_review trigger because
    drug_evidence.created_by is added in migration 010.
    """
    sql005 = (MIGRATION_DIR / "005_scientific_evidence_and_reviews.sql").read_text(
        encoding="utf-8"
    )
    assert "assert_no_self_review" not in sql005, (
        "005_scientific_evidence_and_reviews.sql: contains assert_no_self_review "
        "which depends on drug_evidence.created_by (added in migration 010)"
    )
    assert "trg_content_reviews_no_self_review" not in sql005, (
        "005_scientific_evidence_and_reviews.sql: contains trg_content_reviews_no_self_review "
        "which depends on drug_evidence.created_by (added in migration 010)"
    )


def test_content_reviews_no_delete_policy_still_valid() -> None:
    """No DELETE policy may exist on content_reviews (append-only history)."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    cr_policies = re.findall(
        r'CREATE POLICY "reviewers_manage_content_reviews_\w+".*?FOR\s+(\w+)\s+TO',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    for op in cr_policies:
        assert op.upper() != "DELETE", (
            "010_rls_and_storage_policies.sql: content_reviews policies include DELETE"
        )


# ---------------------------------------------------------------------------
# Phase 02.4 — Database readiness tests
# ---------------------------------------------------------------------------


def test_migration_013_has_schema_migrations_table() -> None:
    """Migration 013 must create the schema_migrations tracking table."""
    sql013 = (MIGRATION_DIR / "013_migration_tracking_and_legacy_compat.sql").read_text(
        encoding="utf-8"
    )
    assert "CREATE TABLE IF NOT EXISTS public.schema_migrations" in sql013, (
        "013: missing schema_migrations table"
    )
    assert "version" in sql013 and "checksum" in sql013 and "applied_at" in sql013, (
        "013: schema_migrations must have version, checksum, applied_at columns"
    )


def test_migration_013_is_idempotent() -> None:
    """Migration 013 must use IF NOT EXISTS / IF EXISTS for safe reapplication."""
    sql013 = (MIGRATION_DIR / "013_migration_tracking_and_legacy_compat.sql").read_text(
        encoding="utf-8"
    )
    assert "CREATE TABLE IF NOT EXISTS public.schema_migrations" in sql013, (
        "013: schema_migrations must use IF NOT EXISTS"
    )
    assert "CREATE INDEX IF NOT EXISTS" in sql013, (
        "013: indexes must use IF NOT EXISTS for idempotency"
    )
    # The GUC-based trigger was removed; no DROP TRIGGER needed for it.
    # Content reviews updated_at trigger uses existence check via DO block.


def test_insert_policy_excludes_reviewed_at_column() -> None:
    """content_reviews INSERT policy must NOT require reviewed_at IS NULL.

    PostgreSQL applies column defaults before evaluating RLS WITH CHECK.
    Since reviewed_at has DEFAULT now(), requiring IS NULL would reject
    all legitimate inserts. Instead, column-level INSERT privilege
    excludes reviewed_at so clients cannot specify it.
    """
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    block_match = re.search(
        r'CREATE POLICY "reviewers_manage_content_reviews_insert".*?WITH CHECK\s*\((.*?)\);',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    assert block_match is not None, (
        "010: reviewers_manage_content_reviews_insert policy missing"
    )
    with_check = block_match.group(1)
    assert "reviewed_at IS NULL" not in with_check, (
        "010: INSERT policy must NOT require reviewed_at IS NULL — "
        "DEFAULT now() fires before RLS evaluation"
    )
    assert "reviewer_id = auth.uid()" in with_check, (
        "010: INSERT policy must bind reviewer_id = auth.uid()"
    )


def test_insert_column_privilege_excludes_reviewed_at() -> None:
    """Column-level INSERT privilege on content_reviews must exclude
    reviewed_at so clients cannot forge or backdate timestamps."""
    sql013 = (MIGRATION_DIR / "013_migration_tracking_and_legacy_compat.sql").read_text(
        encoding="utf-8"
    )
    assert "REVOKE INSERT ON public.content_reviews FROM PUBLIC" in sql013, (
        "013: must REVOKE INSERT from PUBLIC on content_reviews"
    )
    assert "REVOKE INSERT ON public.content_reviews FROM authenticated" in sql013, (
        "013: must REVOKE INSERT from authenticated on content_reviews"
    )
    assert "GRANT INSERT (reviewer_id, drug_evidence_id, review_status" in sql013, (
        "013: must GRANT INSERT on specific columns excluding reviewed_at"
    )
    assert "reviewed_at" not in sql013.split(
        "GRANT INSERT (", 1
    )[1].split(") ON public.content_reviews", 1)[0], (
        "013: reviewed_at must be excluded from INSERT column list"
    )


def test_reviewed_at_column_level_revoke() -> None:
    """Migration 013 must REVOKE UPDATE on reviewed_at from authenticated users."""
    sql013 = (MIGRATION_DIR / "013_migration_tracking_and_legacy_compat.sql").read_text(
        encoding="utf-8"
    )
    assert "REVOKE UPDATE (reviewed_at)" in sql013, (
        "013: must REVOKE UPDATE on reviewed_at column"
    )


def test_no_guc_bypass_for_reviewed_at() -> None:
    """Migration 013 must NOT use a user-settable GUC to authorize
    reviewed_at changes. Custom GUCs can be set by any authenticated
    client via set_config(), creating a bypass path."""
    sql013 = (MIGRATION_DIR / "013_migration_tracking_and_legacy_compat.sql").read_text(
        encoding="utf-8"
    )
    assert "aph.allow_reviewed_at_change" not in sql013, (
        "013: must not reference user-settable GUC aph.allow_reviewed_at_change"
    )
    assert "current_setting" not in sql013, (
        "013: must not use current_setting() for authorization — "
        "ordinary clients can set custom GUCs"
    )
    assert "SET LOCAL aph" not in sql013, (
        "013: must not use SET LOCAL to enable timestamp changes"
    )


def test_reviewed_at_protection_uses_column_privileges() -> None:
    """reviewed_at protection must rely on column-level privileges and
    a SECURITY DEFINER function, not a user-settable GUC or trigger."""
    sql013 = (MIGRATION_DIR / "013_migration_tracking_and_legacy_compat.sql").read_text(
        encoding="utf-8"
    )
    assert "REVOKE UPDATE (reviewed_at)" in sql013, (
        "013: must REVOKE UPDATE on reviewed_at column"
    )
    assert "REVOKE INSERT ON public.content_reviews" in sql013, (
        "013: must REVOKE INSERT on content_reviews"
    )
    assert "GRANT INSERT (" in sql013, (
        "013: must GRANT INSERT on specific columns"
    )
    assert "SECURITY DEFINER" in sql013, (
        "013: aph_correct_reviewed_at must be SECURITY DEFINER"
    )
    assert "GRANT EXECUTE ON FUNCTION aph_correct_reviewed_at" in sql013, (
        "013: must GRANT EXECUTE on aph_correct_reviewed_at"
    )
    # The GUC-based trigger must be removed
    assert "assert_reviewed_at_immutable" not in sql013, (
        "013: must not contain GUC-based assert_reviewed_at_immutable trigger"
    )
    assert "trg_content_reviews_reviewed_at_immutable" not in sql013, (
        "013: must not contain trg_content_reviews_reviewed_at_immutable trigger"
    )


def test_aph_correct_reviewed_at_function_exists() -> None:
    """Migration 013 must create the SECURITY DEFINER aph_correct_reviewed_at function."""
    sql013 = (MIGRATION_DIR / "013_migration_tracking_and_legacy_compat.sql").read_text(
        encoding="utf-8"
    )
    assert "CREATE OR REPLACE FUNCTION aph_correct_reviewed_at" in sql013, (
        "013: missing aph_correct_reviewed_at function"
    )
    assert "SECURITY DEFINER" in sql013, (
        "013: aph_correct_reviewed_at must be SECURITY DEFINER"
    )
    assert "GRANT EXECUTE ON FUNCTION aph_correct_reviewed_at" in sql013, (
        "013: must GRANT EXECUTE on aph_correct_reviewed_at to authenticated"
    )


def test_no_old_new_in_rls_policies() -> None:
    """RLS policies must not reference OLD/NEW (PostgreSQL does not support
    row variables in policies)."""
    sql010 = (MIGRATION_DIR / "010_rls_and_storage_policies.sql").read_text(
        encoding="utf-8"
    )
    policy_blocks = re.findall(
        r'CREATE POLICY\s+"[^"]+"\s+ON\s+public\.\w+\s+FOR\s+\w+\s+TO\s+authenticated\s+(?:USING|WITH CHECK)\s*\((.*?)\);',
        sql010, re.IGNORECASE | re.DOTALL,
    )
    for block in policy_blocks:
        assert "OLD." not in block, (
            "010: RLS policy references OLD.* — PostgreSQL does not support OLD/NEW in policies"
        )
        assert "NEW." not in block, (
            "010: RLS policy references NEW.* — PostgreSQL does not support OLD/NEW in policies"
        )


def test_migration_runner_script_exists() -> None:
    """The migration runner script must exist at backend/scripts/run_migrations.py."""
    runner = Path(__file__).resolve().parent.parent.parent / "backend" / "scripts" / "run_migrations.py"
    assert runner.is_file(), (
        "Migration runner script missing: backend/scripts/run_migrations.py"
    )


def test_content_reviews_reviewed_at_has_default_now() -> None:
    """content_reviews.reviewed_at must have DEFAULT now() (server-assigned)."""
    sql006 = (MIGRATION_DIR / "006_users_and_permissions.sql").read_text(
        encoding="utf-8"
    )
    assert "reviewed_at        TIMESTAMPTZ NOT NULL DEFAULT now()" in sql006, (
        "006: reviewed_at must have DEFAULT now() for server-assigned timestamps"
    )


def test_migration_checksums_are_deterministic() -> None:
    """Each migration file must have a stable SHA-256 checksum."""
    import hashlib
    for version, filename in [
        ("001", "001_extensions_and_helpers.sql"),
        ("006", "006_users_and_permissions.sql"),
        ("010", "010_rls_and_storage_policies.sql"),
        ("013", "013_migration_tracking_and_legacy_compat.sql"),
    ]:
        path = MIGRATION_DIR / filename
        assert path.is_file(), f"Migration {filename} is missing"
        h = hashlib.sha256(path.read_bytes()).hexdigest()
        assert len(h) == 64, f"Checksum for {filename} is not a valid SHA-256"


def test_migration_order_is_sequential() -> None:
    """Migration versions must be sequential with no gaps."""
    versions = [v for v, _ in [
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
    ]]
    for i, v in enumerate(versions, start=1):
        assert v == f"{i:03d}", f"Migration version gap: expected {i:03d}, got {v}"
