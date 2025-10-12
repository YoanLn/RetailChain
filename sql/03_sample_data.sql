-- ============================================
-- 03_sample_data.sql
-- Création des tables staging
-- ============================================

CREATE SCHEMA IF NOT EXISTS staging;


DROP TABLE IF EXISTS staging.customers_raw CASCADE;
DROP TABLE IF EXISTS staging.stores_raw CASCADE;
DROP TABLE IF EXISTS staging.products_raw CASCADE;
DROP TABLE IF EXISTS staging.sales_raw CASCADE;

CREATE TABLE staging.customers_raw (
    customer_business_key INTEGER,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(150),
    gender VARCHAR(10),
    country VARCHAR(50),
    city VARCHAR(100),
    birth_date DATE
);

CREATE TABLE staging.stores_raw (
    store_business_key INTEGER,
    store_name VARCHAR(200),
    city VARCHAR(100),
    country VARCHAR(50),
    region VARCHAR(50),
    store_type VARCHAR(50),
    opening_date DATE
);

CREATE TABLE staging.products_raw (
    product_business_key INTEGER,
    product_name VARCHAR(300),
    brand VARCHAR(100),
    category VARCHAR(100),
    subcategory VARCHAR(100),
    catalog_price DECIMAL(10,2)
);

CREATE TABLE staging.sales_raw (
    transaction_id INTEGER,
    transaction_date DATE,
    customer_business_key INTEGER,
    store_business_key INTEGER,
    product_business_key INTEGER,
    quantity INTEGER,
    unit_price DECIMAL(10,2),
    total_amount DECIMAL(10,2),
    discount_amount DECIMAL(10,2)
);

-- ============================================
-- Génération de données brutes
-- ============================================

-- Fonction pour dim_date (FOURNIE - ne pas modifier)
CREATE OR REPLACE FUNCTION dwh.populate_test_date(start_date DATE, end_date DATE)
RETURNS VOID AS $$
DECLARE
    curr_date DATE;
BEGIN
    curr_date := start_date;
    WHILE curr_date <= end_date LOOP
        INSERT INTO dwh.dim_date (
            date_key, full_date, year_number, month_number, 
            month_name, quarter_number, day_of_week, is_weekend
        ) VALUES (
            TO_CHAR(curr_date, 'YYYYMMDD')::INTEGER,
            curr_date,
            EXTRACT(YEAR FROM curr_date),
            EXTRACT(MONTH FROM curr_date),
            TRIM(TO_CHAR(curr_date, 'Month')),
            EXTRACT(QUARTER FROM curr_date),
            EXTRACT(DOW FROM curr_date),
            EXTRACT(DOW FROM curr_date) IN (0,6)
        );
        curr_date := curr_date + INTERVAL '1 day';
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- Génération automatique des dates
SELECT dwh.populate_test_date('2022-01-01', '2023-12-31');


-- Clients
INSERT INTO staging.customers_raw
SELECT
    gs AS customer_business_key,
    initcap(md5(random()::text)::varchar(8)) AS first_name,
    initcap(md5(random()::text)::varchar(10)) AS last_name,
    lower(md5(random()::text)::varchar(12)) || '@mail.com' AS email,
    (ARRAY['Male','Female','Other'])[1 + floor(random()*3)::int] AS gender,
    (ARRAY['France','Germany','Italy','Spain','Belgium'])[1 + floor(random()*5)::int] AS country,
    (ARRAY['Paris','Berlin','Rome','Madrid','Brussels'])[1 + floor(random()*5)::int] AS city,
    DATE '1970-01-01' + (random() * 18000)::int * INTERVAL '1 day' AS birth_date
FROM generate_series(1,1000) AS gs;

-- Magasins
INSERT INTO staging.stores_raw
SELECT
    gs AS store_business_key,
    'Store ' || gs AS store_name,
    (ARRAY['Paris','Berlin','Rome','Madrid','Brussels'])[1 + floor(random()*5)::int] AS city,
    (ARRAY['France','Germany','Italy','Spain','Belgium'])[1 + floor(random()*5)::int] AS country,
    (ARRAY['North','South','East','West','Central'])[1 + floor(random()*5)::int] AS region,
    (ARRAY['Flagship','Outlet','Standard'])[1 + floor(random()*3)::int] AS store_type,
    DATE '2000-01-01' + (random() * 8000)::int * INTERVAL '1 day' AS opening_date
FROM generate_series(1,50) AS gs;

-- Produits
INSERT INTO staging.products_raw
SELECT
    gs AS product_business_key,
    'Product ' || gs AS product_name,
    (ARRAY['BrandA','BrandB','BrandC','BrandD'])[1 + floor(random()*4)::int] AS brand,
    (ARRAY['Electronics','Clothing','Food','Toys','Home'])[1 + floor(random()*5)::int] AS category,
    (ARRAY['A','B','C','D','E'])[1 + floor(random()*5)::int] AS subcategory,
    (10 + random()*500)::numeric(10,2) AS catalog_price
FROM generate_series(1,1000) AS gs;

-- Transactions
INSERT INTO staging.sales_raw
SELECT
    gs AS transaction_id,
    (SELECT full_date FROM dwh.dim_date ORDER BY random() LIMIT 1) AS transaction_date,
    (SELECT customer_business_key FROM staging.customers_raw ORDER BY random() LIMIT 1),
    (SELECT store_business_key FROM staging.stores_raw ORDER BY random() LIMIT 1),
    (SELECT product_business_key FROM staging.products_raw ORDER BY random() LIMIT 1),
    1 + floor(random()*10)::int AS quantity,
    (10 + random()*500)::numeric(10,2) AS unit_price,
    0.0 AS total_amount, -- sera recalculé
    (random()*20)::numeric(10,2) AS discount_amount
FROM generate_series(1,100000) AS gs;

-- Mise à jour du total_amount
UPDATE staging.sales_raw
SET total_amount = (quantity * unit_price) - discount_amount;