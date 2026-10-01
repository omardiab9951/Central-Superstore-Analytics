# Phase 1–5 Audit

**Audit date:** 2026-10-01  
**Project:** Mini-Project 2 — Central Superstore, PostgreSQL  
**Scope:** Phases 1–5 only. No Phase 6+ work was started.

The source workbook SHA-256 was `abf10f5a41b104af55c78c6fbeec156267abc373d5c885fecaf6c81324660acf` before and after the audit. All rebuild and reload checks used a disposable database or isolated temporary PostgreSQL cluster. The live warehouse was queried read-only and was not rebuilt or reloaded.

| Item | Phase | Status (OK / Fixed / Needs decision / Could not verify) | Evidence | What you changed |
|---|---|---|---|---|
| Workbook exists and `Central_Region` is readable | 1 | OK | `Central_Superstore.xlsx`; profiler run completed on the named worksheet. | None |
| Source shape, column names, and observed types | 1 | OK | `docs/dataset_profile.md`; independently read as 2,323 rows × 21 columns with the expected 21 headers. | None |
| Missing values | 1 | OK | Profiler output: 0 missing cells; per-column counts in `docs/dataset_profile.md`. | None |
| Duplicate rows and identifier checks | 1 | OK | Profile reports 0 duplicate full rows and 0 duplicate `Row ID`s; repeated orders/customers/products are described as expected. | None |
| Distinct counts | 1 | OK | Recomputed: 1,175 orders, 629 customers, 1,310 product IDs, 13 states, 181 cities, 4 shipping modes, 3 segments, 3 categories, 17 sub-categories. | None |
| Date and numeric ranges | 1 | OK | Recomputed date spans: order 2013-01-03–2016-12-30; ship 2013-01-07–2017-01-05. Numeric extrema match the profile after its displayed rounding. | None |
| Relationship and consistency checks | 1 | OK | Recomputed: no ship-before-order rows and no within-order conflicts in customer/date/mode; 16 product IDs have multiple names. | None |
| Text and business-data quality observations | 1 | OK | `docs/dataset_profile.md` records four whitespace occurrences, negative-profit rows, categorical values, and mapping conflicts. | None |
| Phase 1 report and validation gate | 1 | OK | `docs/dataset_profile.md`; running `scripts/profile_dataset.py` completed successfully and rewrote the report from the workbook. | None |
| Fact grain is consistent | 2 | OK | `docs/star_schema.md`, `docs/data_dictionary.md`, ETL notes, and loader all describe one source order line/product line per fact row; `SourceRowID` preserves row identity. | None |
| Fact, dimensions, and measures are documented | 2 | OK | Five tables and measures are described in `docs/star_schema.md` and `docs/data_dictionary.md`. | None |
| Natural/surrogate keys, PKs, FKs, and relationships | 2–3 | OK | Docs compared with live `pg_catalog`; 5 PKs, 5 fact FKs, and documented natural/alternate unique keys match. | None |
| Normalization and product-name conflicts | 2 | Needs decision | `docs/star_schema.md` and the profile document 16 conflicting product IDs; current model preserves cleaned `(ProductID, ProductName)` members. Options and recommendation are below. | No canonical-name choice was made. |
| All 21 source columns are accounted for | 2 | OK | Source-column coverage table in `docs/data_dictionary.md`; no source column is dropped. | None |
| Markdown ERD and column dictionary | 2 | Fixed | `docs/star_schema.md` and `docs/data_dictionary.md`; stale Phase 2-only/proposed wording was inconsistent with the live implementation. | Updated docs to describe the audited as-built schema and actual PostgreSQL types. |
| PNG star-schema diagram | 2 | Fixed | `docs/star_schema.png`; its subtitle previously called the schema a proposal. | Updated subtitle to identify it as the schema as built. |
| Database catalog types, columns, nullability, and keys | 3 | Fixed | `information_schema.columns` returned 5 tables/37 columns; `pg_constraint` matched SQL definitions. Data dictionary now records the implemented types and constraints. | Replaced “suggested types” framing and documented identity/default and constraint details. |
| Database creation and schema script | 3 | OK | `sql/01_create_database.sql`; creates the configured/default database and `warehouse` schema. | None |
| Dimension and fact DDL | 3 | OK | `sql/02_create_dimensions.sql`, `sql/03_create_fact.sql`; catalog has the documented four dimensions and one fact table. | None |
| NOT NULL, primary, foreign, unique, and check constraints | 3 | OK | `sql/02_create_dimensions.sql`–`sql/04_constraints.sql`; live catalog confirmed all definitions and no circular dependencies. | None |
| Scripts are rerunnable with a `warehouse_db` variable | 3 | OK | `01–04` each ran twice with `warehouse_db=central_superstore_phase5_audit` on a disposable clone; both rounds completed. | None |
| Default database works without a variable from a clean state | 3 | OK | In a separate temporary PostgreSQL cluster, `01–04` ran twice without `warehouse_db`; `central_superstore_dw` and all five tables were created. Cluster was stopped and removed. | None |
| Loader implementation exists and performs ETL | 4 | OK | `etl/load_warehouse.py`; extracts the workbook, builds dimensions/facts, looks up surrogate keys, and bulk-loads with PostgreSQL `COPY`. | None |
| Trimming, date parsing, numeric handling, and postal-code text | 4 | OK | Loader code and `docs/etl_notes.md`; source strings are trimmed, dates parsed strictly, numerics cast to declared scale, and postal codes remain text. | None |
| Dimension loading order and surrogate-key lookups | 4 | OK | Loader loads dimensions before facts; two disposable reloads produced expected row counts and keys. | None |
| Transaction safety, repeat load, and no schema changes in loader | 4 | OK | Loader uses one transaction and `TRUNCATE ... RESTART IDENTITY`; ran twice on the clone with equal counts/totals. No DDL statements are in the loader. | None |
| Invalid/rejected-row handling | 4 | OK | Workbook has no missing or invalid rows in checked fields; loader raises an error before loading for invalid input rather than silently dropping it. No rejected-row log was needed for this source. | None |
| Fresh virtual-environment dependency install and ETL run | 4 | OK | Installed `requirements.txt` into a new temporary Python 3.14 venv; imports succeeded and the loader completed twice against the disposable clone. | None |
| ETL notes match code | 4 | OK | `docs/etl_notes.md` compared with `etl/load_warehouse.py`; trim, precision, postal-code, transaction, identity, and count descriptions match. | None |
| Source-to-warehouse counts and totals reconcile | 4–5 | OK | Clone loader output and SQL checks: 2,323 facts; sales 501,239.8908; profit 39,706.3625; quantity 8,780. | None |
| Plan-named Phase 5 validation deliverable | 5 | Fixed | Plan names `sql/07_data_validation.sql`; the project maintained the same queries in `sql/05_validation.sql`, as requested for this audit. | Added `sql/07_data_validation.sql` as a `psql` include of the maintained `05_validation.sql`; no duplicate query set. |
| SQL checks test their stated conditions | 5 | OK | `sql/05_validation.sql`: row/count, totals, date rules, key orphans, nulls, duplicates, unused dimensions, and known source findings. It returned 39 rows. | None |
| Constraint-backed checks are identified | 5 | Fixed | Live catalog confirms `NOT NULL`, `UNIQUE`, FK, and range checks that make several matching validation checks redundant during normal constrained writes. | Added this limitation and the need to inspect status rows to `docs/validation_report.md`. |
| SQL validation on live warehouse | 5 | OK | Ran `sql/05_validation.sql` against `central_superstore_dw`: 39 PASS, 0 FAIL. | None |
| Excel reconciliation checks and coverage | 5 | OK | `etl/reconcile_with_excel.py` compares counts, totals, category/state groups, and 20 seeded rows across all 21 columns. | None |
| Excel reconciliation on live warehouse | 5 | OK | Ran reconciliation read-only: 62 PASS, 0 FAIL; 420 sampled column comparisons passed; workbook hash unchanged. | None |
| Validation report matches the actual run | 5 | Fixed | `docs/validation_report.md`; previous clone name/details were not the clone used in this audit. | Updated clone name, rerun evidence, and SQL-check limitation note. |
| Naming and project structure through Phase 5 | Cross-cutting | OK | Names in the loader, SQL, data dictionary, and profile agree; Phase 4 uses a single Python loader, so illustrative split ETL files are not needed. | None |
| Reproduction README | Cross-cutting | Fixed | No README existed at audit start. | Added `README.md` with goal, requirements, pgpass setup without a real password, exact run order, disposable-database guidance, and Phase 1–5 structure. |
| Ignore rules for environments, bytecode, and secrets | Cross-cutting | Fixed | No `.gitignore` existed at audit start. | Added `.gitignore` entries for `.venv`, `__pycache__`, local environment/password files, and private-key files. |
| Credential and machine-specific path scan | Cross-cutting | OK | No local credential values were found. Three credential-shaped matches are in installed pip/pandas sample or test source, not project configuration. No user-profile paths occur in project code/docs; `.venv/pyvenv.cfg` contains the local interpreter home as normal environment metadata, and `.venv` is ignored by Git. PostgreSQL password remains in external pgpass only. | None |
| Reproducible Phase 1–5 run order | Cross-cutting | OK | `README.md` documents profile → DDL 01–04 → ETL → SQL validation → Excel reconciliation. Fresh venv and disposable DB run completed. | None |
| Automatic nonzero exit on SQL `FAIL` | 5 | Could not verify | No failing data state was injected. Source inspection shows `psql` displays a `FAIL` row but does not itself convert that status to a nonzero process exit code; the report now calls this out. | Documented the limitation; normal passing runs were executed. |

## Needs Decision

The source has 16 `ProductID` values associated with multiple observed product names. Current behavior trims outer whitespace and keeps each distinct cleaned `(ProductID, ProductName)` as a `DimProduct` member. The fact table also has `UNIQUE (OrderID, ProductKey)`, which forbids repeating the same product member in one order.

Options:

1. Keep the current source-preserving product members and current unique constraint for this dataset. This is the recommendation for the current assignment because the workbook has no duplicate order/product pairs and no authoritative product-name mapping.
2. Resolve the 16 product-name conflicts from an authoritative source and redesign `DimProduct` around one canonical row per `ProductID`.
3. If future input can contain multiple lines for the same product member in one order, remove `UNIQUE (OrderID, ProductKey)` and rely on `SourceRowID` for line uniqueness.

The current schema and validation results remain correct for the supplied workbook. Do not canonicalize the product names without a decision and authoritative evidence.
