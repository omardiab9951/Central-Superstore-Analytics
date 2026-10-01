-- Phase 9: reusable KPI procedure and period function for the warehouse.
-- Run with psql while connected to central_superstore_dw.
-- This file creates routines only; it does not change table data or schema.

-- Procedure: calculate one set of KPIs for an inclusive Order Date range.
-- A NULL start or end date means that side of the date range is open.
-- NULL category/region values mean that the corresponding filter is not applied.
CREATE OR REPLACE PROCEDURE warehouse.sp_calculate_kpis(
    IN p_start_date DATE, -- Inclusive earliest Order Date; NULL leaves the lower bound open.
    IN p_end_date DATE, -- Inclusive latest Order Date; NULL leaves the upper bound open.
    IN p_category TEXT, -- Exact product category; NULL includes every category.
    IN p_region TEXT, -- Exact sales region; NULL includes every region.
    OUT out_total_sales NUMERIC, -- Sum of Sales across the matching fact lines.
    OUT out_total_profit NUMERIC, -- Sum of Profit across matching lines, including losses.
    OUT out_profit_margin_percent NUMERIC, -- Total profit divided by total sales, as a percent.
    OUT out_total_quantity BIGINT, -- Sum of whole-unit quantities.
    OUT out_number_of_orders BIGINT, -- Count of distinct OrderID values.
    OUT out_number_of_customers BIGINT, -- Count of distinct customers in matching orders.
    OUT out_average_order_value NUMERIC, -- Filtered Sales divided by distinct order count.
    OUT out_loss_making_lines BIGINT -- Count of individual fact lines whose Profit is negative.
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Error check: reject a reversed, fully specified date range rather than returning misleading results.
    IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_start_date > p_end_date THEN
        RAISE EXCEPTION 'Start date (%) must be on or before end date (%)', p_start_date, p_end_date
            USING ERRCODE = '22007';
    END IF;

    -- Logic block: first aggregate the matching line rows to one row per order.
    -- This ensures order count, customer count, and average order value use the right grain.
    WITH filtered_lines AS (
        SELECT d.order_id, d.customer_id, d.sales, d.profit, d.quantity
        FROM warehouse.vw_sales_detail AS d
        WHERE (p_start_date IS NULL OR d.order_date >= p_start_date)
          AND (p_end_date IS NULL OR d.order_date <= p_end_date)
          AND (p_category IS NULL OR d.product_category = p_category)
          AND (p_region IS NULL OR d.region = p_region)
    ),
    order_totals AS (
        SELECT order_id,
               MIN(customer_id) AS customer_id,
               SUM(sales) AS order_sales,
               SUM(profit) AS order_profit,
               SUM(quantity) AS order_quantity
        FROM filtered_lines
        GROUP BY order_id
    )
    SELECT COALESCE(SUM(o.order_sales), 0),
           COALESCE(SUM(o.order_profit), 0),
           ROUND(100.0 * SUM(o.order_profit) / NULLIF(SUM(o.order_sales), 0), 2),
           COALESCE(SUM(o.order_quantity), 0)::BIGINT,
           COUNT(*)::BIGINT,
           COUNT(DISTINCT o.customer_id)::BIGINT,
           ROUND(SUM(o.order_sales) / NULLIF(COUNT(*), 0), 2),
           (SELECT COUNT(*)::BIGINT
            FROM filtered_lines AS loss_line
            WHERE loss_line.profit < 0)
    INTO out_total_sales,
         out_total_profit,
         out_profit_margin_percent,
         out_total_quantity,
         out_number_of_orders,
         out_number_of_customers,
         out_average_order_value,
         out_loss_making_lines
    FROM order_totals AS o;

    -- Empty-result check: zero sums/counts and NULL ratios/AOV are returned, with a NOTICE explaining why.
    IF out_number_of_orders = 0 THEN
        RAISE NOTICE 'No orders matched the supplied dates/category/region; sums and counts are zero and margin/AOV are NULL.';
        out_profit_margin_percent := NULL;
        out_average_order_value := NULL;
    END IF;
END;
$$;

COMMENT ON PROCEDURE warehouse.sp_calculate_kpis(DATE, DATE, TEXT, TEXT)
IS 'Returns sales, profit, margin, quantity, distinct orders/customers, order-level AOV, and loss-line count for optional Order Date/category/region filters.';

-- Function: return KPI rows at year, quarter, or month grain.
-- Date and category/region filtering follows the same rules as the procedure.
CREATE OR REPLACE FUNCTION warehouse.fn_kpi_by_period(
    p_start_date DATE, -- Inclusive earliest Order Date; NULL leaves the lower bound open.
    p_end_date DATE, -- Inclusive latest Order Date; NULL leaves the upper bound open.
    p_period TEXT, -- Required output grain: year, quarter, or month.
    p_category TEXT DEFAULT NULL, -- Exact product category; default NULL means no category filter.
    p_region TEXT DEFAULT NULL -- Exact region; default NULL means no region filter.
)
RETURNS TABLE (
    period_start DATE,
    period_year INTEGER,
    period_quarter INTEGER,
    period_month INTEGER,
    total_sales NUMERIC,
    total_profit NUMERIC,
    profit_margin_percent NUMERIC,
    total_quantity NUMERIC,
    number_of_orders BIGINT,
    number_of_customers BIGINT,
    average_order_value NUMERIC,
    loss_making_lines BIGINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Error check: reject reversed date bounds so callers receive a clear input error.
    IF p_start_date IS NOT NULL AND p_end_date IS NOT NULL AND p_start_date > p_end_date THEN
        RAISE EXCEPTION 'Start date (%) must be on or before end date (%)', p_start_date, p_end_date
            USING ERRCODE = '22007';
    END IF;

    -- Error check: accept only the three documented period labels; normalize case and outer spaces.
    IF p_period IS NULL OR lower(btrim(p_period)) NOT IN ('year', 'quarter', 'month') THEN
        RAISE EXCEPTION 'Period must be one of year, quarter, or month; received %', p_period
            USING ERRCODE = '22023';
    END IF;

    -- Empty-result check: return no period rows and emit a NOTICE, distinguishing no data from failure.
    IF NOT EXISTS (
        SELECT 1
        FROM warehouse.vw_sales_detail AS d
        WHERE (p_start_date IS NULL OR d.order_date >= p_start_date)
          AND (p_end_date IS NULL OR d.order_date <= p_end_date)
          AND (p_category IS NULL OR d.product_category = p_category)
          AND (p_region IS NULL OR d.region = p_region)
    ) THEN
        RAISE NOTICE 'No rows matched the supplied dates/category/region; the function returns zero rows.';
        RETURN;
    END IF;

    -- Main logic block: filter lines, aggregate each order, then aggregate to the requested period.
    -- This preserves order-level AOV even when an order contains multiple product lines.
    RETURN QUERY
    WITH filtered_lines AS (
        SELECT d.order_id, d.customer_id, d.order_date, d.sales, d.profit, d.quantity
        FROM warehouse.vw_sales_detail AS d
        WHERE (p_start_date IS NULL OR d.order_date >= p_start_date)
          AND (p_end_date IS NULL OR d.order_date <= p_end_date)
          AND (p_category IS NULL OR d.product_category = p_category)
          AND (p_region IS NULL OR d.region = p_region)
    ),
    order_totals AS (
        SELECT order_id,
               MIN(customer_id) AS customer_id,
               MIN(order_date) AS order_date,
               SUM(sales) AS order_sales,
               SUM(profit) AS order_profit,
               SUM(quantity) AS order_quantity,
               COUNT(*) FILTER (WHERE profit < 0)::BIGINT AS order_loss_lines
        FROM filtered_lines
        GROUP BY order_id
    ),
    order_periods AS (
        SELECT order_totals.*,
               CASE lower(btrim(p_period))
                   WHEN 'year' THEN date_trunc('year', order_date)::DATE
                   WHEN 'quarter' THEN date_trunc('quarter', order_date)::DATE
                   ELSE date_trunc('month', order_date)::DATE
               END AS bucket_start
        FROM order_totals
    )
    SELECT bucket_start,
           EXTRACT(YEAR FROM bucket_start)::INTEGER,
           CASE WHEN lower(btrim(p_period)) IN ('quarter', 'month')
                THEN EXTRACT(QUARTER FROM bucket_start)::INTEGER END,
           CASE WHEN lower(btrim(p_period)) = 'month'
                THEN EXTRACT(MONTH FROM bucket_start)::INTEGER END,
           SUM(order_sales),
           SUM(order_profit),
           ROUND(100.0 * SUM(order_profit) / NULLIF(SUM(order_sales), 0), 2),
           SUM(order_quantity),
           COUNT(*)::BIGINT,
           COUNT(DISTINCT customer_id)::BIGINT,
           ROUND(AVG(order_sales), 2),
           SUM(order_loss_lines)::BIGINT
    FROM order_periods
    GROUP BY bucket_start
    ORDER BY bucket_start;
END;
$$;

COMMENT ON FUNCTION warehouse.fn_kpi_by_period(DATE, DATE, TEXT, TEXT, TEXT)
IS 'Returns year-, quarter-, or month-grain KPIs with optional Order Date/category/region filters and order-level AOV.';