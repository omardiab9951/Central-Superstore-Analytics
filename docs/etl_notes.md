# Phase 4 ETL Notes

## Purpose and Scope

This document records the Phase 4 load of `Central_Superstore.xlsx`, sheet `Central_Region`, into the PostgreSQL database `central_superstore_dw`, schema `warehouse`. The workbook is opened for reading only. The ETL does not create analytical queries, views, stored procedures, or a new database schema; it loads the existing five Phase 3 tables and stops before Phase 5.

The runnable implementation is [load_warehouse.py](../etl/load_warehouse.py). Dependencies are pinned in [requirements.txt](../requirements.txt). The script uses the `postgres` connection through libpq, which reads the existing local `pgpass.conf`; no password is stored in the project.

## Beginner Overview

1. Pandas reads the named worksheet and confirms its 2,323 rows and 21 columns against [dataset_profile.md](dataset_profile.md).
2. Text fields are trimmed at the beginning and end. Dates become calendar dates, postal codes stay text, and numeric measures become decimal numbers at the precision supported by the approved PostgreSQL columns.
3. The script builds one row per natural key in each dimension and generates the date calendar from the earliest order date through the latest ship date, including every day in between.
4. It looks up the dimension surrogate keys for every source row. The `ProductID` and cleaned `ProductName` pair is used for product lookup, preserving different names for the same product ID as separate members.
5. One PostgreSQL transaction clears the old rows, bulk-copies all dimensions and facts, and validates counts, foreign keys, calendar continuity, and totals before committing. `DimDate.IsWeekend` is defined by `sql/02_create_dimensions.sql`; ETL only supplies its values. If any operation or validation fails, PostgreSQL rolls the transaction back.
6. PostgreSQL `COPY` is used for batch transfer rather than issuing one insert per row.

## Extract and Cleaning Log

The script opened the workbook in read-only mode and verified exactly 2,323 data rows and these 21 columns in the profiled order. It computes a SHA-256 hash before and after reading; the observed hash remained `abf10f5a41b104af55c78c6fbeec156267abc373d5c885fecaf6c81324660acf`.

| Action | Rows affected | Values handled or changed | Result |
|---|---:|---:|---|
| Trim outer whitespace from all text columns | 4 | 4 changed text values | Removed the trailing spaces from `Product Name` value `Kensington SlimBlade Notebook Wireless Mouse with Nano Receiver ` in four rows. Internal spaces and genuinely different names were not changed. |
| Convert `Order Date` to Python/PostgreSQL date values | 2,323 | 2,323 values converted | All dates parsed; calendar days preserved. |
| Convert `Ship Date` to Python/PostgreSQL date values | 2,323 | 2,323 values converted | All dates parsed; calendar days preserved. |
| Represent `Postal Code` as text | 2,323 | 2,323 values handled | Postal codes are sent as strings and stored in `VARCHAR(20)`, not treated as quantities. |
| Convert `Sales` to `Decimal` at four fractional digits | 2,323 | 980 values normalized at the fourth decimal place | The Phase 2 dictionary defines `NUMERIC(14,4)`. The original Excel numeric values include binary floating-point residue; maximum per-cell normalization difference was approximately `0.000000000003`. |
| Convert `Profit` to `Decimal` at four fractional digits | 2,323 | 1,675 values normalized at the fourth decimal place | Same scale reasoning as Sales; maximum per-cell normalization difference was approximately `0.000000000002`. Negative profit values were kept. |
| Convert `Discount` to `Decimal` at four fractional digits | 2,323 | 0 values changed by rounding | All values fit the approved `NUMERIC(5,4)` representation and remain rates. |
| Validate/cast `Row ID` and `Quantity` as integers | 2,323 | 4,646 values checked; 0 numeric values changed | Both fields were whole numbers in the source. |

The wording “values normalized” refers to a difference between `Decimal(str(value))` and its four-decimal representation. It is not a large business adjustment: the Excel raw sums differ from the stored totals only below the database scale. Both raw and normalized totals are shown in the validation results.

## Dimension and Fact Results

| Table | Rows loaded | How rows were identified |
|---|---:|---|
| `DimDate` | 1,464 | One continuous calendar date from 2013-01-03 through 2017-01-05, inclusive |
| `DimCustomer` | 629 | One row per `Customer ID` |
| `DimProduct` | 1,326 | One row per cleaned `(Product ID, Product Name)` pair |
| `DimLocation` | 195 | One row per `(Country, State, City, Postal Code)` tuple |
| `FactSales` | 2,323 | One row per source `Row ID` / product line |

Surrogate keys are generated deterministically for the three identity-key dimensions in sorted natural-key order during each full reload. The identity sequences are advanced to match those keys so later inserts can continue safely. `DateKey` is an integer in `YYYYMMDD` form. Each fact row resolves to customer, product, location, order-date, and ship-date keys before loading.

## Data Findings and Decisions

- Phase 1 found 16 `Product ID`s with multiple product names. The ETL keeps each distinct cleaned `(Product ID, Product Name)` as its own `DimProduct` member, consistent with Phase 2. It does not select an invented canonical name.
- Four source text cells had a trailing space in one product-name value; trimming those exact outer spaces makes the label consistent while keeping genuinely different product names distinct.
- The source has 741 negative-profit lines; these are retained as losses.
- Phase 1 found no missing cells, duplicate full rows, invalid quantities, non-positive sales, discount values outside 0 to 1, or ship dates before order dates. The ETL checks the critical constraints again and stops rather than loading invalid rows.
- `DimDate.IsWeekend` was requested in Phase 4 but initially omitted from the Phase 2 dictionary and Phase 3 table. Phase 5 documentation synchronization moved this attribute into `sql/02_create_dimensions.sql` and the design documents. The ETL now only populates it from the calendar date; it does not alter database structure.
- The approved data dictionary specifies four decimal places for Sales and Profit. The raw Excel representations sum to `501239.89079999999149825` and `39706.36249999998025702`; after normalization to the database's four-decimal scale the totals are `501239.8908` and `39706.3625`. They are equal at the stored scale. Quantity remains exactly `8780`.

## Rerun and Transaction Safety

Before loading, the script uses one `TRUNCATE` statement listing `FactSales` first, followed by all four dimensions. PostgreSQL requires the referencing fact and referenced dimensions to be truncated together while foreign keys exist. `RESTART IDENTITY` resets generated fact and dimension sequences. Dimensions are then copied before the fact rows.

The `TRUNCATE`, dimension copies, fact copy, and all reconciliation assertions execute in one transaction. A database error or failed assertion aborts the transaction, leaving the previously committed warehouse contents unchanged. Source extraction and validation happen before the transaction, so source problems do not touch the database.

The full ETL script was run twice successfully. Both runs reported the same row counts and measure totals; the second run replaced the first load rather than appending duplicates.

## Validation Output

Actual output from the successful second run:

```text
Extracted: 2,323 rows x 21 columns from Central_Region
Prepared dimension counts:
  - DimDate: 1,464
  - DimCustomer: 629
  - DimProduct: 1,326
  - DimLocation: 195
  - FactSales: 2,323
Post-load validation:
  - DimDate: 1,464 rows (expected 1,464) - PASS
  - DimCustomer: 629 rows (expected 629) - PASS
  - DimProduct: 1,326 rows (expected 1,326) - PASS
  - DimLocation: 195 rows (expected 195) - PASS
  - FactSales: 2,323 rows (expected 2,323) - PASS
  - NULL foreign-key cells in FactSales: 0 - PASS
  - Total Sales: database=501239.8908 Excel raw=501239.89079999999149825 normalized=501239.8908 - PASS (at warehouse precision)
  - Total Profit: database=39706.3625 Excel raw=39706.36249999998025702 normalized=39706.3625 - PASS (at warehouse precision)
  - Total Quantity: database=8780 Excel raw=8780 normalized=8780 - PASS (at warehouse precision)
  - Continuous DimDate: 2013-01-03 through 2017-01-05 (1,464 days) - PASS
Source workbook unchanged: PASS
```

Phase 4 is complete. Orphan-key checks, broader referential-integrity audits, and the remaining Phase 5 validations are intentionally outside this phase.