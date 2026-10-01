-- Phase 8: reusable, read-only reporting views for Central Superstore.
-- Run with psql while connected to central_superstore_dw.
-- CREATE OR REPLACE makes this script safe to run repeatedly.
-- The views summarize stored data only; they do not insert, update, or delete rows.

-- View 1: one row per FactSales line, joined to all descriptive dimensions.
-- Grain: one source order line (one FactSales row).
-- Audience: analysts who need a readable, joined reporting surface.
CREATE OR REPLACE VIEW warehouse.vw_sales_detail AS
SELECT
    f."SalesKey" AS sales_key,
    f."SourceRowID" AS source_row_id,
    f."OrderID" AS order_id,
    order_date."FullDate" AS order_date,
    ship_date."FullDate" AS ship_date,
    f."ShipMode" AS ship_mode,
    c."CustomerKey" AS customer_key,
    c."CustomerID" AS customer_id,
    c."CustomerName" AS customer_name,
    c."Segment" AS customer_segment,
    p."ProductKey" AS product_key,
    p."ProductID" AS product_id,
    p."ProductName" AS product_name,
    p."Category" AS product_category,
    p."SubCategory" AS product_subcategory,
    l."LocationKey" AS location_key,
    l."Country" AS country,
    l."Region" AS region,
    l."State" AS state,
    l."City" AS city,
    l."PostalCode" AS postal_code,
    f."Sales" AS sales,
    f."Profit" AS profit,
    f."Quantity" AS quantity,
    f."Discount" AS discount,
    order_date."Year" AS order_year,
    order_date."Quarter" AS order_quarter,
    order_date."Month" AS order_month,
    order_date."MonthName" AS order_month_name,
    order_date."IsWeekend" AS order_is_weekend
FROM warehouse."FactSales" AS f
JOIN warehouse."DimDate" AS order_date
  ON order_date."DateKey" = f."OrderDateKey"
JOIN warehouse."DimDate" AS ship_date
  ON ship_date."DateKey" = f."ShipDateKey"
JOIN warehouse."DimCustomer" AS c
  ON c."CustomerKey" = f."CustomerKey"
JOIN warehouse."DimProduct" AS p
  ON p."ProductKey" = f."ProductKey"
JOIN warehouse."DimLocation" AS l
  ON l."LocationKey" = f."LocationKey";

-- View 2: totals and descriptive order attributes after aggregating all product lines.
-- Grain: one row per distinct OrderID.
-- Audience: sales operations staff measuring order value, volume, and shipping delay.
CREATE OR REPLACE VIEW warehouse.vw_order_summary AS
SELECT
    d.order_id,
    MIN(d.order_date) AS order_date,
    MIN(d.ship_date) AS ship_date,
    MIN(d.ship_date) - MIN(d.order_date) AS shipping_delay_days,
    MIN(d.customer_key) AS customer_key,
    MIN(d.customer_id) AS customer_id,
    MIN(d.customer_name) AS customer_name,
    MIN(d.customer_segment) AS customer_segment,
    MIN(d.ship_mode) AS ship_mode,
    MIN(d.region) AS region,
    MIN(d.state) AS state,
    SUM(d.sales) AS total_sales,
    SUM(d.profit) AS total_profit,
    SUM(d.quantity) AS total_quantity,
    COUNT(*) AS number_of_lines
FROM warehouse.vw_sales_detail AS d
GROUP BY d.order_id;

-- View 3: executive monthly KPIs. Orders are totaled first, then averaged equally.
-- Grain: one row per order calendar year and month.
-- Audience: executives reviewing sales trends and average order value over time.
CREATE OR REPLACE VIEW warehouse.vw_monthly_kpis AS
SELECT
    order_date."Year" AS order_year,
    order_date."Month" AS order_month,
    order_date."MonthName" AS month_name,
    SUM(order_totals.total_sales) AS total_sales,
    SUM(order_totals.total_profit) AS total_profit,
    ROUND(100.0 * SUM(order_totals.total_profit) / NULLIF(SUM(order_totals.total_sales), 0), 2) AS profit_margin_percent,
    SUM(order_totals.total_quantity) AS total_quantity,
    COUNT(*) AS number_of_orders,
    ROUND(AVG(order_totals.total_sales), 2) AS average_order_value
FROM warehouse.vw_order_summary AS order_totals
JOIN warehouse."DimDate" AS order_date
  ON order_date."FullDate" = order_totals.order_date
GROUP BY order_date."Year", order_date."Month", order_date."MonthName";

-- View 4: customer-level lifetime value and order frequency.
-- Grain: one row per active CustomerKey.
-- Audience: customer relationship teams planning retention and value-based outreach.
CREATE OR REPLACE VIEW warehouse.vw_customer_kpis AS
SELECT
    c."CustomerKey" AS customer_key,
    c."CustomerID" AS customer_id,
    c."CustomerName" AS customer_name,
    c."Segment" AS customer_segment,
    SUM(o.total_sales) AS total_sales,
    SUM(o.total_profit) AS total_profit,
    COUNT(*) AS number_of_orders,
    ROUND(AVG(o.total_sales), 2) AS average_order_value,
    MIN(o.order_date) AS first_order_date,
    MAX(o.order_date) AS last_order_date,
    CASE
        WHEN SUM(o.total_sales) >= 5000 THEN 'High (>= 5000)'
        WHEN SUM(o.total_sales) >= 1000 THEN 'Medium (1000-4999.99)'
        ELSE 'Low (< 1000)'
    END AS customer_value_tier
FROM warehouse.vw_order_summary AS o
JOIN warehouse."DimCustomer" AS c
  ON c."CustomerKey" = o.customer_key
GROUP BY c."CustomerKey", c."CustomerID", c."CustomerName", c."Segment";

-- View 5: performance for each product dimension member, not each ProductID.
-- Grain: one row per ProductKey; conflicting names for one ProductID stay separate.
-- Audience: merchandising teams comparing product-member sales, margin, and losses.
CREATE OR REPLACE VIEW warehouse.vw_product_performance AS
SELECT
    p."ProductKey" AS product_key,
    p."ProductID" AS product_id,
    p."ProductName" AS product_name,
    p."Category" AS product_category,
    p."SubCategory" AS product_subcategory,
    SUM(d.sales) AS total_sales,
    SUM(d.profit) AS total_profit,
    ROUND(100.0 * SUM(d.profit) / NULLIF(SUM(d.sales), 0), 2) AS profit_margin_percent,
    SUM(d.quantity) AS total_quantity,
    COUNT(*) AS number_of_lines,
    COUNT(*) FILTER (WHERE d.profit < 0) AS negative_profit_lines,
    SUM(d.profit) < 0 AS is_loss_making
FROM warehouse.vw_sales_detail AS d
JOIN warehouse."DimProduct" AS p
  ON p."ProductKey" = d.product_key
GROUP BY p."ProductKey", p."ProductID", p."ProductName", p."Category", p."SubCategory";

-- View 6: profitability by sales region, state, and product category.
-- Grain: one row per Region + State + Category combination.
-- Audience: regional and category managers locating the source of losses.
CREATE OR REPLACE VIEW warehouse.vw_category_region_profitability AS
SELECT
    d.region,
    d.state,
    d.product_category,
    SUM(d.sales) AS total_sales,
    SUM(d.profit) AS total_profit,
    ROUND(100.0 * SUM(d.profit) / NULLIF(SUM(d.sales), 0), 2) AS profit_margin_percent,
    COUNT(*) AS number_of_lines,
    COUNT(*) FILTER (WHERE d.profit < 0) AS negative_profit_lines,
    ROUND(100.0 * COUNT(*) FILTER (WHERE d.profit < 0) / NULLIF(COUNT(*), 0), 2) AS negative_profit_line_share_percent
FROM warehouse.vw_sales_detail AS d
GROUP BY d.region, d.state, d.product_category;
