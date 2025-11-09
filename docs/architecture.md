# Architecture du Data Warehouse RetailChain

## 1. Objectif

Ce document décrit l'architecture technique du data warehouse pour *RetailChain*. L'objectif principal est de centraliser et de structurer les données de vente des deux dernières années afin de supporter les objectifs analytiques de l'entreprise :
* Analyser les performances commerciales (par période, géographie, produit).
* Identifier les tendances et les comportements clients.
* Calculer et comparer les performances des magasins.

## 2. Vue d’ensemble & Choix Fondamentaux

On a choisi une architecture classique en plusieurs couches. C'est ce qui garantit que le système est solide, performant et facile à maintenir.

**Flux de données :**
`Staging (Données brutes générées)` → `ETL (Fonctions PL/pgSQL)` → `DWH (Schéma en étoile)` → `Marts (Vues matérialisées)`

### 2.1. Modèle : Schéma en Étoile (Star Schema)

Le modèle central du DWH est un **schéma en étoile**, centré sur les ventes.

* **Table de faits :** `dwh.fact_sales`
* **Dimensions :** `dwh.dim_date`, `dwh.dim_customer`, `dwh.dim_store`, `dwh.dim_product`

> **Justification :**
> * **Performance :** Ce modèle est le plus performant pour les requêtes analytiques. Il minimise le nombre de jointures (une seule par dimension vers la table de faits), ce qui est crucial pour des requêtes ad-hoc.
> * **Simplicité :** Il est très intuitif pour les analystes. La logique faits (mesures) et dimensions correspond directement aux questions métier (ex: "ventes" par "temps", par "client").

### 2.2. Granularité de la Table de Faits

La granularité de `dwh.fact_sales` est la plus fine possible : **une ligne par produit par transaction**.

> **Justification :**
> * **Flexibilité :** Cette granularité nous permet de roll-up à n'importe quel niveau d'agrégation (par jour, par magasin, par catégorie...) sans aucune perte d'information.
> * **Analyses complexes :** C'est très important pour des analyses comportementales comme le RFM ou les cohortes, qui nécessitent de descendre au niveau de la transaction et du client.
> * **Contrôle des données :** Une contrainte `UNIQUE (transaction_id, product_key)` a été mise en place pour garantir cette granularité et prévenir les doublons d'ETL.

---

## 3. Couches de l’architecture

### 3.1. Couche Staging (Schéma `staging`)

* **Rôle :** Zone de transit pour les données brutes (`_raw`).
* **Tables :** `staging.customers_raw`, `staging.stores_raw`, `staging.products_raw`, `staging.sales_raw`.

> **Justification :** On a fait un schéma staging pour une raison simple : elle isole le DWH qui est propre et structuré, des données sources (brutes, potentiellement sales).
> **Pouvoir relancer l'ETL :** Elle permet à notre ETL d'être relancé en toute sécurité. Les données sont chargées, puis traitées, sans polluer directement le DWH.

### 3.2. Couche DWH (Schéma `dwh`)

C'est le cœur du système, il héberge notre schéma en étoile et nos tables.

> **Justification (Stratégie SCD Mixte) :** Nous avons appliqué différentes stratégies de gestion de l'historique pour équilibrer performance et précision historique.
>
> * **SCD Type 2 (pour `dim_customer` et `dim_product`) :**
>     * **Pourquoi ?** Il est crucial de garder l'historique surtout pour ces types de données. Si un client déménage, les ventes de 2023 doivent rester associées à son ancienne adresse. De même pour un changement de prix de produit.
>     * **Implémentation :** `valid_from`, `valid_to`, `is_current` et un **index partiel unique** pour garantir l'unicité de la *business key* seulement sur les lignes actives.
>
> * **SCD Type 1 (pour `dim_store`) :**
>     * **Pourquoi ?** Pour cette dimension (magasins), nous avons fait l'hypothèse qu'un changement (ex: renommage) est une simple correction. L'ancienne valeur est écrasée. Il n'y a pas besoin d'historiser et d'avoir plusieurs versions d'un magasin. Cela permet d'éviter d'avoir trop de lignes pour un magasin.
>     * **Compromis (Trade-off) :** C'est un choix de simplicité. L'ETL est plus rapide (un simple `INSERT ... ON CONFLICT`) au détriment de l'historique des magasins, jugé moins critique.

### 3.3. Couche ETL (Fonctions PL/pgSQL)

L'ensemble de la logique de transformation est encapsulé dans des fonctions PostgreSQL stockées dans le schéma `dwh`.

> **Justification :**
> * **Atomicité & Robustesse :** Plutôt qu'un seul gros script, on a créé des fonctions faisants le nécessaire : (`dwh.run_full_etl()`, `dwh.upsert_dim_customer_scd2`, etc.) qui gèrent les transactions et les erreurs.
> * **Monitoring Intégré :** Nous avons bâti un micro-framework de monitoring (`etl_runs`, `etl_events`, `etl_metrics`). Chaque exécution de l'ETL est tracée. En cas d'échec, le statut du "run" passe à `FAILED` et l'erreur est enregistrée, ce qui rend le système maintenable.
> * **Relançable :** L'ETL peut être lancé plusieurs fois. Les SCD gèrent les mises à jour et la table de faits (`ON CONFLICT ... DO NOTHING`) ignore les doublons.

### 3.4. Couche Marts (Schéma `marts`)

* **Rôle :** Fournir des agrégats pré-calculés pour les analyses récurrentes (ex: dashboards).
* **Technologie :** Vues Matérialisées (`mv_monthly_sales_country`, etc.).

> **Justification :** C'est une optimisation clé de performance. Cela nous permet de séparer les données du DWH et les données des marts nécessaires.
> * **Le `dwh`** est optimisé pour le *stockage* et les analyses *ad-hoc complexes* (cohortes, RFM).
> * **Les `marts`** sont optimisés pour la *lecture rapide*. Une requête sur `marts.mv_monthly_sales_country` est instantanée, car le calcul est déjà fait.
> * **Maintenance :** Les Marts sont rafraîchis via une fonction dédiée (`dwh.refresh_all_marts()`) après chaque exécution de l'ETL.

---

## 4. Stratégie d'optimisation

* **Indexation Stratégique :**
    * **B-Tree (standard) :** Sur les clés étrangères (`fk_...`) pour accélérer les `JOIN`.
    * **B-Tree Composites :** Sur `(date_key, product_key)` pour les filtres fréquents.
    * **Index BRIN :** On a mis un index BRIN sur transaction_id. Comme notre ID est séquentiel (de 1 à 1M), cet index est super léger et très rapide. On en a aussi mis un sur date_key.
* **Vues Matérialisées :** Pré-calculer les agrégats lourds.

---
## 5. Schéma logique (simplifié)

                 [dwh.dim_date]
                 (PK: date_key)
                       |
                       | (FK: date_key)
                       |
[dwh.dim_customer] --(FK: customer_key)-- [dwh.fact_sales] --(FK: product_key)-- [dwh.dim_product]
(PK: customer_key)                         (PK: sales_key)                       (PK: product_key)
                                                  |
                                                  | (FK: store_key)
                                                  |
                                            [dwh.dim_store]
                                            (PK: store_key)