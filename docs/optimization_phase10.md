# Phase 10 Query Optimization

## Scope and Method

Phase 10 added and evaluated five indexes only. No table columns, constraints, data, views, routines, or Excel content were changed. The live warehouse was analyzed before benchmarking. Six representative read-only queries were measured with `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` five times each through [benchmark_phase10.py](../scripts/benchmark_phase10.py). The same statements and helper were used before and after indexes.

Reported execution times are PostgreSQL's `Execution Time` values in milliseconds; medians are over five runs. The first observation is listed separately as the first-run/cold-start attempt. It is **not guaranteed to be a physically cold cache**: Phase 1–9 already used the database, and measured shared read-block counts were zero. PostgreSQL and operating-system caches were not flushed because doing so would require disruptive server-level operations. `ANALYZE` refreshed planner statistics before each baseline/post-index set and after the scale clone was enlarged/indexed.

### How to Read the Plan Terms

- **Seq Scan (sequential scan):** PostgreSQL reads every row in a table. On a 2,323-row table this can be cheaper than looking up many rows through an index.
- **Index Scan:** PostgreSQL uses a B-tree index to locate matching rows and then reads those rows.
- **Bitmap Index Scan / Bitmap Heap Scan:** PostgreSQL finds matching row locations through an index, groups those locations, then reads the relevant table pages. This is useful when more than a handful of rows match.
- **Hash Join:** PostgreSQL builds an in-memory hash lookup from one input and probes it with the other input.
- **Nested Loop:** PostgreSQL takes rows from one input and repeatedly probes another input; this works especially well when the inner lookup is indexed and the outer input is small.
- **Sort / Aggregate:** PostgreSQL orders rows or combines them into groups and totals.
- **Gather / Gather Merge:** PostgreSQL combines work performed by parallel workers.
- **Function Scan:** PostgreSQL calls a set-returning function. Its top-level plan does not expose every internal plan node executed inside the PL/pgSQL function.
- **Shared Hit Blocks:** pages found in PostgreSQL shared memory. **Shared Read Blocks:** pages PostgreSQL had to read into shared memory during that plan.

The reported buffer counts are the root plan totals from the final run in each five-run set. They are not elapsed-time estimates.

## Existing Index Inventory

Before Phase 10, `pg_indexes` reported these 11 indexes. The `pkey` and `UQ_...` indexes were created automatically by primary-key/unique constraints; they were not redundantly recreated.

| Existing index | Existing coverage | Source |
|---|---|---|
| `DimCustomer_pkey` | `DimCustomer(CustomerKey)` | Primary key |
| `UQ_DimCustomer_CustomerID` | `DimCustomer(CustomerID)` | Unique natural key |
| `DimDate_pkey` | `DimDate(DateKey)` | Primary key |
| `UQ_DimDate_FullDate` | `DimDate(FullDate)` | Unique natural key |
| `DimLocation_pkey` | `DimLocation(LocationKey)` | Primary key |
| `UQ_DimLocation_Geography` | `DimLocation(Country, State, City, PostalCode)` | Composite unique natural key |
| `DimProduct_pkey` | `DimProduct(ProductKey)` | Primary key |
| `UQ_DimProduct_ProductID_ProductName` | `DimProduct(ProductID, ProductName)` | Composite unique natural key; its left prefix also begins with ProductID |
| `FactSales_pkey` | `FactSales(SalesKey)` | Primary key |
| `UQ_FactSales_OrderID_ProductKey` | `FactSales(OrderID, ProductKey)` | Unique order/product-member key |
| `UQ_FactSales_SourceRowID` | `FactSales(SourceRowID)` | Unique source row identifier |

No pre-existing index directly covered the individual `FactSales` foreign-key columns. The ProductID and CustomerID indexes already existed, so no duplicate indexes were proposed for them.

## Baseline Workloads

All six queries were run five times before the Phase 10 indexes. A short description of each benchmark workload:

| ID | Workload |
|---|---|
| Q1 | 2015 order-date range joined to DimDate; count lines and sum sales/profit. |
| Q2 | Sales/profit for one customer, filtered by the unique CustomerID. |
| Q3 | Sales/profit for the ProductID `OFF-BI-10004995`, grouped at ProductKey/product-name member grain. |
| Q4 | Filter the category/region profitability view to Texas. |
| Q5 | Q4 2016 ship-date range joined to DimDate. |
| Q6 | Monthly KPI function for 2015 Furniture orders. |

The benchmark helper also measured four SQL rewrite pairs, five runs per statement. Result-row counts and SHA-256 fingerprints were equal for every original/rewritten pair.

## Indexes Added

The re-runnable script [12_indexes.sql](../sql/12_indexes.sql) adds five individual foreign-key indexes. They match joins or filters present in the measured/reporting workloads. No duplicate natural-key, primary-key, or redundant composite indexes were added.

| New index | Intended use |
|---|---|
| `ix_factsales_orderdatekey` on `FactSales(OrderDateKey)` | Order-date joins and filtered time-period reporting. |
| `ix_factsales_shipdatekey` on `FactSales(ShipDateKey)` | Ship-date joins and shipping-period filters. |
| `ix_factsales_customerkey` on `FactSales(CustomerKey)` | Selective customer-to-fact joins. |
| `ix_factsales_productkey` on `FactSales(ProductKey)` | Selective product-member-to-fact joins. |
| `ix_factsales_locationkey` on `FactSales(LocationKey)` | Selective location-to-fact joins. |

Actual script output: first run created five indexes; second run reported each relation already existed and completed without error due to `IF NOT EXISTS`.

## Baseline and Post-Index Measurements: Live Warehouse

| Query | Baseline median ms | After-index median ms | Baseline → after plan signature | Buffers baseline → after | Interpretation |
|---|---:|---:|---|---|---|
| Q1 order-date year filter | 2.033 | 1.359 | FactSales Seq Scan + DimDate index lookup → same | 41 hit / 0 read → 41 / 0 | No plan change; small-table timing variation, not a demonstrated index win. |
| Q2 customer lookup | 0.820 | 0.096 | FactSales Seq Scan + Hash Join → FactSales Bitmap Index/Heap Scan + Nested Loop | 37 / 0 → 10 / 0 | Clear index-driven improvement; about 88% lower median. |
| Q3 product-member lookup | 0.971 | 0.107 | FactSales Seq Scan + Hash Join → FactSales Bitmap Index/Heap Scan + Nested Loop | 37 / 0 → 8 / 0 | Clear index-driven improvement; about 89% lower median. |
| Q4 Texas profitability view | 8.814 | 3.447 | Several joins and sequential scans both times | 85 / 0 → 85 / 0 | Lower measured median, but same scans/buffers; not attributed to the indexes. |
| Q5 ship-date range | 1.041 | 0.646 | FactSales Seq Scan + DimDate index lookup → same | 38 / 0 → 38 / 0 | No plan change; lower timing is within small-run/cache variation. |
| Q6 period KPI function | 15.800 | 11.879 | Function Scan at outer plan both times | 1356 / 0 → 503 / 0 | Lower measured time and buffers; the outer plan cannot show which inner routine scan used an index, so attribution is qualified. |

### Representative Actual Plan Excerpts

Q2 before indexes used a full FactSales scan even though one customer was requested:

```text
Hash Join
  Seq Scan on FactSales (actual rows=2323)
  Hash
    Index Scan using UQ_DimCustomer_CustomerID on DimCustomer (actual rows=1)
Execution Time: about 1.2 ms in the displayed plan
Buffers: shared hit=37
```

Q2 after indexes looked up the customer first, then used the new fact foreign-key index:

```text
Nested Loop
  Index Scan using UQ_DimCustomer_CustomerID on DimCustomer (actual rows=1)
  Bitmap Heap Scan on FactSales (actual rows=11)
    Bitmap Index Scan on ix_factsales_customerkey (actual rows=11)
Execution Time: about 0.23 ms in the displayed plan
Buffers: shared hit=10
```

Q3 showed the analogous `ix_factsales_productkey` bitmap lookup. In contrast, Q1/Q5 and the broad location view still scanned FactSales. Those plans explain why indexing every foreign key does not automatically make every query faster.

## Synthetic Scale Test: 500,000 Fact Rows

This test used a disposable database `central_superstore_phase10_scale`, cloned from the pre-index live warehouse. It added 497,677 synthetic repeated source lines with new `SourceRowID` values and replica-specific `OrderID` values; the dimension foreign keys remained valid. The clone reached exactly 500,000 FactSales rows, was analyzed, benchmarked before indexes, received the same five indexes, was analyzed again, and was benchmarked with the same six workloads. Query outputs matched before and after indexing within that clone. The database was dropped after testing.

| Query | 500k baseline median ms | 500k after-index median ms | Plan result | Interpretation |
|---|---:|---:|---|---|
| Q1 order-date year filter | 138.425 | 123.717 | Parallel FactSales sequential scan both times | No demonstrated index benefit; the year range selects many rows. |
| Q2 customer lookup | 109.191 | 2.940 | Sequential scan/hash join → index/bitmap lookup and nested loop | Strong improvement, about 97%. |
| Q3 product-member lookup | 96.079 | 1.712 | Sequential scan/hash join → index/bitmap lookup and nested loop | Strong improvement, about 98%. |
| Q4 Texas profitability view | 254.148 | 267.788 | Broad sequential scans both times | No improvement; after-index median was about 5% slower. |
| Q5 ship-date range | 106.527 | 110.572 | Parallel FactSales sequential scan both times | No improvement; the selected range is broad and the plan remains sequential. |
| Q6 period KPI function | 364.001 | 338.260 | Function Scan at outer plan both times | Small observed improvement (~7%) but buffer hits did not decrease; no firm index attribution. |

The scale test demonstrates that a foreign-key index can be valuable for highly selective customer/product lookup joins as a fact table grows. Date-range and aggregation workloads that read a large fraction of the fact table still favor sequential scans. A Function Scan hides its internal plan from this outer EXPLAIN output.

## Query Rewrite Comparisons

The helper ran five `EXPLAIN ANALYZE BUFFERS` trials for each version before and after indexing. It also compared ordered result row counts and SHA-256 fingerprints; every pair returned exactly the same rows.

| Rewrite | Live baseline original → rewrite median ms | Live after-index original → rewrite median ms | Same result? | Honest conclusion |
|---|---:|---:|---|---|
| Filter before grouping vs outer filter after grouping | 3.685 → 2.874 | 3.286 → 2.006 | Yes, 1 row each | More explicit early filtering measured faster, but the plan was essentially the same; small table and run variation may contribute. |
| Project four needed columns from a wide subquery vs select four columns directly | 0.879 → 0.623 | 0.441 → 0.418 | Yes, 3 rows each | PostgreSQL pruned unused view columns in both plans; only a small difference remained. |
| `date_trunc()` predicate vs half-open date range | 1.496 → 0.684 | 0.969 → 0.813 | Yes, 47 rows each | The range form is sargable (the indexed date column is compared directly to bounds); before indexes it changed the DimDate plan from sequential scan to its unique FullDate index. |
| Repeated correlated category-average subquery vs one grouped average joined once | 6645.932 → 16.662 | 4150.874 → 19.503 | Yes, 20 rows each | The join/aggregate rewrite is dramatically faster; the original repeatedly re-evaluates a costly view aggregation. |

The correlated-query timing has high run-to-run variation (the baseline original ranged from about 4.0 to 9.5 seconds). Its median is still orders of magnitude above the grouped-join rewrite. Result fingerprints matched exactly.

## Index Storage and ETL Trade-Off

On the live 2,323-row warehouse, FactSales had 304 kB of indexes before the five additions and 552 kB afterward: approximately **248 kB extra**. The live FactSales heap remained 272 kB. On the 500,000-row clone, the five new FK indexes were about 3.4–3.6 MB each (about 17.4 MB total); the full clone FactSales index footprint was about 64 MB alongside a 58 MB FactSales table. Index storage is real and grows with the fact table.

Indexes help reads but require PostgreSQL to maintain each B-tree entry on inserts, updates, and deletes. ETL was timed on two matching disposable clones, one with the five new indexes and one without them, three full transactional loads each:

| Clone | Run times (seconds) | Median seconds | Result |
|---|---|---:|---|
| No new FK indexes | 3.751, 3.486, 3.855 | 3.751 | All row/totals checks passed |
| Five FK indexes present | 3.151, 3.094, 3.163 | 3.151 | All row/totals checks passed |

The indexed test happened second, after the environment and source workbook were already warm. Its faster elapsed time must **not** be interpreted as indexes speeding up ETL. This small 2,323-row test did not show a measurable insert penalty, but the mechanism still adds index maintenance work, which can matter for larger/frequent loads. The existing [load_warehouse.py](../etl/load_warehouse.py) completed successfully with indexes present. Both ETL timing clones were dropped after testing.

## Final Verification and Scope

- `12_indexes.sql` ran on the live warehouse and its second run skipped existing indexes safely.
- Six representative workloads each ran five times before and after indexes; the 500k clone ran the same six workloads five times before and after.
- Four original/rewritten query pairs had identical row counts and result fingerprints.
- The indexed ETL test clone loaded and reconciled successfully.
- `sql/05_validation.sql`: **39 PASS, 0 FAIL** after indexes.
- `sql/08_business_queries.sql`: all 20 statements reran without errors.
- `sql/09_advanced_sql.sql`: all 12 statements reran without errors.
- Phase 9 procedure output remained Sales `501239.8908`, Profit `39706.3625`, Margin `7.92`, Quantity `8780`, Orders `1175`, Customers `629`, AOV `426.59`, loss lines `741`; function yearly totals still reconciled.
- The live FactSales row count and totals stayed at their pre-Phase-10 values. The Excel source hash remained unchanged.
- No materialized view was evaluated: Phase 10 of `plan.md` does not mention one.

**Conclusion:** The clearest measured wins are selective customer and ProductKey joins, especially in the 500,000-row synthetic test. Broad scans/aggregations on this compact production extract generally remain sequential scans, as is appropriate. The optimization claims are limited to the measured plans and timings above.
