-- 1) CA et volume par mois et pays
SELECT
    year_number,
    month_number,
    country,
    total_sales,
    nb_customers
FROM marts.mv_monthly_sales_country
ORDER BY year_number, month_number, country;


-- 2) Saisonniers: moyenne lissée sur 3 mois par catégorie
WITH monthly AS (
  SELECT
    d.year_number,
    d.month_number,
    p.category,
    SUM(f.total_amount) AS sales
  FROM dwh.fact_sales f
  JOIN dwh.dim_date d ON f.date_key = d.date_key
  JOIN dwh.dim_product p ON f.product_key = p.product_key
  GROUP BY d.year_number, d.month_number, p.category
),
indexed AS (
  SELECT *,
         (year_number * 12 + month_number) AS ym
  FROM monthly
)
SELECT
  category,
  year_number,
  month_number,
  sales,
  AVG(sales) OVER (PARTITION BY category ORDER BY ym ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING) AS sales_ma3
FROM indexed
ORDER BY category, year_number, month_number;


-- 3) Classement des magasins par CA et ticket moyen
SELECT
  s.country,
  s.region,
  s.store_name,
  SUM(f.total_amount) AS total_sales,
  COUNT(*) AS nb_transactions,
  ROUND(SUM(f.total_amount)::numeric / NULLIF(COUNT(*),0), 2) AS avg_ticket
FROM dwh.fact_sales f
JOIN dwh.dim_store s ON f.store_key = s.store_key
GROUP BY s.country, s.region, s.store_name
ORDER BY total_sales DESC
LIMIT 50;


-- 4) Mix produit: part de chaque catégorie et prix moyen
SELECT
  category,
  SUM(total_sales) AS sales,
  SUM(total_qty) AS qty,
  ROUND(SUM(total_sales)::numeric / NULLIF(SUM(total_qty),0), 2) AS avg_price,
  ROUND(100.0 * SUM(total_sales) / NULLIF((SELECT SUM(total_sales) FROM marts.mv_top_products),0), 2) AS sales_share_pct
FROM marts.mv_top_products
GROUP BY category
ORDER BY sales DESC;


-- 5) Corrélation simple prix-quantité par catégorie (proxy d'élasticité)
WITH price_qty AS (
  SELECT
    p.category,
    ROUND(f.unit_price, 0) AS price_bucket,
    SUM(f.quantity) AS qty
  FROM dwh.fact_sales f
  JOIN dwh.dim_product p ON f.product_key = p.product_key
  GROUP BY p.category, ROUND(f.unit_price, 0)
)
SELECT
  category,
  price_bucket,
  qty,
  SUM(qty) OVER (PARTITION BY category ORDER BY price_bucket ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_qty
FROM price_qty
ORDER BY category, price_bucket;


-- 6) Cohortes: première commande et rétention mensuelle par cohorte
WITH first_order AS (
  SELECT
    f.customer_key,
    MIN(d.year_number * 12 + d.month_number) AS cohort_ym
  FROM dwh.fact_sales f
  JOIN dwh.dim_date d ON f.date_key = d.date_key
  GROUP BY f.customer_key
),
activity AS (
  SELECT
    f.customer_key,
    (d.year_number * 12 + d.month_number) AS order_ym
  FROM dwh.fact_sales f
  JOIN dwh.dim_date d ON f.date_key = d.date_key
),
cohort_matrix AS (
  SELECT
    fo.cohort_ym,
    a.order_ym,
    a.order_ym - fo.cohort_ym AS month_offset
  FROM first_order fo
  JOIN activity a ON a.customer_key = fo.customer_key
)
SELECT
  cohort_ym,
  month_offset,
  COUNT(DISTINCT CONCAT(cohort_ym, '-', month_offset, '-', order_ym, '-', cohort_ym)) AS active_events,
  COUNT(DISTINCT (SELECT customer_key FROM first_order fo2 WHERE fo2.cohort_ym = cohort_ym)) AS cohort_size
FROM cohort_matrix
GROUP BY cohort_ym, month_offset
ORDER BY cohort_ym, month_offset;


-- 7) RFM: segmentation clients
WITH base AS (
  SELECT
    f.customer_key,
    MAX(d.full_date) AS last_purchase_date,
    COUNT(*) AS frequency,
    SUM(f.total_amount) AS monetary
  FROM dwh.fact_sales f
  JOIN dwh.dim_date d ON f.date_key = d.date_key
  GROUP BY f.customer_key
),
ranks AS (
  SELECT
    customer_key,
    last_purchase_date,
    frequency,
    monetary,
    NTILE(5) OVER (ORDER BY last_purchase_date DESC) AS r_score,
    NTILE(5) OVER (ORDER BY frequency DESC) AS f_score,
    NTILE(5) OVER (ORDER BY monetary DESC) AS m_score
  FROM base
)
SELECT
  r_score, f_score, m_score,
  COUNT(*) AS nb_customers,
  ROUND(AVG(monetary)::numeric,2) AS avg_monetary
FROM ranks
GROUP BY r_score, f_score, m_score
ORDER BY r_score DESC, f_score DESC, m_score DESC;


-- 8) Segments de performance magasin (quartiles de CA)
WITH store_perf AS (
  SELECT
    s.store_key,
    s.country,
    s.region,
    s.store_name,
    SUM(f.total_amount) AS total_sales
  FROM dwh.fact_sales f
  JOIN dwh.dim_store s ON f.store_key = s.store_key
  GROUP BY s.store_key, s.country, s.region, s.store_name
),
segmented AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY total_sales DESC) AS performance_quartile
  FROM store_perf
)
SELECT
  country, region,
  performance_quartile,
  COUNT(*) AS nb_stores,
  ROUND(AVG(total_sales)::numeric,2) AS avg_sales
FROM segmented
GROUP BY country, region, performance_quartile
ORDER BY country, region, performance_quartile;


-- 9) Distribution des quantités et panier moyen
SELECT
  CASE
    WHEN quantity BETWEEN 1 AND 2 THEN '1-2'
    WHEN quantity BETWEEN 3 AND 5 THEN '3-5'
    WHEN quantity BETWEEN 6 AND 9 THEN '6-9'
    ELSE '10+'
  END AS qty_bucket,
  COUNT(*) AS nb_transactions,
  ROUND(AVG(total_amount)::numeric,2) AS avg_ticket
FROM dwh.fact_sales
GROUP BY qty_bucket
ORDER BY nb_transactions DESC;


-- 10) Contribution des marques
SELECT
  brand,
  SUM(total_sales) AS total_sales,
  SUM(total_qty) AS total_qty,
  ROUND(100.0 * SUM(total_sales) / NULLIF((SELECT SUM(total_sales) FROM marts.mv_top_products),0), 2) AS sales_share_pct
FROM marts.mv_top_products
GROUP BY brand
ORDER BY total_sales DESC;


-- 11) Part de chaque pays dans le CA total
SELECT
  country,
  SUM(total_sales) AS total_sales,
  ROUND(100.0 * SUM(total_sales) / NULLIF((SELECT SUM(total_sales) FROM marts.mv_monthly_sales_country),0), 2) AS market_share_pct
FROM marts.mv_monthly_sales_country
GROUP BY country
ORDER BY total_sales DESC;


-- 12) Top 5 produits par pays et mois
WITH monthly_product AS (
  SELECT
    d.year_number,
    d.month_number,
    c.country,
    p.product_name,
    SUM(f.total_amount) AS sales
  FROM dwh.fact_sales f
  JOIN dwh.dim_date d ON f.date_key = d.date_key
  JOIN dwh.dim_customer c ON f.customer_key = c.customer_key
  JOIN dwh.dim_product p ON f.product_key = p.product_key
  GROUP BY d.year_number, d.month_number, c.country, p.product_name
),
ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY year_number, month_number, country ORDER BY sales DESC) AS rn
  FROM monthly_product
)
SELECT
  year_number, month_number, country, product_name, sales
FROM ranked
WHERE rn <= 5
ORDER BY year_number, month_number, country, rn;