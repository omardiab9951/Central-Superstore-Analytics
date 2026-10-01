# Mini-Project 2 — Central Superstore Data Warehouse

This project profiles `Central_Superstore.xlsx`, loads the `Central_Region` sheet into a PostgreSQL star schema, validates the warehouse, provides core and advanced read-only business queries, defines KPI reporting views/routines, and documents measured query optimization. The implemented scope ends at Phase 10; business analytics reporting remains future work.

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

## Setup and Run Order (Phases 1–10)

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

# Phase 8: create or replace the six reporting views.
& $psql -h localhost -p 5432 -U postgres -d central_superstore_dw -v ON_ERROR_STOP=1 -f sql\10_views.sql

# Phase 9: create or replace the KPI procedure and period function.
& $psql -h localhost -p 5432 -U postgres -d central_superstore_dw -v ON_ERROR_STOP=1 -f sql\11_stored_procedures.sql

# Phase 10: create or replace justified fact foreign-key indexes.
& $psql -h localhost -p 5432 -U postgres -d central_superstore_dw -v ON_ERROR_STOP=1 -f sql\12_indexes.sql

# Refresh planner statistics, then measure the documented representative queries.
& $psql -h localhost -p 5432 -U postgres -d central_superstore_dw -v ON_ERROR_STOP=1 -c 'ANALYZE warehouse."FactSales"; ANALYZE warehouse."DimDate"; ANALYZE warehouse."DimCustomer"; ANALYZE warehouse."DimProduct"; ANALYZE warehouse."DimLocation";'
.\.venv\Scripts\python.exe scripts\benchmark_phase10.py --database central_superstore_dw --runs 5
```

The Phase 6 file [sql/08_business_queries.sql](sql/08_business_queries.sql) contains 20 read-only core business queries. The Phase 7 file [sql/09_advanced_sql.sql](sql/09_advanced_sql.sql) contains 12 advanced read-only queries demonstrating CTEs, window functions, correlated subqueries, and analytical techniques. Phase 8's [sql/10_views.sql](sql/10_views.sql) creates or replaces six reporting views. Phase 9's [sql/11_stored_procedures.sql](sql/11_stored_procedures.sql) creates or replaces a KPI procedure and a table-valued period function; neither routine modifies data.

Example Phase 9 procedure call for the full source date range, with no category or region filter (pass NULL placeholders for the OUT values):

```sql
CALL warehouse.sp_calculate_kpis(
    '2013-01-03', '2016-12-30', NULL, NULL,
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL
);
```

Example monthly KPI query:

```sql
SELECT *
FROM warehouse.fn_kpi_by_period('2013-01-03', '2016-12-30', 'month', NULL, NULL)
ORDER BY period_start;
```

NULL date bounds are open-ended; NULL category/region means all values. Full parameter, output, and verification details are in [docs/stored_procedures_phase9.md](docs/stored_procedures_phase9.md), with the plan-compatible [docs/stored_procedure.md](docs/stored_procedure.md) pointer.

Phase 10 index definitions are re-runnable and documented in [docs/optimization_phase10.md](docs/optimization_phase10.md). The read-only benchmark helper [scripts/benchmark_phase10.py](scripts/benchmark_phase10.py) accepts `--database` and runs five `EXPLAIN (ANALYZE, BUFFERS)` trials for its representative workloads. Scale tests must use a disposable clone, never the live warehouse.

The plan's Phase 5 filename `sql/07_data_validation.sql` is also available as a `psql` include of the maintained `05_validation.sql` checks.

**The loader replaces rows in its target warehouse.** It performs the truncate, load, and in-transaction reconciliation atomically. For a rebuild or reload test, use a disposable database and pass its name to the DDL scripts and loader. For example, add `-v warehouse_db=central_superstore_audit` to each `psql` invocation for `01–04`, and pass `--database central_superstore_audit` to `load_warehouse.py`. The default is `central_superstore_dw` when `warehouse_db` is omitted.

Phase 2 design is documented before the SQL files are run. `sql/02_create_dimensions.sql` drops and recreates the warehouse tables; keep any rebuild testing isolated from data you need.

## Current Project Structure (Phases 1–10)

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
|   |-- views_phase8.md
|   |-- stored_procedure.md
|   |-- stored_procedures_phase9.md
|   |-- optimization_phase10.md
|   |-- audit_phases_1_to_5.md
|-- scripts/
|   |-- profile_dataset.py
|   |-- benchmark_phase10.py
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
    |-- 10_views.sql
    |-- 11_stored_procedures.sql
    |-- 12_indexes.sql
```
