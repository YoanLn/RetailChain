-- 03_sample_data.sql -

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

SELECT dwh.populate_test_date('2022-01-01', '2023-12-31');

-- Enrichissement dim_date
-- Met à jour les colonnes supplémentaires après la génération de base
UPDATE dwh.dim_date
SET 
    day_name = TRIM(TO_CHAR(full_date, 'Day')),
    week_number = EXTRACT(WEEK FROM full_date),
    -- On simule quelques jours fériés réeeles pour la cohérence des données (ex: 1er Janvier, 25 Décembre)
    is_holiday = CASE 
        WHEN EXTRACT(MONTH FROM full_date) = 1 AND EXTRACT(DAY FROM full_date) = 1 THEN TRUE
        WHEN EXTRACT(MONTH FROM full_date) = 5 AND EXTRACT(DAY FROM full_date) = 1 THEN TRUE  -- Fête du travail
        WHEN EXTRACT(MONTH FROM full_date) = 8 AND EXTRACT(DAY FROM full_date) = 15 THEN TRUE -- Assomption
        WHEN EXTRACT(MONTH FROM full_date) = 12 AND EXTRACT(DAY FROM full_date) = 25 THEN TRUE
        ELSE FALSE
    END
WHERE day_name IS NULL; -- Pour éviter de le faire plusieurs fois

-- Clients (200 par pays, 1000 total)
INSERT INTO staging.customers_raw
SELECT
    ((c.ord - 1) * 200 + gs) AS customer_business_key,
    (ARRAY['Jean','Marie','Pierre','Luc','Sophie','Anna','Hans','Giulia','Carlos','Elena'])[1 + floor(random()*10)::int] AS first_name,
    (ARRAY['Dupont','Martin','Schmidt','Rossi','Garcia','Dubois','Müller','Bianchi','Lopez','Vermeulen'])[1 + floor(random()*10)::int] AS last_name,
    lower(md5(random()::text)::varchar(8)) || '@mail.com' AS email,
    (ARRAY['Male','Female'])[1 + floor(random()*2)::int] AS gender,
    c.country,
    CASE c.country
        WHEN 'France'  THEN (ARRAY['Paris','Lyon','Marseille'])[1 + floor(random()*3)::int]
        WHEN 'Germany' THEN (ARRAY['Berlin','Munich','Hamburg'])[1 + floor(random()*3)::int]
        WHEN 'Italy'   THEN (ARRAY['Rome','Milan','Naples'])[1 + floor(random()*3)::int]
        WHEN 'Spain'   THEN (ARRAY['Madrid','Barcelona','Valencia'])[1 + floor(random()*3)::int]
        WHEN 'Belgium' THEN (ARRAY['Brussels','Antwerp','Ghent'])[1 + floor(random()*3)::int]
    END AS city,
    DATE '1950-01-01' + (random() * 20000)::int * INTERVAL '1 day' AS birth_date
FROM unnest(ARRAY['France','Germany','Italy','Spain','Belgium']) WITH ORDINALITY c(country, ord)
CROSS JOIN generate_series(1,200) gs;

-- Magasins (10 par pays, 50 total)
INSERT INTO staging.stores_raw
SELECT
    ((c.ord - 1) * 10 + gs) AS store_business_key,
    'Store ' || ((c.ord - 1) * 10 + gs) AS store_name,
    CASE c.country
        WHEN 'France'  THEN (ARRAY['Paris','Lyon','Marseille'])[1 + floor(random()*3)::int]
        WHEN 'Germany' THEN (ARRAY['Berlin','Munich','Hamburg'])[1 + floor(random()*3)::int]
        WHEN 'Italy'   THEN (ARRAY['Rome','Milan','Naples'])[1 + floor(random()*3)::int]
        WHEN 'Spain'   THEN (ARRAY['Madrid','Barcelona','Valencia'])[1 + floor(random()*3)::int]
        WHEN 'Belgium' THEN (ARRAY['Brussels','Antwerp','Ghent'])[1 + floor(random()*3)::int]
    END AS city,
    c.country,
    (ARRAY['North','South','East','West','Central'])[1 + floor(random()*5)::int] AS region,
    (ARRAY['Standard','Outlet','Flagship'])[1 + floor(random()*3)::int] AS store_type,
    DATE '2000-01-01' + (random() * 8000)::int * INTERVAL '1 day' AS opening_date
FROM unnest(ARRAY['France','Germany','Italy','Spain','Belgium']) WITH ORDINALITY c(country, ord)
CROSS JOIN generate_series(1,10) gs;

-- Produits (1000)
INSERT INTO staging.products_raw
SELECT
    gs AS product_business_key,
    'Product ' || gs AS product_name,
    (ARRAY['BrandA','BrandB','BrandC','BrandD'])[1 + floor(random()*4)::int] AS brand,
    (ARRAY['Electronics','Clothing','Food','Toys','Home'])[1 + floor(random()*5)::int] AS category, 
    (ARRAY['A','B','C','D','E'])[1 + floor(random()*5)::int] AS subcategory,
    CASE (ARRAY['Electronics','Clothing','Food','Toys','Home'])[1 + floor(random()*5)::int]
        WHEN 'Electronics' THEN (100 + random()*1900)
        WHEN 'Clothing'    THEN (10 + random()*190)
        WHEN 'Food'        THEN (1 + random()*49)
        WHEN 'Toys'        THEN (5 + random()*95)
        ELSE (20 + random()*480)
    END::numeric(10,2) AS catalog_price
FROM generate_series(1,1000) AS gs;

-- Transactions (uniforme par magasin, client même pays, produit uniforme)
-- Liste ordonnée des magasins + taille + décalage aléatoire
WITH store_list AS (
    SELECT store_business_key, country, ROW_NUMBER() OVER () AS rn
    FROM staging.stores_raw
),
store_count AS (
    SELECT COUNT(*) AS n FROM store_list
),
rand_offset AS (
    SELECT FLOOR(random() * (SELECT n FROM store_count))::int AS off
)

INSERT INTO staging.sales_raw
SELECT
    gs AS transaction_id,
    (DATE '2022-01-01' + (FLOOR(random() * 730))::int) AS transaction_date,
    (
      SELECT c.customer_business_key
      FROM staging.customers_raw c
      WHERE c.country = s.country
      OFFSET FLOOR(random() * (
        SELECT COUNT(*) FROM staging.customers_raw c2 WHERE c2.country = s.country
      ))
      LIMIT 1
    ) AS customer_business_key,
    s.store_business_key,
    -- Produit: distribution uniforme garantie par modulo
    ((gs - 1) % (SELECT COUNT(*) FROM staging.products_raw) + 1) AS product_business_key,
    (CASE WHEN random() < 0.7 THEN 1 + FLOOR(random()*3)::int ELSE 4 + FLOOR(random()*6)::int END) AS quantity,
    (10 + random()*500)::numeric(10,2) AS unit_price,
    0.0 AS total_amount,
    (CASE WHEN random() < 0.3 THEN (random()*15)::numeric(10,2) ELSE 0 END) AS discount_amount
FROM generate_series(1, 100000) gs
JOIN store_count sc ON true
JOIN rand_offset ro ON true
JOIN store_list s
  ON s.rn = ((gs + ro.off) % sc.n) + 1;

-- Calcul du total
UPDATE staging.sales_raw
SET total_amount = (quantity * unit_price) - discount_amount;
