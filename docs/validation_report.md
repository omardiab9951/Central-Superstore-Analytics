# Phase 5 Validation Report

## Scope and Safety

This phase performed checks only against the live `central_superstore_dw` warehouse. The Excel workbook was opened read-only; its SHA-256 remained `abf10f5a41b104af55c78c6fbeec156267abc373d5c885fecaf6c81324660acf`. The SQL validation file and Excel reconciliation script use `SELECT` statements and make no changes to the live data.

For Task 0, the Phase 3 SQL scripts were also tested against a disposable clone named `central_superstore_phase5_check`, not against the live warehouse. The clone was rebuilt, ETL-loaded, validated, and then dropped. After cleanup, direct catalog counts on the live database remained: 2,323 facts, 1,464 dates, 629 customers, 1,326 product members, and 195 locations.

## Task 0: Weekend Schema Source of Truth

`DimDate.IsWeekend BOOLEAN NOT NULL` is now declared in [02_create_dimensions.sql](../sql/02_create_dimensions.sql), listed in [star_schema.md](star_schema.md) and [data_dictionary.md](data_dictionary.md), and shown in [star_schema.png](star_schema.png). [load_warehouse.py](../etl/load_warehouse.py) no longer contains `ALTER TABLE`; it only writes the already-defined date attribute. The ETL notes were corrected to match.

Actual disposable-clone rebuild and reload results:

| Step | Actual result |
|---|---|
| Create temporary clone from live database | `CREATE DATABASE` |
| Run `01_create_database.sql` with `warehouse_db=central_superstore_phase5_check` | Connected to test database; `warehouse` schema already existed; no error |
| Run `02_create_dimensions.sql` | Dropped dependent fact/dimensions in order; created four dimensions including `IsWeekend`; no error |
| Run `03_create_fact.sql` | Created `FactSales`; no error |
| Run `04_constraints.sql` | Added natural-key, foreign-key, and check constraints; no error |
| Run ETL on the test database | 1,464 dates, 629 customers, 1,326 product members, 195 locations, 2,323 facts; totals and foreign keys passed |
| Run `05_validation.sql` on test database | 39 PASS, 0 FAIL |
| Drop temporary test database | `DROP DATABASE`; subsequent catalog query returned 0 rows for its name |
| Check live database afterward | 2,323 FactSales, 1,464 DimDate, 629 DimCustomer, 1,326 DimProduct, 195 DimLocation |

This verifies that the canonical SQL definition can rebuild the schema and that the loader works without altering the schema. The populated live warehouse itself was not rebuilt or truncated.

## SQL Validation Results

The script [05_validation.sql](../sql/05_validation.sql) emits the required `check_name`, `expected`, `actual`, and `status` columns. It returned **39 PASS, 0 FAIL** on both the live warehouse and the rebuilt test clone.

| Check name | Expected | Actual | Status | What the check proves |
|---|---:|---:|---|---|
| `row_count_DimDate` | 1464 | 1464 | PASS | Calendar contains all expected days. |
| `row_count_DimCustomer` | 629 | 629 | PASS | Customer dimension count matches the source profile. |
| `row_count_DimProduct_members` | 1326 | 1326 | PASS | Product dimension retains each observed ID/name member. |
| `row_count_DimLocation` | 195 | 195 | PASS | Location dimension count matches the observed geography tuples. |
| `row_count_FactSales` | 2323 | 2323 | PASS | Every source order line is represented in the fact table. |
| `distinct_CustomerIDs` | 629 | 629 | PASS | Customer business identifiers match the source count. |
| `distinct_Location_natural_keys` | 195 | 195 | PASS | Location natural-key tuples match the source count. |
| `distinct_orders` | 1175 | 1175 | PASS | Distinct order IDs match the source count. |
| `orphan_OrderDateKey` | 0 | 0 | PASS | Every order-date key resolves to `DimDate`. |
| `orphan_ShipDateKey` | 0 | 0 | PASS | Every ship-date key resolves to `DimDate`. |
| `orphan_CustomerKey` | 0 | 0 | PASS | Every customer key resolves to `DimCustomer`. |
| `orphan_ProductKey` | 0 | 0 | PASS | Every product key resolves to `DimProduct`. |
| `orphan_LocationKey` | 0 | 0 | PASS | Every location key resolves to `DimLocation`. |
| `NULL_fact_keys_measures` | 0 | 0 | PASS | No fact IDs, foreign keys, ship mode, or measures are NULL. |
| `NULL_DimDate_keys` | 0 | 0 | PASS | Date primary and natural keys are populated. |
| `NULL_DimCustomer_keys` | 0 | 0 | PASS | Customer primary and natural keys are populated. |
| `NULL_DimProduct_keys` | 0 | 0 | PASS | Product primary and composite natural-key fields are populated. |
| `NULL_DimLocation_keys` | 0 | 0 | PASS | Location primary and natural-key fields are populated. |
| `duplicate_CustomerID` | 0 | 0 | PASS | Each customer business key identifies one dimension row. |
| `duplicate_ProductID_ProductName` | 0 | 0 | PASS | Each approved product composite natural key identifies one row. |
| `duplicate_Location_natural_key` | 0 | 0 | PASS | Each country/state/city/postal tuple identifies one location row. |
| `duplicate_DimDate_FullDate` | 0 | 0 | PASS | Each calendar date appears once. |
| `duplicate_FactSales_RowID` | 0 | 0 | PASS | Each source row identifier appears once in the fact table. |
| `duplicate_FactSales_OrderID_ProductKey` | 0 | 0 | PASS | The source-snapshot order/product-member pair remains unique. |
| `unused_DimCustomer_rows` | 0 | 0 | PASS | Every customer dimension row is referenced by a fact row. |
| `unused_DimProduct_rows` | 0 | 0 | PASS | Every product member is referenced by a fact row. |
| `unused_DimLocation_rows` | 0 | 0 | PASS | Every location row is referenced by a fact row. |
| `ship_date_before_order_date` | 0 | 0 | PASS | No fact ships before its order date. |
| `invalid_Discount_range` | 0 | 0 | PASS | Discounts stay in the inclusive 0-to-1 interval. |
| `invalid_Quantity_nonpositive` | 0 | 0 | PASS | Every quantity is positive. |
| `invalid_Sales_negative` | 0 | 0 | PASS | No sales amount is negative. |
| `DimDate_missing_calendar_days` | 0 | 0 | PASS | The date dimension has no gaps between its endpoints. |
| `DimDate_IsWeekend_mismatches` | 0 | 0 | PASS | `IsWeekend` agrees with Saturday/Sunday calculated from the date. |
| `ProductIDs_with_multiple_names` | 16 | 16 | PASS | All known conflicting product IDs remain visible, rather than silently resolved. |
| `distinct_ProductIDs` | 1310 | 1310 | PASS | Distinct source product IDs are preserved. |
| `negative_profit_lines` | 741 | 741 | PASS | Expected loss-making lines are retained. |
| `total_Sales` | 501239.8908 | 501239.8908 | PASS | Sales reconcile at the warehouse `NUMERIC(14,4)` scale. |
| `total_Profit` | 39706.3625 | 39706.3625 | PASS | Profit reconciles at the warehouse `NUMERIC(14,4)` scale. |
| `total_Quantity` | 8780 | 8780 | PASS | Quantity reconciles exactly. |

## Excel Reconciliation Results

The read-only [reconcile_with_excel.py](../etl/reconcile_with_excel.py) used the explicit absolute monetary tolerance **0.0001**. Integer counts and quantity totals were compared exactly. The fixed random seed was **2026**. Summary: **62 PASS, 0 FAIL**.

### Counts and Totals

| Check | Excel expected | PostgreSQL actual | Difference | Status |
|---|---:|---:|---:|---|
| Fact rows | 2323 | 2323 | 0 | PASS |
| Distinct customers | 629 | 629 | 0 | PASS |
| Distinct Product IDs | 1310 | 1310 | 0 | PASS |
| Distinct product members | 1326 | 1326 | 0 | PASS |
| Distinct locations | 195 | 195 | 0 | PASS |
| Distinct orders | 1175 | 1175 | 0 | PASS |
| Total Sales | 501239.89079999999149825 | 501239.8908 | +0.00000000000850175 | PASS |
| Total Profit | 39706.36249999998025702 | 39706.3625 | +0.00000000001974298 | PASS |
| Total Quantity | 8780 | 8780 | 0 | PASS |

The tiny monetary differences are from representing Excel numeric cells as binary floating-point values before storing them at the approved four-decimal PostgreSQL scale. They are much smaller than the `0.0001` tolerance.

### Sales and Profit by Category

Each row below is one of the 6 actual grouped measure comparisons. Difference is PostgreSQL minus Excel.

| Category | Measure | Excel | PostgreSQL | Difference | Status |
|---|---|---:|---:|---:|---|
| Furniture | Sales | 163797.1637999999944083 | 163797.1638 | 0.0000000000055917 | PASS |
| Furniture | Profit | -2871.0494000000032397 | -2871.0494 | 0.0000000000032397 | PASS |
| Office Supplies | Sales | 167026.41499999999750935 | 167026.4150 | 0.00000000000249065 | PASS |
| Office Supplies | Profit | 8879.97989999999059058 | 8879.9799 | 0.00000000000940942 | PASS |
| Technology | Sales | 170416.3119999999995806 | 170416.3120 | 0.0000000000004194 | PASS |
| Technology | Profit | 33697.43199999999290614 | 33697.4320 | 0.00000000000709386 | PASS |

### Sales and Profit by Region/State

Each row is one of the 26 actual grouped measure comparisons. All records are in the `Central` region. Difference is PostgreSQL minus Excel.

| Region | State | Measure | Excel | PostgreSQL | Difference | Status |
|---|---|---|---:|---:|---:|---|
| Central | Illinois | Sales | 80166.1010000000001508 | 80166.1010 | -0.0000000000001508 | PASS |
| Central | Illinois | Profit | -12607.88700000000440364 | -12607.8870 | 0.00000000000440364 | PASS |
| Central | Indiana | Sales | 53555.3599999999970865 | 53555.3600 | 0.0000000000029135 | PASS |
| Central | Indiana | Profit | 18382.9362999999982952 | 18382.9363 | 0.0000000000017048 | PASS |
| Central | Iowa | Sales | 4579.759999999999947 | 4579.7600 | 0.000000000000053 | PASS |
| Central | Iowa | Profit | 1183.8118999999999958 | 1183.8119 | 0.0000000000000042 | PASS |
| Central | Kansas | Sales | 2914.310000000000010 | 2914.3100 | -0.000000000000010 | PASS |
| Central | Kansas | Profit | 836.4434999999999298 | 836.4435 | 0.0000000000000702 | PASS |
| Central | Michigan | Sales | 76269.613999999999676 | 76269.6140 | 0.000000000000324 | PASS |
| Central | Michigan | Profit | 24463.18759999999914120 | 24463.1876 | 0.00000000000085880 | PASS |
| Central | Minnesota | Sales | 29863.150000000000146 | 29863.1500 | -0.000000000000146 | PASS |
| Central | Minnesota | Profit | 10823.1873999999998805 | 10823.1874 | 0.0000000000001195 | PASS |
| Central | Missouri | Sales | 22205.149999999999168 | 22205.1500 | 0.000000000000832 | PASS |
| Central | Missouri | Profit | 6436.2105000000000686 | 6436.2105 | -0.0000000000000686 | PASS |
| Central | Nebraska | Sales | 7464.929999999999685 | 7464.9300 | 0.000000000000315 | PASS |
| Central | Nebraska | Profit | 2037.09419999999963243 | 2037.0942 | 0.00000000000036757 | PASS |
| Central | North Dakota | Sales | 919.91 | 919.9100 | 0.0000 | PASS |
| Central | North Dakota | Profit | 230.1496999999999573 | 230.1497 | 0.0000000000000427 | PASS |
| Central | Oklahoma | Sales | 19683.389999999999919 | 19683.3900 | 0.000000000000081 | PASS |
| Central | Oklahoma | Profit | 4853.9559999999996411 | 4853.9560 | 0.0000000000003589 | PASS |
| Central | South Dakota | Sales | 1315.5600000000000008 | 1315.5600 | -0.0000000000000008 | PASS |
| Central | South Dakota | Profit | 394.8283000000000453 | 394.8283 | -0.0000000000000453 | PASS |
| Central | Texas | Sales | 170188.04579999999588715 | 170188.0458 | 0.00000000000411285 | PASS |
| Central | Texas | Profit | -25729.35630000001184382 | -25729.3563 | 0.00000000001184382 | PASS |
| Central | Wisconsin | Sales | 32114.609999999999822 | 32114.6100 | 0.000000000000178 | PASS |
| Central | Wisconsin | Profit | 8401.80039999999991725 | 8401.8004 | 0.00000000000008275 | PASS |

### Random Full-Line Comparison

The fixed sample contains 20 distinct `Row ID` values. The script joined each fact to both role-playing date references and to customer, product, and location, then compared every one of the 21 source fields. **420 column comparisons were performed; 420 passed.**

| Seed | Sampled Row ID | Compared columns | Result |
|---:|---:|---:|---|
| 2026 | 212 | 21 | PASS |
| 2026 | 7389 | 21 | PASS |
| 2026 | 9873 | 21 | PASS |
| 2026 | 4151 | 21 | PASS |
| 2026 | 7853 | 21 | PASS |
| 2026 | 1724 | 21 | PASS |
| 2026 | 6715 | 21 | PASS |
| 2026 | 7567 | 21 | PASS |
| 2026 | 3898 | 21 | PASS |
| 2026 | 726 | 21 | PASS |
| 2026 | 3193 | 21 | PASS |
| 2026 | 8985 | 21 | PASS |
| 2026 | 6329 | 21 | PASS |
| 2026 | 5169 | 21 | PASS |
| 2026 | 757 | 21 | PASS |
| 2026 | 9894 | 21 | PASS |
| 2026 | 2788 | 21 | PASS |
| 2026 | 4083 | 21 | PASS |
| 2026 | 8311 | 21 | PASS |
| 2026 | 903 | 21 | PASS |

## Known Data Issues and Observations

- **Product names:** 16 `Product ID`s map to multiple source product names. All 16 remain represented as separate `DimProduct` members where their cleaned `(Product ID, Product Name)` keys differ. No canonical names were invented.
- **Negative profit:** 741 fact rows have negative profit. These are expected losses, not validation failures, and were retained.
- **Whitespace:** Four product-name cells had trailing spaces in the original workbook. The Phase 4 loader trimmed those four text values; the workbook itself remains unchanged.
- **Numeric representation:** Excel's raw floating-point sums contain tiny sub-precision artifacts. Differences from PostgreSQL are shown above and remain within the explicit `0.0001` tolerance.
- **Other quality checks:** No orphan foreign keys, duplicate natural keys, null required values, unused customer/product/location rows, date-order violations, invalid discounts, non-positive quantities, negative sales, calendar gaps, or weekend-flag mismatches were found.

## Final Result

| Suite | Checks | Passed | Failed |
|---|---:|---:|---:|
| SQL warehouse checks | 39 | 39 | 0 |
| Excel reconciliation | 62 | 62 | 0 |
| **Combined** | **101** | **101** | **0** |

Phase 5 is complete. No analytical queries, views, stored procedures, or Phase 6 work were added.