# Architecture du Data Warehouse RetailChain

## 1. Objectif

Ce document décrit l'architecture technique du data warehouse (DWH) conçu pour *RetailChain*. L'objectif principal est de centraliser et de structurer les données de vente des deux dernières années afin de supporter les objectifs analytiques de l'entreprise :
* Analyser les performances commerciales (par période, géographie, produit).
* Identifier les tendances et les comportements clients.
* Calculer et comparer les performances des magasins.

## 2. Vue d’ensemble & Choix Fondamentaux

Nous avons opté pour une architecture multi-couches classique, garantissant la robustesse, la performance et la maintenabilité du système.

**Flux de données :**
`Staging (Données brutes)` → `ETL (Fonctions PL/pgSQL)` → `DWH (Schéma en étoile)` → `Marts (Vues matérialisées)`

### 2.1. Modèle : Schéma en Étoile (Star Schema)

Le cœur du DWH est un **schéma en étoile** unique, centré sur les ventes.

* **Table de faits :** `dwh.fact_sales`
* **Dimensions :** `dwh.dim_date`, `dwh.dim_customer`, `dwh.dim_store`, `dwh.dim_product`

> **Justification :**
> * **Performance :** Ce modèle est le plus performant pour les requêtes analytiques. Il minimise le nombre de jointures (une seule par dimension vers la table de faits), ce qui est crucial pour des requêtes ad-hoc.
> * **Simplicité :** Il est très intuitif pour les analystes. La logique "faits" (mesures) et "dimensions" (axes d'analyse) correspond directement aux questions métier (ex: "ventes" *par* "temps", *par* "client").

### 2.2. Granularité de la Table de Faits

La granularité de `dwh.fact_sales` est la plus fine possible : **une ligne par produit par transaction**.

> **Justification :**
> * **Flexibilité Analytique :** Cette granularité nous permet de "remonter" (roll-up) à n'importe quel niveau d'agrégation (par jour, par magasin, par catégorie...) sans aucune perte d'information.
> * **Analyses Avancées :** C'est un prérequis indispensable pour des analyses comportementales comme le RFM ou les cohortes, qui nécessitent de descendre au niveau de la transaction et du client.
> * **Contrôle :** Une contrainte `UNIQUE (transaction_id, product_key)` a été mise en place pour garantir cette granularité et prévenir les doublons d'ETL.

---

## 3. Couches de l’architecture

### 3.1. Couche Staging (Schéma `staging`)

* **Rôle :** Zone de transit pour les données brutes (`_raw`).
* **Tables :** `staging.customers_raw`, `staging.stores_raw`, `staging.products_raw`, `staging.sales_raw`.

> **Justification :** Cette couche est indispensable pour un ETL robuste.
> * **Séparation des responsabilités :** Elle isole le DWH (propre et structuré) des données sources (brutes, potentiellement "sales").
> * **Idempotence :** Elle permet à notre ETL d'être relancé en toute sécurité. Les données sont chargées, puis traitées, sans "polluer" directement le DWH.

### 3.2. Couche DWH (Schéma `dwh`)

C'est le cœur du système, hébergeant notre schéma en étoile.

> **Justification (Stratégie SCD Mixte) :** C'est un choix de conception central. Nous avons appliqué différentes stratégies de gestion de l'historique (SCD - Slowly Changing Dimensions) pour équilibrer performance et précision historique.
>
> * **SCD Type 2 (pour `dim_customer` et `dim_product`) :**
>     * **Pourquoi ?** Il est crucial de garder l'historique. Si un client déménage, les ventes de 2023 doivent rester associées à son ancienne adresse. De même pour un changement de prix de produit.
>     * **Implémentation :** `valid_from`, `valid_to`, `is_current` et un **index partiel unique** pour garantir l'unicité de la *business key* seulement sur les lignes actives.
>
> * **SCD Type 1 (pour `dim_store`) :**
>     * **Pourquoi ?** Pour cette dimension (magasins), nous avons fait l'hypothèse qu'un changement (ex: renommage) est une simple correction. L'ancienne valeur est écrasée.
>     * **Compromis (Trade-off) :** C'est un choix de simplicité. L'ETL est plus rapide (un simple `INSERT ... ON CONFLICT`) au détriment de l'historique des magasins, jugé moins critique.

### 3.3. Couche ETL (Fonctions PL/pgSQL)

L'ensemble de la logique de transformation est encapsulé dans des fonctions PostgreSQL stockées dans le schéma `dwh`.

> **Justification :**
> * **Atomicité & Robustesse :** Plutôt qu'un script monolithique, nous avons des fonctions robustes (`dwh.run_full_etl()`, `dwh.upsert_dim_customer_scd2`, etc.) qui gèrent les transactions et les erreurs.
> * **Monitoring Intégré :** Nous avons bâti un micro-framework de monitoring (`etl_runs`, `etl_events`, `etl_metrics`). Chaque exécution de l'ETL est tracée. En cas d'échec, le statut du "run" passe à `FAILED` et l'erreur est enregistrée, ce qui rend le système maintenable.
> * **Idempotence :** L'ETL peut être lancé plusieurs fois. Les SCD gèrent les mises à jour et la table de faits (`ON CONFLICT ... DO NOTHING`) ignore les doublons.

### 3.4. Couche Marts (Schéma `marts`)

* **Rôle :** Fournir des agrégats pré-calculés pour les analyses récurrentes (ex: dashboards).
* **Technologie :** Vues Matérialisées (`mv_monthly_sales_country`, etc.).

> **Justification (Séparation DWH / Marts) :** C'est une optimisation clé de performance.
> * **Le `dwh`** est optimisé pour le *stockage* et les analyses *ad-hoc complexes* (cohortes, RFM).
> * **Les `marts`** sont optimisés pour la *lecture rapide*. Une requête sur `marts.mv_monthly_sales_country` est instantanée, car le calcul est déjà fait.
> * **Maintenance :** Les Marts sont rafraîchis via une fonction dédiée (`dwh.refresh_all_marts()`) après chaque exécution de l'ETL.

---

## 4. Stratégie d'optimisation

* **Indexation Stratégique :**
    * **B-Tree (standard) :** Sur les clés étrangères (`fk_...`) pour accélérer les `JOIN`.
    * **B-Tree Composites :** Sur `(date_key, product_key)` pour les filtres fréquents.
    * **Index BRIN :** Sur `date_key` et `transaction_id`. C'est un choix spécifique aux DWH. Ces index sont très légers et parfaits pour les données triées chronologiquement, accélérant massivement les requêtes sur des plages de dates.
* **Vues Matérialisées :** (Voir Couche Marts) Pré-calculer les agrégats lourds.

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