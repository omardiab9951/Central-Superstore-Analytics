# Mini-Project 2 — Advanced SQL Data Warehouse & Business Analytics

## 1. Project Overview

Build a complete relational analytical database and business analytics solution from the provided Excel dataset:

- **Input file:** `Central_Superstore.xlsx`
- **Sheet:** `Central_Region`
- **Rows:** 2,323 data rows
- **Columns:** 21
- **Business domain:** Retail sales
- **Region:** Central
- **Target:** SQL Server / MySQL / PostgreSQL

The project must transform the flat Excel dataset into a normalized relational database using a **star schema**, then use advanced SQL to produce business KPIs and analytical reports.

### Academic Requirements

The final project must contain at least:

- 5 relational tables
- Primary and foreign key relationships
- A star schema
- 15 SQL queries
- 3+ JOIN operations
- 2+ CTEs
- 1+ subquery
- 1+ CASE statement/query
- 1 SQL View
- 1 Stored Procedure
- Query optimization/performance work
- Analytical reporting covering:
  - Profitability
  - Customer behavior
  - Sales trends

---

# 2. Dataset Information

The Excel file contains these 21 columns:

1. `Row ID`
2. `Order ID`
3. `Order Date`
4. `Ship Date`
5. `Ship Mode`
6. `Customer ID`
7. `Customer Name`
8. `Segment`
9. `Country`
10. `City`
11. `State`
12. `Postal Code`
13. `Region`
14. `Product ID`
15. `Category`
16. `Sub-Category`
17. `Product Name`
18. `Sales`
19. `Quantity`
20. `Discount`
21. `Profit`

Known dataset characteristics:

- 2,323 data rows
- 629 unique customers
- 1,310 unique products
- 1,175 unique orders
- 13 states
- 181 cities
- 4 shipping modes
- 3 customer segments
- 3 product categories
- 17 sub-categories
- `Region` is always `Central`
- Dataset currently has no known missing values

**Important:** Do not invent data that is not present in the Excel file.

---

# 3. Recommended Technology

Use **PostgreSQL** as the default database unless the user explicitly chooses SQL Server or MySQL.

Recommended project tools:

- PostgreSQL
- SQL
- Python for Excel/ETL support if needed
- pandas/openpyxl for reading the Excel file if needed
- Git/GitHub for version control
- VS Code / Codex / GitHub Copilot as the coding environment

If another database engine is selected, adapt syntax appropriately.

---

# 4. Target Star Schema

The initial recommended design is:

```text
                 DimCustomer
                      |
                      |
DimProduct ---- FactSales ---- DimDate
                      |
                      |
                DimLocation
```

Recommended minimum tables:

### DimCustomer

- `CustomerKey` — surrogate primary key
- `CustomerID` — business/natural key
- `CustomerName`
- `Segment`

### DimProduct

- `ProductKey` — surrogate primary key
- `ProductID` — business/natural key
- `ProductName`
- `Category`
- `SubCategory`

### DimDate

- `DateKey` — primary key
- `FullDate`
- `Year`
- `Quarter`
- `Month`
- `MonthName`
- `Day`
- optionally `DayOfWeek`

### DimLocation

- `LocationKey` — surrogate primary key
- `Country`
- `City`
- `State`
- `PostalCode`
- `Region`

### FactSales

- `SalesKey` — surrogate primary key
- `OrderID`
- `OrderDateKey` — foreign key to DimDate
- `ShipDateKey` — foreign key to DimDate
- `CustomerKey` — foreign key to DimCustomer
- `ProductKey` — foreign key to DimProduct
- `LocationKey` — foreign key to DimLocation
- `ShipMode`
- `Sales`
- `Quantity`
- `Discount`
- `Profit`

The agent must validate this design against the actual dataset before implementation and may make justified changes.

---

# PHASE 1 — Project Setup and Dataset Profiling

## Objective

Understand the input data before creating the database.

## Tasks

1. Confirm the Excel file exists.
2. Read the `Central_Region` sheet.
3. Verify:
   - row count
   - column count
   - column names
   - data types
   - missing values
   - duplicate rows
   - duplicate IDs
   - unique counts
   - date ranges
   - numeric ranges
4. Check relationships between:
   - Order ID
   - Customer ID
   - Product ID
   - Order Date
   - Ship Date
5. Identify data-quality issues.
6. Do not modify the original Excel file.

## Deliverables

Create:

```text
docs/
  dataset_profile.md
```

The report must document:

- Dataset dimensions
- Column descriptions
- Data types
- Missing-value results
- Duplicate results
- Unique-value counts
- Data-quality observations
- Date range
- Important assumptions

## Validation

The profile should confirm that the source dataset contains 2,323 data rows and 21 columns.

## Gate

Do not proceed until the dataset profile is complete.

---

# PHASE 2 — Star Schema Design

## Objective

Design the analytical relational model before writing the database implementation.

## Tasks

1. Determine the grain of `FactSales`.

The preferred grain is:

> One row in FactSales represents one product line within an order.

2. Identify dimensions.
3. Identify measures.
4. Identify natural/business keys.
5. Identify surrogate keys.
6. Define primary keys.
7. Define foreign keys.
8. Define relationships.
9. Check normalization of dimensions.
10. Produce an ERD/star-schema diagram.

## Deliverables

Create:

```text
docs/
  star_schema.md
  data_dictionary.md
  star_schema.png
```

The documentation must explain:

- Fact table
- Dimension tables
- Grain
- Measures
- Dimensions
- PKs
- FKs
- Relationships
- Design assumptions

## Gate

Do not create production tables until the schema is documented and internally consistent.

---

# PHASE 3 — Database Creation

## Objective

Create the relational database structure.

## Tasks

1. Create database/schema.
2. Create dimension tables.
3. Create fact table.
4. Define appropriate data types.
5. Define primary keys.
6. Define foreign keys.
7. Add appropriate `NOT NULL` constraints.
8. Add reasonable uniqueness constraints.
9. Add basic check constraints where appropriate.
10. Ensure referential integrity.

## Deliverables

Create:

```text
sql/
  01_create_database.sql
  02_create_dimensions.sql
  03_create_fact.sql
  04_constraints.sql
```

## Validation

Verify:

- All required tables exist.
- PKs exist.
- FKs exist.
- Data types are appropriate.
- No circular dependencies exist.
- Fact table correctly references dimensions.

---

# PHASE 4 — ETL / Data Loading

## Objective

Move the Excel data into the star schema.

## Tasks

1. Read the Excel file.
2. Clean/standardize column names.
3. Convert dates to proper date types.
4. Clean numeric values.
5. Build dimension datasets.
6. Generate surrogate keys.
7. Build the date dimension.
8. Load dimensions first.
9. Load the fact table after dimensions.
10. Map business keys to surrogate keys.
11. Preserve all valid source records.
12. Log rejected or invalid records if any exist.

Recommended loading order:

```text
DimDate
DimCustomer
DimProduct
DimLocation
      ↓
FactSales
```

## Deliverables

Create appropriate ETL scripts, for example:

```text
etl/
  load_dimensions.py
  load_fact.py
```

and/or:

```text
sql/
  05_load_dimensions.sql
  06_load_fact.sql
```

## Validation

Compare source and database results:

- Source row count
- Fact row count
- Unique customer count
- Unique product count
- Unique order count
- Total Sales
- Total Quantity
- Total Profit

The totals should reconcile with the source data within any explicitly documented transformation differences.

---

# PHASE 5 — Data Validation and Relationship Testing

## Objective

Prove that the warehouse is correctly populated.

## Tasks

Create validation queries for:

1. Orphan customer keys
2. Orphan product keys
3. Orphan date keys
4. Orphan location keys
5. Duplicate dimension business keys
6. Null foreign keys
7. Fact row count
8. Sales total
9. Quantity total
10. Profit total
11. Order count
12. Customer count
13. Product count

## Deliverables

```text
sql/
  07_data_validation.sql
```

```text
docs/
  validation_report.md
```

## Gate

Do not continue if referential integrity or major source-to-database totals do not reconcile.

---

# PHASE 6 — Core Business SQL Queries

## Objective

Create at least 15 meaningful analytical SQL queries.

Do not create artificial queries just to satisfy the number requirement.

## Required query categories

### General KPIs

1. Total Sales
2. Total Profit
3. Total Quantity
4. Total Orders
5. Average Order Value
6. Profit Margin

### Product Analysis

7. Sales by Category
8. Profit by Category
9. Top Products by Sales
10. Top Products by Profit
11. Products with Negative Profit

### Customer Analysis

12. Top Customers by Sales
13. Sales by Customer Segment
14. Customer Order Frequency

### Location Analysis

15. Sales by State
16. Profit by State

### Time Analysis

17. Sales by Year
18. Sales by Month
19. Profit by Month

The project may contain more than 15 queries.

## SQL techniques

Across the query set, demonstrate:

- SELECT
- WHERE
- GROUP BY
- HAVING
- ORDER BY
- Aggregate functions
- JOINs
- CASE
- Subqueries
- CTEs
- Window functions where appropriate

## Deliverables

```text
sql/
  08_business_queries.sql
```

Each query must have a short comment explaining its business purpose.

---

# PHASE 7 — Advanced SQL Requirements

## Objective

Explicitly demonstrate the advanced SQL techniques required by the assignment.

## 7.1 JOINs

Use at least 3 meaningful JOIN operations.

Examples:

- FactSales + DimCustomer
- FactSales + DimProduct
- FactSales + DimDate
- FactSales + DimLocation

## 7.2 CTEs

Create at least 2 meaningful CTE queries.

Example ideas:

- Monthly sales followed by month-over-month comparison
- Customer totals followed by customer ranking
- Product profitability analysis

## 7.3 Subqueries

Create at least 1 meaningful subquery.

Example:

> Find products whose sales are greater than the average product sales.

## 7.4 CASE

Create at least 1 meaningful CASE query.

Example:

```text
High Value
Medium Value
Low Value
```

based on customer sales.

## 7.5 Window Functions

Use where useful, for example:

- `RANK()`
- `DENSE_RANK()`
- `ROW_NUMBER()`
- `LAG()`
- `SUM() OVER()`

Do not use window functions merely for decoration.

## Deliverables

```text
sql/
  09_advanced_sql.sql
```

---

# PHASE 8 — SQL View

## Objective

Create a reusable KPI view for executive reporting.

## Requirements

Create at least one view containing useful business metrics.

Possible metrics:

- Total Sales
- Total Profit
- Total Quantity
- Total Orders
- Average Order Value
- Profit Margin

Example concept:

```text
vw_Executive_KPIs
```

## Deliverables

```text
sql/
  10_views.sql
```

Also document the purpose of the view.

---

# PHASE 9 — Stored Procedure

## Objective

Create at least one reusable stored procedure.

Possible procedure:

```text
sp_GetSalesByDateRange
```

Parameters could include:

- Start date
- End date

The procedure should return useful sales/profit KPIs.

Alternative:

```text
sp_GetCustomerSales
```

with a customer ID parameter.

## Requirements

The procedure must:

- Accept parameters
- Perform meaningful analytical work
- Return useful results
- Be tested with multiple inputs

## Deliverables

```text
sql/
  11_stored_procedures.sql
```

```text
docs/
  stored_procedure.md
```

---

# PHASE 10 — Performance Optimization

## Objective

Demonstrate basic SQL performance optimization.

## Tasks

1. Identify potentially expensive queries.
2. Inspect execution plans where supported.
3. Identify useful indexes.
4. Add indexes to important foreign keys and frequently filtered/grouped columns where justified.
5. Avoid unnecessary indexes.
6. Compare query plans/performance before and after optimization where possible.
7. Document the reasoning for each index.

Possible indexes:

- FactSales(CustomerKey)
- FactSales(ProductKey)
- FactSales(OrderDateKey)
- FactSales(LocationKey)
- DimCustomer(CustomerID)
- DimProduct(ProductID)

Do not blindly create indexes on every column.

## Deliverables

```text
sql/
  12_indexes.sql
```

```text
docs/
  performance_optimization.md
```

---

# PHASE 11 — Business Analytics / KPI Report

## Objective

Turn the SQL results into a clear business report.

The report must cover three major areas.

## A. Profitability

Answer questions such as:

- What is total sales?
- What is total profit?
- What is profit margin?
- Which categories are most/least profitable?
- Which products have negative profit?
- Which states generate the most profit?

## B. Customer Behavior

Answer:

- Who are the top customers?
- Which customer segments generate the most sales?
- How frequently do customers order?
- Which customers generate the most profit?

## C. Sales Trends

Answer:

- How do sales change over time?
- Which months have the highest sales?
- Which years have the highest sales?
- How does profit change over time?

## Deliverables

Create:

```text
reports/
  business_analytics_report.md
```

Optionally create charts/dashboard outputs using Python, Excel, Power BI, or another suitable tool.

Every reported KPI should be traceable to a SQL query.

---

# PHASE 12 — Final Documentation

## Objective

Prepare the project so another person can understand and reproduce it.

## Documentation should contain

1. Project title
2. Business scenario
3. Dataset description
4. Data-quality analysis
5. Star schema explanation
6. ERD/schema diagram
7. Table descriptions
8. PK/FK relationships
9. ETL process
10. SQL query analysis
11. CTE examples
12. Subquery example
13. CASE example
14. View explanation
15. Stored procedure explanation
16. Index/performance optimization
17. Business findings
18. Limitations
19. How to run the project

## Deliverables

```text
README.md
docs/
  final_report.md
```

---

# PHASE 13 — Final Quality Assurance

Before declaring the project complete, verify every academic requirement.

## Checklist

- [ ] Excel source analyzed
- [ ] At least 5 relational tables
- [ ] Star schema implemented
- [ ] Primary keys implemented
- [ ] Foreign keys implemented
- [ ] Referential integrity verified
- [ ] Data loaded successfully
- [ ] Source/database totals reconciled
- [ ] At least 15 SQL queries
- [ ] At least 3 JOIN operations
- [ ] At least 2 CTEs
- [ ] At least 1 subquery
- [ ] At least 1 CASE statement
- [ ] At least 1 SQL View
- [ ] At least 1 Stored Procedure
- [ ] Query optimization demonstrated
- [ ] Profitability analysis completed
- [ ] Customer behavior analysis completed
- [ ] Sales trend analysis completed
- [ ] KPI report completed
- [ ] Documentation completed
- [ ] All SQL scripts tested
- [ ] Project can be reproduced from the documented steps

---

# 5. Recommended Project Structure

The final repository should approximately look like:

```text
Mini-Project-2/
│
├── data/
│   └── Central_Superstore.xlsx
│
├── sql/
│   ├── 01_create_database.sql
│   ├── 02_create_dimensions.sql
│   ├── 03_create_fact.sql
│   ├── 04_constraints.sql
│   ├── 05_load_dimensions.sql
│   ├── 06_load_fact.sql
│   ├── 07_data_validation.sql
│   ├── 08_business_queries.sql
│   ├── 09_advanced_sql.sql
│   ├── 10_views.sql
│   ├── 11_stored_procedures.sql
│   └── 12_indexes.sql
│
├── etl/
│   ├── load_dimensions.py
│   └── load_fact.py
│
├── docs/
│   ├── dataset_profile.md
│   ├── star_schema.md
│   ├── data_dictionary.md
│   ├── validation_report.md
│   ├── stored_procedure.md
│   └── performance_optimization.md
│
├── reports/
│   └── business_analytics_report.md
│
├── README.md
└── plan.md
```

The agent may adjust this structure if there is a good technical reason, but it must preserve clear separation between source data, SQL, ETL, documentation, and reports.

---

# 6. Agent Operating Rules

The coding agent must follow these rules:

### Rule 1 — Work phase by phase

Do not attempt to implement the entire project blindly in one step.

Complete one phase, validate it, then move to the next phase.

### Rule 2 — Inspect before modifying

Always inspect existing files and database state before creating or changing files.

### Rule 3 — Do not invent data

Use only the supplied dataset.

### Rule 4 — Preserve the original dataset

Never modify or overwrite:

```text
Central_Superstore.xlsx
```

### Rule 5 — Explain important decisions

When making a schema or architecture decision, document the reason.

### Rule 6 — Test everything

SQL scripts must be tested where the required database environment is available.

### Rule 7 — Keep scripts reproducible

A new user should be able to follow `README.md` and reproduce the database.

### Rule 8 — Do not hide errors

If something fails, diagnose and fix it rather than silently working around it.

### Rule 9 — Maintain academic traceability

Every assignment requirement must map to a specific file, query, object, or report section.

### Rule 10 — Do not proceed past failed validation

If a phase's validation fails, fix the issue before continuing.

---

# 7. Final Definition of Done

The project is complete only when:

1. The Excel dataset has been transformed into a valid star-schema analytical database.
2. The database contains at least 5 related tables.
3. PK/FK relationships are implemented and validated.
4. Data has been successfully loaded.
5. At least 15 meaningful SQL queries exist.
6. JOINs, CTEs, subqueries, and CASE statements are demonstrated.
7. A SQL View exists.
8. A Stored Procedure exists.
9. Performance optimization is documented.
10. Profitability, customer behavior, and sales trends are analyzed.
11. KPI/business reporting is complete.
12. Documentation explains the entire project.
13. All scripts are tested and reproducible.
14. The final project satisfies every requirement in the assignment.

---

# 8. Important Learning Goal

This project is not only about producing files.

The student should be able to explain:

- What a fact table is
- What a dimension table is
- What a star schema is
- Why normalization is useful
- What primary and foreign keys do
- How the tables are related
- What each SQL query calculates
- Why JOINs are needed
- What a CTE is
- What a subquery is
- What CASE does
- What a SQL View is
- What a Stored Procedure is
- Why indexes improve some queries
- What each KPI means from a business perspective

The coding agent should therefore produce clear comments and documentation rather than opaque generated code.
