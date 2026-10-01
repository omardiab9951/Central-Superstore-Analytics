-- Phase 10: justified supporting indexes for common warehouse joins/filters.
-- Run with psql while connected to central_superstore_dw.
-- CREATE INDEX IF NOT EXISTS makes this script safe to run repeatedly.
-- PostgreSQL already has PK/unique indexes on all dimension surrogate keys and
-- the documented natural keys. This file does not recreate those indexes.
-- On a 2,323-row table PostgreSQL may still choose sequential scans; indexes
-- add value mainly as the fact table grows or when a filter is selective.

-- Supports filtering facts by the order-date role and joins from order-date reports.
CREATE INDEX IF NOT EXISTS ix_factsales_orderdatekey
    ON warehouse."FactSales" ("OrderDateKey");

-- Supports shipping-date filtering and the second role-playing DimDate join.
CREATE INDEX IF NOT EXISTS ix_factsales_shipdatekey
    ON warehouse."FactSales" ("ShipDateKey");

-- Supports customer-level fact lookups and joins used by customer KPI reports.
CREATE INDEX IF NOT EXISTS ix_factsales_customerkey
    ON warehouse."FactSales" ("CustomerKey");

-- Supports product-member joins used by product/category performance reports.
CREATE INDEX IF NOT EXISTS ix_factsales_productkey
    ON warehouse."FactSales" ("ProductKey");

-- Supports location-filtered and location-grouped fact joins.
CREATE INDEX IF NOT EXISTS ix_factsales_locationkey
    ON warehouse."FactSales" ("LocationKey");
