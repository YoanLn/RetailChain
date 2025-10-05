# Documentation – Sample Data pour RetailChain Data Warehouse

## 1. Contexte
Ce fichier explique comment nous avons généré les données d'exemple pour le projet Data Warehouse RetailChain.  
L’objectif était de remplir les dimensions et la table de faits avec des volumes réalistes pour permettre des analyses métiers pertinentes.

---

## 2. Dimension Date (`dim_date`)
- **Méthode** : Fonction PL/pgSQL fournie par le professeur `dwh.populate_test_date(start_date, end_date)`.
- **Paramètres utilisés** :
  - `start_date = '2022-01-01'`
  - `end_date = '2023-12-31'`
- **Nombre de lignes générées** : 730 jours (2 ans).
- **Notes** :
  - Génère un `date_key` unique par jour au format `YYYYMMDD`.
  - Inclut `year_number`, `month_number`, `month_name`, `quarter_number`, `day_of_week`, `is_weekend`.
  - Ne pas modifier la fonction fournie.
- **Usage** : Référence pour toutes les ventes dans `fact_sales`.

---

## 3. Dimension Customer (`dim_customer`)
- **Méthode** : `INSERT ... SELECT` avec `generate_series(1,1000)` pour créer 1 000 clients.
- **Colonnes générées** :
  - `customer_business_key` : ID client unique.
  - `first_name`, `last_name` : Noms aléatoires générés via `md5(random())`.
  - `country` : Choisi aléatoirement parmi `France, Germany, Italy, Spain, Belgium`.
- **Nombre de lignes générées** : 1 000.
- **Notes** :
  - La distribution des pays est aléatoire.
  - Permet de tester les analyses par pays et comportement clients.

---

## 4. Dimension Store (`dim_store`)
- **Méthode** : `INSERT ... SELECT` avec `generate_series(1,50)` pour créer 50 magasins.
- **Colonnes générées** :
  - `store_business_key` : ID magasin unique.
  - `store_name` : `"Store " || gs`.
  - `city`, `country` : Choisis aléatoirement parmi des villes et pays européens.
- **Nombre de lignes générées** : 50.
- **Notes** :
  - Assure la diversité géographique.
  - Supporte les analyses par magasin, ville et pays.

---

## 5. Dimension Product (`dim_product`)
- **Méthode** : `INSERT ... SELECT` avec `generate_series(1,1000)` pour créer 1 000 produits.
- **Colonnes générées** :
  - `product_business_key` : ID produit unique.
  - `product_name` : `"Product " || gs`.
  - `category` : Choisi aléatoirement parmi `Electronics, Clothing, Food, Toys, Home`.
  - `subcategory` : Aléatoire parmi `A, B, C, D, E`.
- **Nombre de lignes générées** : 1 000.
- **Notes** :
  - Permet des analyses par catégorie et sous-catégorie.
  - Randomisation nécessaire pour avoir toutes les catégories représentées.

---

## 6. Table de faits (`fact_sales`)
- **Méthode** : Bloc PL/pgSQL `DO $$ ... END $$` pour générer 100 000 ventes.
- **Processus** :
  1. Boucle de 1 à 100 000 pour créer autant de transactions.
  2. Sélection aléatoire de :
     - `date_key` depuis `dim_date`
     - `customer_key` depuis `dim_customer`
     - `store_key` depuis `dim_store`
     - `product_key` et `category` depuis `dim_product`
  3. Quantité aléatoire entre 1 et 10 (`qty`).
  4. Prix unitaire selon catégorie :
     - Electronics : 50 à 500
     - Clothing : 10 à 100
     - Food : 1 à 20
     - Toys : 5 à 80
     - Home : 20 à 200
  5. `total_amount` calculé comme `qty * unit_price`.
- **Nombre de lignes générées** : 100 000.
- **Notes** :
  - Distribution aléatoire pour chaque catégorie et produit.
  - Permet de tester les requêtes analytiques et les agrégations.
  - Temps de génération : ~20 secondes pour 100 000 lignes.
  - Méthode lente mais réaliste, car chaque vente est indépendante et aléatoire.

---

## 7. Vérification
- **Nombre total de ventes** :
```sql
SELECT COUNT(*) FROM dwh.fact_sales;
