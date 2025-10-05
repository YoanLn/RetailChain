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



INSERT INTO dwh.dim_customer (customer_business_key, first_name, last_name, country)
SELECT
    gs AS customer_business_key,
    initcap(md5(random()::text)::varchar(8)) AS first_name,
    initcap(md5(random()::text)::varchar(10)) AS last_name,
    (ARRAY['France','Germany','Italy','Spain','Belgium'])[1 + floor(random()*5)::int] AS country
FROM generate_series(1,1000) AS gs;


INSERT INTO dwh.dim_store (store_business_key, store_name, city, country)
SELECT
    gs AS store_business_key,
    'Store ' || gs AS store_name,
    (ARRAY['Paris','Berlin','Rome','Madrid','Brussels'])[1 + floor(random()*5)::int] AS city,
    (ARRAY['France','Germany','Italy','Spain','Belgium'])[1 + floor(random()*5)::int] AS country
FROM generate_series(1,50) AS gs;


INSERT INTO dwh.dim_product (product_business_key, product_name, category, subcategory)
SELECT
    gs AS product_business_key,
    'Product ' || gs AS product_name,
    (ARRAY['Electronics','Clothing','Food','Toys','Home'])[1 + floor(random()*5)::int] AS category,
    (ARRAY['A','B','C','D','E'])[1 + floor(random()*5)::int] AS subcategory
FROM generate_series(1,1000) AS gs;



DO $$
DECLARE
    i INT;
    d_key INT;
    c_key INT;
    s_key INT;
    p_key INT;
    p_cat TEXT;
    qty INT;
    unit DECIMAL(10,2);
BEGIN
    FOR i IN 1..100000 LOOP
        SELECT date_key INTO d_key FROM dwh.dim_date ORDER BY random() LIMIT 1;
        SELECT customer_key INTO c_key FROM dwh.dim_customer ORDER BY random() LIMIT 1;
        SELECT store_key INTO s_key FROM dwh.dim_store ORDER BY random() LIMIT 1;
        SELECT product_key, category INTO p_key, p_cat FROM dwh.dim_product ORDER BY random() LIMIT 1;
        
        qty := 1 + floor(random()*10)::int;
        unit := CASE p_cat
            WHEN 'Electronics' THEN 50 + floor(random()*451)
            WHEN 'Clothing'    THEN 10 + floor(random()*91)
            WHEN 'Food'        THEN 1 + floor(random()*19)
            WHEN 'Toys'        THEN 5 + floor(random()*76)
            WHEN 'Home'        THEN 20 + floor(random()*181)
            ELSE 10 + floor(random()*90)
        END;

        INSERT INTO dwh.fact_sales(
            date_key, customer_key, store_key, product_key, transaction_id, quantity, unit_price, total_amount
        ) VALUES (
            d_key, c_key, s_key, p_key, i, qty, unit, qty*unit
        );
    END LOOP;
END $$;



SELECT COUNT(*) FROM dwh.fact_sales; 
SELECT p.category, COUNT(*) AS nb_ventes, AVG(f.unit_price) AS avg_unit_price, AVG(f.total_amount) AS avg_total
FROM dwh.fact_sales f
JOIN dwh.dim_product p ON f.product_key = p.product_key
GROUP BY p.category
ORDER BY p.category;
