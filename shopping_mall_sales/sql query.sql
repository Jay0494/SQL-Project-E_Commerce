SELECT * FROM ecommerce_sales_records;

-- DATA QUALITY CHECK 
SELECT
    'Null Order ID' AS Check_Type,
    COUNT(*) AS Issue_Count
FROM ecommerce_sales_records
WHERE order_id IS NULL

UNION ALL

SELECT
    'Null Product',
    COUNT(*)
FROM ecommerce_sales_records
WHERE product IS NULL

UNION ALL

SELECT
    'Null Quantity',
    COUNT(*)
FROM ecommerce_sales_records
WHERE quantity IS NULL

UNION ALL

SELECT
    'Negative Quantity',
    COUNT(*)
FROM ecommerce_sales_records
WHERE quantity < 0

UNION ALL

SELECT
    'Negative Price',
    COUNT(*)
FROM ecommerce_sales_records
WHERE price < 0

UNION ALL

SELECT
    'Future Order Date',
    COUNT(*)
FROM ecommerce_sales_records
WHERE `Date` > CURRENT_DATE

UNION ALL

SELECT
    'Duplicate Order IDs',
    COUNT(*)
FROM (
    SELECT order_id
    FROM ecommerce_sales_records
    GROUP BY order_id
    HAVING COUNT(*) > 1
) d;

-- DUPLICATE TABLE
CREATE TABLE sales AS
SELECT *
FROM ecommerce_sales_records; 

-- DATA MODELLING
ALTER TABLE sales
ADD Total_sales DECIMAL(10,2);

UPDATE sales
SET Total_sales = Quantity * Price;

CREATE TABLE dim_product(
	Product VARCHAR(50),
    Product_ID INT AUTO_INCREMENT PRIMARY KEY) ;

INSERT INTO dim_product(Product)
SELECT DISTINCT Product
FROM sales;
        
    
CREATE TABLE dim_category (
	Category VARCHAR(50),
    Category_ID INT AUTO_INCREMENT PRIMARY KEY) ;

INSERT INTO dim_category (Category)
SELECT DISTINCT Category
FROM sales;	

CREATE TABLE dim_city (
		CIty VARCHAR(50),
        City_ID INT AUTO_INCREMENT PRIMARY KEY);

INSERT INTO dim_city (City)
SELECT DISTINCT City
FROM sales;


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
   FOREIGN KEY (City_ID)
        REFERENCES dim_city(City_ID),

    FOREIGN KEY (Product_ID)
        REFERENCES dim_product(Product_ID),

    FOREIGN KEY (Category_ID)
        REFERENCES dim_category(Category_ID)); 
        

INSERT INTO fact_orders (
    Order_ID,
    City_ID,
    Product_ID,
    Category_ID,
    Quantity,
    Price,
    Total_sales,
    `Date`
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
JOIN dim_city c
    ON s.City = c.City
JOIN dim_product p
    ON s.Product = p.Product
JOIN dim_category cat
    ON s.Category = cat.Category;
    
SELECT * FROM fact_orders;    


-- INSIGHTS
-- top 5 selling products 
SELECT  
	p.Product, 
    SUM(f.Total_sales) AS Revenue
FROM fact_orders f
JOIN dim_product p
		ON f.Product_ID = p.Product_ID
GROUP BY p.Product
ORDER BY Revenue DESC
lIMIT 5;        


-- BEST SELLING CATEGORIES
SELECT  
	c.Category, 
    SUM(f.Total_sales) AS Revenue
FROM fact_orders f
JOIN dim_category c
		ON f.Category_ID = c.Category_ID
GROUP BY c.Category
ORDER BY Revenue DESC;    


-- REVENUE BY CITY
SELECT  
	ci.City, 
    SUM(f.Total_sales) AS Revenue
FROM fact_orders f
JOIN dim_city ci
		ON f.City_ID = ci.City_ID
GROUP BY ci.City
ORDER BY Revenue DESC;   



-- KPI

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

