-- Phase 5: read-only data quality checks for the loaded warehouse.
-- Run with psql while connected to central_superstore_dw.
-- Every result uses the same columns: check_name, expected, actual, status.
-- This file contains SELECT statements only; it never changes warehouse data.

\set ON_ERROR_STOP on

WITH checks AS (
    -- Compare dimension and fact row counts with the source profile and ETL results.
    SELECT 'row_count_DimDate'::TEXT AS check_name, '1464'::TEXT AS expected,
           COUNT(*)::TEXT AS actual, COUNT(*) = 1464 AS passed
    FROM warehouse."DimDate"
    UNION ALL
    SELECT 'row_count_DimCustomer', '629', COUNT(*)::TEXT, COUNT(*) = 629
    FROM warehouse."DimCustomer"
    UNION ALL
    SELECT 'row_count_DimProduct_members', '1326', COUNT(*)::TEXT, COUNT(*) = 1326
    FROM warehouse."DimProduct"
    UNION ALL
    SELECT 'row_count_DimLocation', '195', COUNT(*)::TEXT, COUNT(*) = 195
    FROM warehouse."DimLocation"
    UNION ALL
    SELECT 'row_count_FactSales', '2323', COUNT(*)::TEXT, COUNT(*) = 2323
    FROM warehouse."FactSales"
        UNION ALL
        SELECT 'distinct_CustomerIDs', '629', COUNT(DISTINCT "CustomerID")::TEXT,
            COUNT(DISTINCT "CustomerID") = 629
        FROM warehouse."DimCustomer"
        UNION ALL
        SELECT 'distinct_Location_natural_keys', '195', COUNT(*)::TEXT, COUNT(*) = 195
        FROM warehouse."DimLocation"
        UNION ALL
        SELECT 'distinct_orders', '1175', COUNT(DISTINCT "OrderID")::TEXT,
            COUNT(DISTINCT "OrderID") = 1175
        FROM warehouse."FactSales"

    -- Each orphan check finds facts whose foreign key has no matching dimension key.
    UNION ALL
    SELECT 'orphan_OrderDateKey', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."FactSales" f
    LEFT JOIN warehouse."DimDate" d ON d."DateKey" = f."OrderDateKey"
    WHERE d."DateKey" IS NULL
    UNION ALL
    SELECT 'orphan_ShipDateKey', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."FactSales" f
    LEFT JOIN warehouse."DimDate" d ON d."DateKey" = f."ShipDateKey"
    WHERE d."DateKey" IS NULL
    UNION ALL
    SELECT 'orphan_CustomerKey', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."FactSales" f
    LEFT JOIN warehouse."DimCustomer" d ON d."CustomerKey" = f."CustomerKey"
    WHERE d."CustomerKey" IS NULL
    UNION ALL
    SELECT 'orphan_ProductKey', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."FactSales" f
    LEFT JOIN warehouse."DimProduct" d ON d."ProductKey" = f."ProductKey"
    WHERE d."ProductKey" IS NULL
    UNION ALL
    SELECT 'orphan_LocationKey', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."FactSales" f
    LEFT JOIN warehouse."DimLocation" d ON d."LocationKey" = f."LocationKey"
    WHERE d."LocationKey" IS NULL

    -- Check fact identifiers, foreign keys, ship mode, and all measures for NULLs.
    UNION ALL
    SELECT 'NULL_fact_keys_measures', '0',
           (COUNT(*) FILTER (WHERE "SalesKey" IS NULL)
          + COUNT(*) FILTER (WHERE "SourceRowID" IS NULL)
          + COUNT(*) FILTER (WHERE "OrderID" IS NULL)
          + COUNT(*) FILTER (WHERE "OrderDateKey" IS NULL)
          + COUNT(*) FILTER (WHERE "ShipDateKey" IS NULL)
          + COUNT(*) FILTER (WHERE "CustomerKey" IS NULL)
          + COUNT(*) FILTER (WHERE "ProductKey" IS NULL)
          + COUNT(*) FILTER (WHERE "LocationKey" IS NULL)
          + COUNT(*) FILTER (WHERE "ShipMode" IS NULL)
          + COUNT(*) FILTER (WHERE "Sales" IS NULL)
          + COUNT(*) FILTER (WHERE "Quantity" IS NULL)
          + COUNT(*) FILTER (WHERE "Discount" IS NULL)
          + COUNT(*) FILTER (WHERE "Profit" IS NULL))::TEXT,
           (COUNT(*) FILTER (WHERE "SalesKey" IS NULL)
          + COUNT(*) FILTER (WHERE "SourceRowID" IS NULL)
          + COUNT(*) FILTER (WHERE "OrderID" IS NULL)
          + COUNT(*) FILTER (WHERE "OrderDateKey" IS NULL)
          + COUNT(*) FILTER (WHERE "ShipDateKey" IS NULL)
          + COUNT(*) FILTER (WHERE "CustomerKey" IS NULL)
          + COUNT(*) FILTER (WHERE "ProductKey" IS NULL)
          + COUNT(*) FILTER (WHERE "LocationKey" IS NULL)
          + COUNT(*) FILTER (WHERE "ShipMode" IS NULL)
          + COUNT(*) FILTER (WHERE "Sales" IS NULL)
          + COUNT(*) FILTER (WHERE "Quantity" IS NULL)
          + COUNT(*) FILTER (WHERE "Discount" IS NULL)
          + COUNT(*) FILTER (WHERE "Profit" IS NULL)) = 0
    FROM warehouse."FactSales"
    UNION ALL
    SELECT 'NULL_DimDate_keys', '0',
           (COUNT(*) FILTER (WHERE "DateKey" IS NULL)
          + COUNT(*) FILTER (WHERE "FullDate" IS NULL))::TEXT,
           (COUNT(*) FILTER (WHERE "DateKey" IS NULL)
          + COUNT(*) FILTER (WHERE "FullDate" IS NULL)) = 0
    FROM warehouse."DimDate"
    UNION ALL
    SELECT 'NULL_DimCustomer_keys', '0',
           (COUNT(*) FILTER (WHERE "CustomerKey" IS NULL)
          + COUNT(*) FILTER (WHERE "CustomerID" IS NULL))::TEXT,
           (COUNT(*) FILTER (WHERE "CustomerKey" IS NULL)
          + COUNT(*) FILTER (WHERE "CustomerID" IS NULL)) = 0
    FROM warehouse."DimCustomer"
    UNION ALL
    SELECT 'NULL_DimProduct_keys', '0',
           (COUNT(*) FILTER (WHERE "ProductKey" IS NULL)
          + COUNT(*) FILTER (WHERE "ProductID" IS NULL)
          + COUNT(*) FILTER (WHERE "ProductName" IS NULL))::TEXT,
           (COUNT(*) FILTER (WHERE "ProductKey" IS NULL)
          + COUNT(*) FILTER (WHERE "ProductID" IS NULL)
          + COUNT(*) FILTER (WHERE "ProductName" IS NULL)) = 0
    FROM warehouse."DimProduct"
    UNION ALL
    SELECT 'NULL_DimLocation_keys', '0',
           (COUNT(*) FILTER (WHERE "LocationKey" IS NULL)
          + COUNT(*) FILTER (WHERE "Country" IS NULL)
          + COUNT(*) FILTER (WHERE "State" IS NULL)
          + COUNT(*) FILTER (WHERE "City" IS NULL)
          + COUNT(*) FILTER (WHERE "PostalCode" IS NULL))::TEXT,
           (COUNT(*) FILTER (WHERE "LocationKey" IS NULL)
          + COUNT(*) FILTER (WHERE "Country" IS NULL)
          + COUNT(*) FILTER (WHERE "State" IS NULL)
          + COUNT(*) FILTER (WHERE "City" IS NULL)
          + COUNT(*) FILTER (WHERE "PostalCode" IS NULL)) = 0
    FROM warehouse."DimLocation"

    -- Count duplicate natural keys. A count of zero means the key identifies one row.
    UNION ALL
    SELECT 'duplicate_CustomerID', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM (
        SELECT "CustomerID" FROM warehouse."DimCustomer"
        GROUP BY "CustomerID" HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'duplicate_ProductID_ProductName', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM (
        SELECT "ProductID", "ProductName" FROM warehouse."DimProduct"
        GROUP BY "ProductID", "ProductName" HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'duplicate_Location_natural_key', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM (
        SELECT "Country", "State", "City", "PostalCode" FROM warehouse."DimLocation"
        GROUP BY "Country", "State", "City", "PostalCode" HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'duplicate_DimDate_FullDate', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM (
        SELECT "FullDate" FROM warehouse."DimDate"
        GROUP BY "FullDate" HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'duplicate_FactSales_RowID', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM (
        SELECT "SourceRowID" FROM warehouse."FactSales"
        GROUP BY "SourceRowID" HAVING COUNT(*) > 1
    ) duplicates
    UNION ALL
    SELECT 'duplicate_FactSales_OrderID_ProductKey', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM (
        SELECT "OrderID", "ProductKey" FROM warehouse."FactSales"
        GROUP BY "OrderID", "ProductKey" HAVING COUNT(*) > 1
    ) duplicates

    -- Unused dimensions can indicate stale or failed lookups; none are expected here.
    UNION ALL
    SELECT 'unused_DimCustomer_rows', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."DimCustomer" d
    WHERE NOT EXISTS (SELECT 1 FROM warehouse."FactSales" f WHERE f."CustomerKey" = d."CustomerKey")
    UNION ALL
    SELECT 'unused_DimProduct_rows', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."DimProduct" d
    WHERE NOT EXISTS (SELECT 1 FROM warehouse."FactSales" f WHERE f."ProductKey" = d."ProductKey")
    UNION ALL
    SELECT 'unused_DimLocation_rows', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."DimLocation" d
    WHERE NOT EXISTS (SELECT 1 FROM warehouse."FactSales" f WHERE f."LocationKey" = d."LocationKey")

    -- Check that role-specific dates and fact measures obey the approved business rules.
    UNION ALL
    SELECT 'ship_date_before_order_date', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."FactSales" f
    JOIN warehouse."DimDate" order_date ON order_date."DateKey" = f."OrderDateKey"
    JOIN warehouse."DimDate" ship_date ON ship_date."DateKey" = f."ShipDateKey"
    WHERE ship_date."FullDate" < order_date."FullDate"
    UNION ALL
    SELECT 'invalid_Discount_range', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."FactSales" WHERE "Discount" < 0 OR "Discount" > 1
    UNION ALL
    SELECT 'invalid_Quantity_nonpositive', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."FactSales" WHERE "Quantity" <= 0
    UNION ALL
    SELECT 'invalid_Sales_negative', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."FactSales" WHERE "Sales" < 0

    -- Compare expected no-gap calendar length with dates actually present.
    UNION ALL
    SELECT 'DimDate_missing_calendar_days', '0',
           GREATEST((MAX("FullDate") - MIN("FullDate") + 1) - COUNT(*), 0)::TEXT,
           GREATEST((MAX("FullDate") - MIN("FullDate") + 1) - COUNT(*), 0) = 0
    FROM warehouse."DimDate"
    UNION ALL
    SELECT 'DimDate_IsWeekend_mismatches', '0', COUNT(*)::TEXT, COUNT(*) = 0
    FROM warehouse."DimDate"
    WHERE "IsWeekend" <> (EXTRACT(ISODOW FROM "FullDate") IN (6, 7))

    -- These expected source findings are deliberately reported, not treated as quality failures.
    UNION ALL
    SELECT 'ProductIDs_with_multiple_names', '16', COUNT(*)::TEXT, COUNT(*) = 16
    FROM (
        SELECT "ProductID" FROM warehouse."DimProduct"
        GROUP BY "ProductID" HAVING COUNT(DISTINCT "ProductName") > 1
    ) conflicts
    UNION ALL
    SELECT 'distinct_ProductIDs', '1310', COUNT(DISTINCT "ProductID")::TEXT,
           COUNT(DISTINCT "ProductID") = 1310
    FROM warehouse."DimProduct"
    UNION ALL
    SELECT 'negative_profit_lines', '741', COUNT(*)::TEXT, COUNT(*) = 741
    FROM warehouse."FactSales" WHERE "Profit" < 0

    -- Compare additive totals with the source profile, using four-decimal warehouse precision.
    UNION ALL
    SELECT 'total_Sales', '501239.8908', COALESCE(SUM("Sales"), 0)::TEXT,
           COALESCE(SUM("Sales"), 0) = 501239.8908::NUMERIC
    FROM warehouse."FactSales"
    UNION ALL
    SELECT 'total_Profit', '39706.3625', COALESCE(SUM("Profit"), 0)::TEXT,
           COALESCE(SUM("Profit"), 0) = 39706.3625::NUMERIC
    FROM warehouse."FactSales"
    UNION ALL
    SELECT 'total_Quantity', '8780', COALESCE(SUM("Quantity"), 0)::TEXT,
           COALESCE(SUM("Quantity"), 0) = 8780
    FROM warehouse."FactSales"
)
SELECT
    check_name,
    expected,
    actual,
    CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY check_name;