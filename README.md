# Mini-Project 2 — Central Superstore Data Warehouse

This project profiles `Central_Superstore.xlsx`, loads the `Central_Region` sheet into a PostgreSQL star schema, validates the warehouse, and provides core and advanced read-only business queries. The implemented scope ends at Phase 7; views, procedures, indexes, and later reporting remain future work.

## Requirements

- PostgreSQL 18 (or a compatible recent PostgreSQL release) with `psql` available.
- Python 3.14.x.
- Windows PowerShell for the commands below; adjust PostgreSQL's `bin` path if it is installed elsewhere.
- The supplied workbook at the project root. Keep the original workbook unchanged.

## PostgreSQL Credentials

The ETL and reconciliation scripts connect as PostgreSQL role `postgres` on `localhost:5432`. Store its password in your local libpq password file, not in the project. On Windows, the default path is `%APPDATA%\postgresql\pgpass.conf`. A line has this format:

```text
localhost:5432:*:postgres:<your-local-password>
```

Replace the placeholder locally with your own password. Do not commit `pgpass.conf`, paste a real password into project files, or put one on a command line. Restrict access to the local file to your Windows account.

## Setup and Run Order (Phases 1–7)

Run these commands from the project root in PowerShell. The pinned Python dependencies were installed and the ETL was run from a fresh virtual environment during the Phase 1–5 audit.

```powershell
py -3.14 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt

# Phase 1: re-profile the workbook and write docs/dataset_profile.md
.\.venv\Scripts\python.exe scripts\profile_dataset.py

# Phase 3: create the default database, schema, dimensions, fact, and constraints.
# Set $psql to your PostgreSQL installation's psql.exe first.
$pgBin = 'C:\Program Files\PostgreSQL\18\bin'
$psql = Join-Path $pgBin 'psql.exe'
& $psql -h localhost -p 5432 -U postgres -d postgres -v ON_ERROR_STOP=1 -f sql\01_create_database.sql
& $psql -h localhost -p 5432 -U postgres -d postgres -v ON_ERROR_STOP=1 -f sql\02_create_dimensions.sql
& $psql -h localhost -p 5432 -U postgres -d postgres -v ON_ERROR_STOP=1 -f sql\03_create_fact.sql
& $psql -h localhost -p 5432 -U postgres -d postgres -v ON_ERROR_STOP=1 -f sql\04_constraints.sql

# Phase 4: load the workbook into central_superstore_dw.
.\.venv\Scripts\python.exe etl\load_warehouse.py

# Phase 5: run read-only SQL checks, then read-only Excel reconciliation.
& $psql -h localhost -p 5432 -U postgres -d central_superstore_dw -v ON_ERROR_STOP=1 -f sql\05_validation.sql
.\.venv\Scripts\python.exe etl\reconcile_with_excel.py

# Phase 6: run the 20 read-only core business queries.
& $psql -h localhost -p 5432 -U postgres -d central_superstore_dw -v ON_ERROR_STOP=1 -P pager=off -f sql\08_business_queries.sql

# Phase 7: run the 12 read-only advanced SQL queries.
& $psql -h localhost -p 5432 -U postgres -d central_superstore_dw -v ON_ERROR_STOP=1 -P pager=off -f sql\09_advanced_sql.sql
```

The Phase 6 file [sql/08_business_queries.sql](sql/08_business_queries.sql) contains 20 read-only core business queries. The Phase 7 file [sql/09_advanced_sql.sql](sql/09_advanced_sql.sql) contains 12 advanced read-only queries demonstrating CTEs, window functions, correlated subqueries, and analytical techniques. Neither file changes database state. Explanations, actual PostgreSQL samples, and pandas verification are documented in [docs/queries_phase6.md](docs/queries_phase6.md) and [docs/queries_phase7.md](docs/queries_phase7.md).

The plan's Phase 5 filename `sql/07_data_validation.sql` is also available as a `psql` include of the maintained `05_validation.sql` checks.

**The loader replaces rows in its target warehouse.** It performs the truncate, load, and in-transaction reconciliation atomically. For a rebuild or reload test, use a disposable database and pass its name to the DDL scripts and loader. For example, add `-v warehouse_db=central_superstore_audit` to each `psql` invocation for `01–04`, and pass `--database central_superstore_audit` to `load_warehouse.py`. The default is `central_superstore_dw` when `warehouse_db` is omitted.

Phase 2 design is documented before the SQL files are run. `sql/02_create_dimensions.sql` drops and recreates the warehouse tables; keep any rebuild testing isolated from data you need.

## Current Project Structure (Phases 1–7)

```text
Mini_Project_2/
|-- Central_Superstore.xlsx
|-- plan.md
|-- requirements.txt
|-- README.md
|-- .gitignore
|-- docs/
|   |-- dataset_profile.md
|   |-- star_schema.md
|   |-- data_dictionary.md
|   |-- star_schema.png
|   |-- etl_notes.md
|   |-- validation_report.md
|   |-- queries_phase6.md
|   |-- queries_phase7.md
|   |-- audit_phases_1_to_5.md
|-- scripts/
|   |-- profile_dataset.py
|-- etl/
|   |-- load_warehouse.py
|   |-- reconcile_with_excel.py
|-- sql/
    |-- 01_create_database.sql
    |-- 02_create_dimensions.sql
    |-- 03_create_fact.sql
    |-- 04_constraints.sql
    |-- 05_validation.sql
    |-- 07_data_validation.sql  (plan-compatible include)
    |-- 08_business_queries.sql
    |-- 09_advanced_sql.sql
```
