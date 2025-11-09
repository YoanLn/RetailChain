-- 05_optimisations.sql -

-- 1. Indexation avancée

-- Index composites pour accélérer les requêtes analytiques fréquentes
-- Exemple : requêtes par date + produit
CREATE INDEX IF NOT EXISTS idx_fact_sales_date_product
    ON dwh.fact_sales(date_key, product_key);

-- Exemple : requêtes par date + magasin
CREATE INDEX IF NOT EXISTS idx_fact_sales_date_store
    ON dwh.fact_sales(date_key, store_key);

-- Exemple : requêtes par client + date
CREATE INDEX IF NOT EXISTS idx_fact_sales_customer_date
    ON dwh.fact_sales(customer_key, date_key);

-- Index sur les colonnes de filtrage fréquentes dans les dimensions
CREATE INDEX IF NOT EXISTS idx_customer_city ON dwh.dim_customer(city);
CREATE INDEX IF NOT EXISTS idx_product_brand ON dwh.dim_product(brand);


-- 2. Vues matérialisées (les "marts")

-- Ventes mensuelles par pays
CREATE MATERIALIZED VIEW IF NOT EXISTS marts.mv_monthly_sales_country AS
SELECT
    d.year_number,
    d.month_number,
    c.country,
    SUM(f.total_amount) AS total_sales,
    COUNT(DISTINCT f.customer_key) AS nb_customers
FROM dwh.fact_sales f
JOIN dwh.dim_date d ON f.date_key = d.date_key
JOIN dwh.dim_customer c ON f.customer_key = c.customer_key
GROUP BY d.year_number, d.month_number, c.country;

-- Ventes par produit (top produits)
CREATE MATERIALIZED VIEW IF NOT EXISTS marts.mv_top_products AS
SELECT
    p.category,
    p.brand,
    p.product_name,
    SUM(f.total_amount) AS total_sales,
    SUM(f.quantity) AS total_qty
FROM dwh.fact_sales f
JOIN dwh.dim_product p ON f.product_key = p.product_key
GROUP BY p.category, p.brand, p.product_name;

-- Ventes par magasin et région
CREATE MATERIALIZED VIEW IF NOT EXISTS marts.mv_sales_store_region AS
SELECT
    s.region,
    s.store_name,
    SUM(f.total_amount) AS total_sales,
    COUNT(DISTINCT f.customer_key) AS nb_customers
FROM dwh.fact_sales f
JOIN dwh.dim_store s ON f.store_key = s.store_key
GROUP BY s.region, s.store_name;


-- 3. Index BRIN 

-- Index BRIN sur la date, car les requêtes filtrent souvent sur des plages de dates.
CREATE INDEX IF NOT EXISTS idx_fact_sales_date_brin
    ON dwh.fact_sales USING BRIN(date_key);

-- Index BRIN sur l'ID de transaction, car il est séquentiel (vient du generate_series).
CREATE INDEX IF NOT EXISTS idx_fact_sales_transaction_brin
    ON dwh.fact_sales USING BRIN(transaction_id);


-- 4. Fonction de rafraîchissement des Marts

CREATE OR REPLACE FUNCTION dwh.refresh_all_marts()
RETURNS VOID AS $$
DECLARE
    le_run_id BIGINT;
BEGIN
    -- On loggue ce refresh dans notre table d'ETL
    INSERT INTO dwh.etl_runs (status, error_message) 
    VALUES ('RUNNING', 'Refreshing Marts') 
    RETURNING run_id INTO le_run_id;

    BEGIN
        PERFORM dwh.log_event(le_run_id, 'marts', 'INFO', 'Refreshing mv_monthly_sales_country...');
        REFRESH MATERIALIZED VIEW marts.mv_monthly_sales_country;
        
        PERFORM dwh.log_event(le_run_id, 'marts', 'INFO', 'Refreshing mv_top_products...');
        REFRESH MATERIALIZED VIEW marts.mv_top_products;
        
        PERFORM dwh.log_event(le_run_id, 'marts', 'INFO', 'Refreshing mv_sales_store_region...');
        REFRESH MATERIALIZED VIEW marts.mv_sales_store_region;
        
        PERFORM dwh.log_event(le_run_id, 'marts', 'INFO', 'All Marts refreshed successfully.');
        UPDATE dwh.etl_runs SET status = 'SUCCESS', ended_at = NOW() WHERE run_id = le_run_id;

    EXCEPTION WHEN others THEN
        UPDATE dwh.etl_runs SET status = 'FAILED', ended_at = NOW(), error_message = SQLERRM WHERE run_id = le_run_id;
        RAISE;
    END;
END;
$$ LANGUAGE plpgsql;