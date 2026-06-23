# E-Commerce Sales Data Warehouse: Data Quality Auditing & Dimensional Modeling

## Project Overview

This project takes a raw e-commerce sales dataset and transforms it into an analysis-ready star schema data warehouse using SQL. The work covers the full pipeline a BI team would expect before data reaches a dashboard: data quality auditing, staging, dimensional modeling, and fact table construction — laying the foundation for downstream reporting in Power BI or Tableau.

**Tools used:** MySQL, dimensional modeling (star schema design)

---

## Business Problem

Raw transactional sales data is rarely analysis-ready. Before building any dashboard or report, an analyst needs to answer:

- Is the data trustworthy? Are there nulls, duplicates, or impossible values (negative prices, future-dated orders)?
- How do we structure the data so it's fast to query and easy for BI tools to consume?
- How do we separate descriptive attributes (product, category, city) from transactional facts (quantity, price, sales) in a way that scales?

This project addresses all three by auditing the raw table, then re-modeling it into a star schema.

---

## Step 1: Data Quality Audit

Before any modeling work, I ran a structured data quality check against the raw `ecommerce_sales_records` table to catch issues that would silently break downstream calculations or reporting.

```sql
SELECT
    'Null Order ID' AS Check_Type,
    COUNT(*) AS Issue_Count
FROM ecommerce_sales_records
WHERE order_id IS NULL
UNION ALL
SELECT 'Null Product', COUNT(*)
FROM ecommerce_sales_records WHERE product IS NULL
UNION ALL
SELECT 'Null Quantity', COUNT(*)
FROM ecommerce_sales_records WHERE quantity IS NULL
UNION ALL
SELECT 'Negative Quantity', COUNT(*)
FROM ecommerce_sales_records WHERE quantity < 0
UNION ALL
SELECT 'Negative Price', COUNT(*)
FROM ecommerce_sales_records WHERE price < 0
UNION ALL
SELECT 'Future Order Date', COUNT(*)
FROM ecommerce_sales_records WHERE `Date` > CURRENT_DATE
UNION ALL
SELECT 'Duplicate Order IDs', COUNT(*)
FROM (
    SELECT order_id
    FROM ecommerce_sales_records
    GROUP BY order_id
    HAVING COUNT(*) > 1
) d;
```

**Why this matters:** Running all checks as a single `UNION ALL` query returns one consolidated audit report rather than seven separate result sets — useful for a quick, scannable data health summary that could be re-run on every data refresh.

**Checks performed:**
| Check | Purpose |
|---|---|
| Null Order ID / Product / Quantity | Flags incomplete records that would break joins or aggregations |
| Negative Quantity / Price | Catches data entry errors or system glitches (returns shouldn't appear as negative raw values without a clear refund flag) |
| Future Order Date | Identifies impossible timestamps, often a sign of system clock errors or test data leakage |
| Duplicate Order IDs | Surfaces potential double-counted transactions before they inflate revenue figures |

---

## Step 2: Staging the Data

To avoid modifying the raw source table, I duplicated it into a working `sales` table:

```sql
CREATE TABLE sales AS
SELECT * FROM ecommerce_sales_records;
```

This preserves the original raw data as a source of truth while giving me a safe space to transform and enrich.

---

## Step 3: Feature Engineering — Total Sales

Added a calculated `Total_sales` column (Quantity × Price), a derived measure needed for revenue reporting that wasn't present in the source data:

```sql
ALTER TABLE sales
ADD Total_sales DECIMAL(10,2);

UPDATE sales
SET Total_sales = Quantity * Price;
```

---

## Step 4: Dimensional Modeling (Star Schema Design)

The raw data stores `Product`, `Category`, and `City` as repeated text values on every row — inefficient for storage and inflexible for analysis. I normalized these into dimension tables, each with a surrogate auto-incrementing key, following standard star schema design.

### Dimension Tables

```sql
CREATE TABLE dim_product (
    Product VARCHAR(50),
    Product_ID INT AUTO_INCREMENT PRIMARY KEY
);
INSERT INTO dim_product (Product)
SELECT DISTINCT Product FROM sales;

CREATE TABLE dim_category (
    Category VARCHAR(50),
    Category_ID INT AUTO_INCREMENT PRIMARY KEY
);
INSERT INTO dim_category (Category)
SELECT DISTINCT Category FROM sales;

CREATE TABLE dim_city (
    City VARCHAR(50),
    City_ID INT AUTO_INCREMENT PRIMARY KEY
);
INSERT INTO dim_city (City)
SELECT DISTINCT City FROM sales;
```

### Fact Table

The fact table holds the transactional measures (Quantity, Price, Total_sales) and foreign keys linking back to each dimension:

```sql
CREATE TABLE fact_orders (
    Order_key INT AUTO_INCREMENT PRIMARY KEY,
    Order_ID VARCHAR(50),
    City_ID INT,
    Product_ID INT,
    Category_ID INT,
    Quantity INT,
    Price DECIMAL(10,2),
    Total_sales DECIMAL(10,2),
    `Date` DATE,
    FOREIGN KEY (City_ID) REFERENCES dim_city(City_ID),
    FOREIGN KEY (Product_ID) REFERENCES dim_product(Product_ID),
    FOREIGN KEY (Category_ID) REFERENCES dim_category(Category_ID)
);
```

### Populating the Fact Table

Joined the staged `sales` table against each new dimension table to map text values to their surrogate keys:

```sql
INSERT INTO fact_orders (
    Order_ID, City_ID, Product_ID, Category_ID,
    Quantity, Price, Total_sales, `Date`
)
SELECT
    s.Order_ID,
    c.City_ID,
    p.Product_ID,
    cat.Category_ID,
    s.Quantity,
    s.Price,
    s.Quantity * s.Price AS Total_sales,
    s.`Date`
FROM sales s
JOIN dim_city c ON s.City = c.City
JOIN dim_product p ON s.Product = p.Product
JOIN dim_category cat ON s.Category = cat.Category;
```

---

## Step 5: Business Insights Querying

With the star schema in place, I queried `fact_orders` against each dimension to answer core business questions a stakeholder would actually ask. This is the payoff of the modeling work — joins across the schema are now simple and fast.

### Revenue by City

```sql
-- REVENUE BY CITY
SELECT
    ci.City,
    SUM(f.Total_sales) AS Revenue
FROM fact_orders f
JOIN dim_city ci
    ON f.City_ID = ci.City_ID
GROUP BY ci.City
ORDER BY Revenue DESC;
```

| City | Revenue |
|---|---|
| Mumbai | 3,197,293.30 |
| Jaipur | 3,138,418.77 |
| Pune | 2,958,953.75 |
| Kolkata | 2,946,512.18 |
| Bangalore | 2,761,749.03 |
| Delhi | 2,576,365.21 |
| Surat | 2,553,883.97 |
| Chennai | 2,282,006.22 |
| Ahmedabad | 2,099,774.90 |
| Hyderabad | 1,901,620.17 |

**Insight:** Mumbai and Jaipur lead in revenue, but the spread across the top 7 cities is fairly tight (within ~20% of each other) — suggesting a broadly distributed customer base rather than dependence on one city.

### Best Selling Categories

```sql
-- BEST SELLING CATEGORIES
SELECT
    c.Category,
    SUM(f.Total_sales) AS Revenue
FROM fact_orders f
JOIN dim_category c
    ON f.Category_ID = c.Category_ID
GROUP BY c.Category
ORDER BY Revenue DESC;
```

| Category | Revenue |
|---|---|
| Electronics | 20,632,874.98 |
| Home Appliances | 2,981,601.33 |
| Accessories | 1,592,701.82 |
| Fashion | 1,124,380.54 |
| Books | 85,018.83 |

**Insight:** Electronics dominates the revenue mix, generating roughly 78% of total revenue — far outpacing every other category combined. This is the kind of concentration risk a business should be aware of: growth (or disruption) in Electronics drives the whole top line.

### Top 5 Selling Products

```sql
-- TOP 5 SELLING PRODUCTS
SELECT
    p.Product,
    SUM(f.Total_sales) AS Revenue
FROM fact_orders f
JOIN dim_product p
    ON f.Product_ID = p.Product_ID
GROUP BY p.Product
ORDER BY Revenue DESC
LIMIT 5;
```

| Product | Revenue |
|---|---|
| Laptop | 10,866,810.28 |
| Tablet | 5,633,543.32 |
| Smartphone | 3,431,372.85 |
| Air Fryer | 1,445,610.80 |
| Watch | 1,187,306.94 |

**Insight:** The top 3 products are all Electronics, confirming the category-level finding. Laptops alone account for roughly 40% of the top-5 revenue total.

### Key Business Metrics (KPI Summary)

```sql
-- KEY METRICS SUMMARY
SELECT
    'Revenue' AS Metric,
    SUM(Total_sales) AS Value
FROM fact_orders

UNION ALL

SELECT
    'Total Quantity',
    SUM(Quantity)
FROM fact_orders

UNION ALL

SELECT
    'Total Orders',
    COUNT(Order_ID)
FROM fact_orders;
```

| Metric | Value |
|---|---|
| Revenue | 26,416,577.50 |
| Total Quantity | 2,913.00 |
| Total Orders | 964.00 |

**Insight:** Average order value works out to roughly **27,402** (Revenue ÷ Total Orders) and around **3 units per order** (Total Quantity ÷ Total Orders) — a useful baseline KPI pair to track over time as the dataset grows or refreshes.

---

## Resulting Schema

```
            dim_product
                 |
dim_city -- fact_orders -- dim_category
```

A classic star schema: one central fact table (`fact_orders`) surrounded by lookup dimension tables, connected via foreign keys. This structure is optimized for the kind of slice-and-dice analysis BI tools perform (e.g., "Total sales by Category by City over time").

---

## Why This Approach

- **Data quality first:** Auditing before modeling prevents building a "pretty" schema on top of broken data.
- **Non-destructive staging:** Keeping the raw table untouched and working on a `sales` copy protects the source of truth.
- **Star schema over a flat table:** Reduces redundancy (city/product/category names aren't repeated thousands of times), improves query performance on large datasets, and matches the data model BI tools like Power BI and Tableau are optimized to consume.
- **Surrogate keys:** Using auto-incrementing IDs rather than text fields as join keys is faster and more storage-efficient at scale.

---

## Next Steps

- Connect `fact_orders` and the dimension tables to Power BI / Tableau to build a sales performance dashboard (revenue by category, top products, sales by city, trend over time).
- Add a `dim_date` table for richer time-intelligence (month, quarter, year, day-of-week) rather than relying on a raw date column.
- Set up the data quality audit query as a recurring check on each data refresh.
- Investigate the Electronics revenue concentration further — break it down by sub-category or product line to assess dependency risk.

---

## Skills Demonstrated

`SQL` · `Data Quality Auditing` · `Dimensional Modeling (Star Schema)` · `ETL Staging` · `Data Warehousing` · `Database Design` · `Business Insights & KPI Reporting`
