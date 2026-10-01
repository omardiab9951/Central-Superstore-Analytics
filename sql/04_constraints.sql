-- Phase 3, step 4: add business-key uniqueness, referential integrity, and checks.
-- Run this file with psql after 03_create_fact.sql.
-- Existing named constraints are dropped first so this file is safe to rerun.

\set ON_ERROR_STOP on
\if :{?warehouse_db}
\else
\set warehouse_db central_superstore_dw
\endif
\connect :warehouse_db

-- Dimension natural keys prevent duplicate descriptive members.
ALTER TABLE warehouse."DimCustomer"
    DROP CONSTRAINT IF EXISTS "UQ_DimCustomer_CustomerID";
ALTER TABLE warehouse."DimCustomer"
    ADD CONSTRAINT "UQ_DimCustomer_CustomerID" UNIQUE ("CustomerID");

ALTER TABLE warehouse."DimProduct"
    DROP CONSTRAINT IF EXISTS "UQ_DimProduct_ProductID_ProductName";
ALTER TABLE warehouse."DimProduct"
    ADD CONSTRAINT "UQ_DimProduct_ProductID_ProductName"
    UNIQUE ("ProductID", "ProductName");

ALTER TABLE warehouse."DimDate"
    DROP CONSTRAINT IF EXISTS "UQ_DimDate_FullDate";
ALTER TABLE warehouse."DimDate"
    ADD CONSTRAINT "UQ_DimDate_FullDate" UNIQUE ("FullDate");

ALTER TABLE warehouse."DimLocation"
    DROP CONSTRAINT IF EXISTS "UQ_DimLocation_Geography";
ALTER TABLE warehouse."DimLocation"
    ADD CONSTRAINT "UQ_DimLocation_Geography"
    UNIQUE ("Country", "State", "City", "PostalCode");

-- SourceRowID uniquely identifies the original input row for lineage.
ALTER TABLE warehouse."FactSales"
    DROP CONSTRAINT IF EXISTS "UQ_FactSales_SourceRowID";
ALTER TABLE warehouse."FactSales"
    ADD CONSTRAINT "UQ_FactSales_SourceRowID" UNIQUE ("SourceRowID");

-- Phase 2 verified each (Order ID, Product ID) pair is unique in this source.
-- ProductKey represents the exact ProductID + ProductName member.
ALTER TABLE warehouse."FactSales"
    DROP CONSTRAINT IF EXISTS "UQ_FactSales_OrderID_ProductKey";
ALTER TABLE warehouse."FactSales"
    ADD CONSTRAINT "UQ_FactSales_OrderID_ProductKey"
    UNIQUE ("OrderID", "ProductKey");

-- Each fact row must point to one valid customer, product, location, and date.
ALTER TABLE warehouse."FactSales"
    DROP CONSTRAINT IF EXISTS "FK_FactSales_Customer";
ALTER TABLE warehouse."FactSales"
    ADD CONSTRAINT "FK_FactSales_Customer"
    FOREIGN KEY ("CustomerKey")
    REFERENCES warehouse."DimCustomer" ("CustomerKey");

ALTER TABLE warehouse."FactSales"
    DROP CONSTRAINT IF EXISTS "FK_FactSales_Product";
ALTER TABLE warehouse."FactSales"
    ADD CONSTRAINT "FK_FactSales_Product"
    FOREIGN KEY ("ProductKey")
    REFERENCES warehouse."DimProduct" ("ProductKey");

ALTER TABLE warehouse."FactSales"
    DROP CONSTRAINT IF EXISTS "FK_FactSales_OrderDate";
ALTER TABLE warehouse."FactSales"
    ADD CONSTRAINT "FK_FactSales_OrderDate"
    FOREIGN KEY ("OrderDateKey")
    REFERENCES warehouse."DimDate" ("DateKey");

ALTER TABLE warehouse."FactSales"
    DROP CONSTRAINT IF EXISTS "FK_FactSales_ShipDate";
ALTER TABLE warehouse."FactSales"
    ADD CONSTRAINT "FK_FactSales_ShipDate"
    FOREIGN KEY ("ShipDateKey")
    REFERENCES warehouse."DimDate" ("DateKey");

ALTER TABLE warehouse."FactSales"
    DROP CONSTRAINT IF EXISTS "FK_FactSales_Location";
ALTER TABLE warehouse."FactSales"
    ADD CONSTRAINT "FK_FactSales_Location"
    FOREIGN KEY ("LocationKey")
    REFERENCES warehouse."DimLocation" ("LocationKey");

-- These checks reject invalid transactional values when data is loaded later.
ALTER TABLE warehouse."FactSales"
    DROP CONSTRAINT IF EXISTS "CK_FactSales_Quantity_Positive";
ALTER TABLE warehouse."FactSales"
    ADD CONSTRAINT "CK_FactSales_Quantity_Positive"
    CHECK ("Quantity" > 0);

ALTER TABLE warehouse."FactSales"
    DROP CONSTRAINT IF EXISTS "CK_FactSales_Sales_Nonnegative";
ALTER TABLE warehouse."FactSales"
    ADD CONSTRAINT "CK_FactSales_Sales_Nonnegative"
    CHECK ("Sales" >= 0);

ALTER TABLE warehouse."FactSales"
    DROP CONSTRAINT IF EXISTS "CK_FactSales_Discount_Range";
ALTER TABLE warehouse."FactSales"
    ADD CONSTRAINT "CK_FactSales_Discount_Range"
    CHECK ("Discount" >= 0 AND "Discount" <= 1);

-- Profit intentionally has no nonnegative check because valid source losses exist.