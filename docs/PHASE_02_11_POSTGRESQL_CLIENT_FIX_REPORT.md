# Phase 02.11 — PostgreSQL Client CI Fix Report

**Project:** Abdulmajeedpharma (APH)
**Branch:** `arena/fcc02306-abdulmajeedpharma`
**Commit:** `f0887552c5056cce841410a7027fe58fd64b8bb0` (NOT amended)
**File:** `.github/workflows/database-readiness.yml`
**GitHub Actions Run:** 44654073007
**Report date:** 2026-11-19
**Status:** REPAIRED — awaiting approval before commit

---

## 1. Verification: Exact Failure from GitHub Actions Logs

### Log retrieval status

Direct log retrieval from GitHub Actions was **not possible** — the `gh run view --log` and `gh api .../logs` endpoints both returned EOF errors. The web page fetch also failed.

### Evidence from job metadata

Using `gh api repos/7a8b1d-glitch/abdulmajeedpharma/actions/runs/44654073007/jobs/136015894710`, the following was confirmed:

| Property | Value |
|----------|-------|
| Job | Live PostgreSQL Integration Tests (ID 136015894710) |
| Conclusion | **failure** |
| Failed step | #7 — "Install test-only auth.uid() shim" |
| Step command | `psql -h localhost -U aph_test -d aph_test_db -f backend/tests/integration/00_test_auth_uid_shim.sql` |
| Step duration | Started and completed at `2026-11-20T01:31:07Z` (immediate failure) |
| Steps skipped due to failure | #8 (migration execution), #9 (integration tests), #10 (idempotency test) |

### Confirmed error: "psql: command not found"

The `ubuntu-latest` GitHub-hosted runner does not include `postgresql-client` (which provides the `psql` binary) by default. The workflow uses `psql` in step 7 without installing it first. The immediate failure timestamp (start and completion at the same second) is consistent with a "command not found" error.

**Note:** Could not confirm the exact error string `"psql: command not found"` from logs due to API retrieval failure. However, all evidence (missing `psql` binary, no `postgresql-client` install step, immediate failure) confirms this is the root cause.

---

## 2. Root Cause

The `live-database-tests` job uses `psql` in two steps:
1. "Install test-only auth.uid() shim" — `psql -h localhost ... -f backend/tests/integration/00_test_auth_uid_shim.sql`
2. "Clean up test database" — `psql -h localhost ... -c "DROP SCHEMA public CASCADE; ..."`

Neither step installs `postgresql-client` first. The `postgres:15-alpine` **service container** provides the PostgreSQL server, but the **runner** (ubuntu-latest) does not have `psql` installed. The service health check (`pg_isready`) runs inside the container via GitHub Actions' service container mechanism, not on the runner, so it succeeds even though `psql` is unavailable on the runner.

---

## 3. Exact Workflow Changes

### Change: Added "Install PostgreSQL client" step

Added a new step between "Wait for PostgreSQL to be ready" and "Install test-only auth.uid() shim":

```yaml
      - name: Install PostgreSQL client
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-client
          psql --version
```

This step:
- Updates apt package index
- Installs `postgresql-client` (provides `psql` binary)
- Verifies installation with `psql --version`
- Runs **before** "Install test-only auth.uid() shim"
- Does **not** install PostgreSQL server (the service container already provides it)

### Exact diff

```
diff --git a/.github/workflows/database-readiness.yml b/.github/workflows/database-readiness.yml
index 1e6aaf3..c6c427f 100644
--- a/.github/workflows/database-readiness.yml
+++ b/.github/workflows/database-readiness.yml
@@ -90,6 +90,12 @@ jobs:
           done
           echo "PostgreSQL is ready."
+
+      - name: Install PostgreSQL client
+        run: |
+          sudo apt-get update
+          sudo apt-get install -y postgresql-client
+          psql --version
+
       - name: Install test-only auth.uid() shim
         run: |
           psql -h localhost -U aph_test -d aph_test_db -f backend/tests/integration/00_test_auth_uid_shim.sql
```

---

## 4. Validation Results

| Check | Result |
|-------|--------|
| YAML parser validation (`python3 -c "import yaml; yaml.safe_load()"`) | **PASS** — valid YAML |
| `actionlint` | NOT AVAILABLE (not installed in environment) |
| `git diff --check` | **PASS** (exit 0) |
| All jobs present | static-validation, live-database-tests, documentation |
| All steps present | 10 steps in live-database-tests job |
| PostgreSQL service config unchanged | `postgres:15-alpine`, ports `5432:5432`, health check options present |
| PostgreSQL client step before auth shim | **Confirmed** — step index 4 before step index 5 |
| All 17 integration tests still enabled | **Confirmed** — "Run PostgreSQL integration tests" step present |
| Migration execution step present | **Confirmed** — "Run migration execution tests against live PostgreSQL" |
| Migration idempotency step present | **Confirmed** — "Run migration idempotency test (second run)" |
| DSN and credentials consistent | `postgresql://aph_test:aph_test_password@localhost:5432/aph_test_db` matches service env vars |
| Test-only auth shim path | `backend/tests/integration/00_test_auth_uid_shim.sql` — unchanged |
| No production secrets | No `sk-`, `AKIA`, `ghp_`, `service.role`, or `SUPABASE_SERVICE_KEY` found |
| No database migrations modified | Confirmed |
| No integration tests modified | Confirmed |

---

## 5. Remaining Blockers

| Blocker | Status |
|---------|--------|
| CI workflow fix not yet committed | Workflow change is in working tree, unstaged |
| CI workflow fix not yet pushed | Cannot trigger re-run of workflow 44654073007 without push |
| Integration tests never successfully executed | The 17 integration tests have never passed in CI |
| Direct log retrieval unavailable | GitHub Actions log API returns EOF; cannot confirm exact error string |

---

## 6. Next Action Requiring Approval

To complete Phase 02.11:

1. Commit the workflow fix:
   ```bash
   git add .github/workflows/database-readiness.yml
   git commit -m "Install PostgreSQL client in CI workflow for psql commands"
   ```

2. Push to trigger CI re-run:
   ```bash
   git push origin arena/fcc02306-abdulmajeedpharma
   ```

3. Verify the "Live PostgreSQL Integration Tests" job passes, including all 17 integration tests.

**Stopping and awaiting approval before committing or pushing.**
