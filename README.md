# E-commerce Order Tracking Dashboard

Database for managing e-commerce orders, inventory, shipments, and audit history.

## Repository layout

| Path | Contents |
| --- | --- |
| `build/` | Bash entry point, Python build helper, and configuration example. |
| `database/` | Ordered SQL scripts and the authoritative `manifest.txt`. |
| `docs/` | [FRD](docs/FRD.md), [TDD](docs/TDD.md), [ERD explanation](docs/ERD.md), and diagram sources/exports. |
| `docs/evidence/` | Recorded database and build verification results. |
| `tests/` | Database integration and build safety checks. |
| `requirements.txt` | Python dependencies. |

## Requirements

Use Linux or Windows with WSL, Bash, Git, Python 3.12, and MySQL 8.4 server and clients (`mysql`, `mysqldump`). The build account needs permission to create databases, objects, accounts, roles and grants, and to assign routine definers. Use a local development server with `innodb_flush_log_at_trx_commit=1` and `sync_binlog=1` when binary logging is enabled.

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt
cp build/config.example.env build/config.env
```

Edit `build/config.env` for your MySQL connection, then load it:

```bash
set -a
source build/config.env
set +a
```

Passwords are requested through hidden prompts unless supplied through `DB_ADMIN_PASSWORD`, `DB_APP_PASSWORD`, `APP_ADMIN_PASSWORD`, and `DEMO_PASSWORD`. Keep these values and `build/config.env` out of Git. For a non-local database, set `DB_SSL_CA` to its trusted CA certificate and `DB_APP_HOST` to the application's specific host.

## Build

Commit the repository contents, then create a release tag. For example, after committing:

```bash
git tag v1.0.0
git push origin v1.0.0
bash build/build_database.sh annberjin E-commerce-tracking-dashboard v1.0.0 ecommerce_demo
```

Use a release tag that contains the complete database build. Authenticate Git normally for a private repository. The build clones the exact tag, records its commit, checks `database/manifest.txt`, then runs its SQL files in order. It refuses existing databases or conflicting generated MySQL identities. Choose a new database name for another build. Partial failed builds are retained for inspection.

To verify a committed local tag before publishing it:

```bash
bash build/build_database.sh annberjin E-commerce-tracking-dashboard v1.0.0 ecommerce_demo --source .
```

The build substitutes validated database/account names and generated password hashes into the SQL templates. Run the build script instead of feeding templates directly to `mysql`.

## Initial accounts and verification

The dashboard login `admin` uses `APP_ADMIN_PASSWORD`. Fictional logins `staff`, `staff2`, `customer`, and `customer2` use `DEMO_PASSWORD`. All stored passwords are salted hashes. Sample data includes three products, two shipped orders worth $55 and $40, and one product at its low-stock threshold.

For database `ecommerce_demo`, the backend MySQL account is `ecommerce_demo_app`, with password `DB_APP_PASSWORD`. Its role is `ecommerce_demo_app_runtime`. It can read business data and execute public procedures, but cannot directly modify tables or call the private audit helper. The locked `ecommerce_demo_definer` account supplies the procedures' limited privileges.

Build verification checks objects, relationships, seed counts, reports, and an EXPLAIN plan. Each script's outcome is recorded in BuildLog and `.build-work/<run>/build.log`. Failures stop the sequence and retain the error number, line, and diagnostic message with secrets redacted. Inspect results with:

```sql
SELECT ScriptPath, Outcome, StartedAt, FinishedAt FROM BuildLog ORDER BY BuildID;
SELECT OrderID, StatusCode, OrderValue FROM v_order_summary ORDER BY OrderID;
SELECT COUNT(*) AS ShippedOrders, SUM(OrderValue) AS Sales FROM v_shipped_order_value;
```

## Database tests

Run the integration checks once on a fresh disposable build. They add fixtures and retain their audit history. Use the same connection settings and build/application passwords as above.

```bash
python3 tests/test_database.py --disposable-db ecommerce_demo
python3 tests/test_build.py --source . --tag v1.0.0 --disposable-db ecommerce_demo
```

These checks exercise database rules, permissions, retries, atomic rollback, concurrency, and safe build failures. Build tests use temporary Git fixtures and retain deliberately incomplete databases for inspection. Browser sessions, ownership filters in HTTP endpoints, CSRF protection, server crash recovery, backup restoration, and larger performance workloads remain separate TDD acceptance tests.

Verified on MySQL 8.4.13 and Python 3.12: 46 database checks, 10 build safety checks, and all 56 live column definitions passed. Actual output is in `docs/evidence/database-verification.txt`.

## Calling the database from Flask

Use parameterized calls without an outer transaction and consume all result sets. Each public procedure takes the authenticated account ID, a UTC timestamp, and one context UUID before its operation-specific inputs. It commits the business change and its audit records together. Order lines are a JSON array of `product_id` and integer `quantity` values; prices come from Product. Prices and signed adjustments use validated text inputs so MySQL cannot silently round invalid input before checking it.

The backend must derive the actor from its session, enforce read ownership, and keep MySQL credentials private. Map procedure validation/conflict errors to the TDD's safe API responses. Record failed or unconfirmed attempts in the protected application log; return success only after the database confirms commit.
