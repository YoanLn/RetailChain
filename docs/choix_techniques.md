# Fichier des Choix Techniques

Ce document explique les décisions techniques qu'on a prises pour construire le data warehouse de *RetailChain*. L'objectif, c'était de trouver un bon équilibre entre la performance, un ETL robuste, et des analyses précises.

## 1. Stratégie de Gestion de l'Historique (SCD)

C'est le choix de modélisation le plus important. On n'a pas utilisé la même stratégie pour toutes les dimensions, parce qu'elles n'ont pas les mêmes besoins.

### SCD Type 1 pour `dim_store` (Écrasement)F

* **Choix :** Pour les magasins, on utilise un SCD Type 1. Si un attribut change (ex: le nom du magasin), on écrase l'ancienne valeur.
* **Justification :** C'est un choix de simplicité. On a fait l'hypothèse que les changements sur un magasin sont rares ou qu'ils sont des corrections. L'analyse se basera donc toujours sur l'état *actuel* du magasin.
* **Implémentation ETL :** C'est très performant. On utilise un `INSERT ... ON CONFLICT (store_business_key) DO UPDATE`. C'est une seule commande atomique et rapide.

### SCD Type 2 pour `dim_customer` et `dim_product` (Historique)

* **Choix :** Pour les clients et les produits, il était obligatoire de garder un historique complet.
* **Justification :** C'est vital pour l'intégrité des analyses.
    * **Exemple Client :** Si un client déménage de Paris à Lyon en 2023, on *doit* pouvoir lier ses achats de 2022 à Paris. Si on avait fait un SCD Type 1 (écrasement), toutes ses ventes de 2022 auraient été faussement attribuées à Lyon.
    * **Exemple Produit :** De même, si le prix catalogue d'un produit change, on veut pouvoir analyser les ventes faites à l'ancien prix.
* **Implémentation :** On a ajouté les colonnes `valid_from`, `valid_to`, et `is_current`.
    * Pour garantir l'unicité de la *business key* (ex: `customer_business_key`) **uniquement** sur les lignes actives, on a utilisé un **index unique partiel** (`WHERE is_current = TRUE`). C'est la solution la plus propre en PostgreSQL pour gérer le SCD Type 2.

## 2. Stratégie ETL (Staging vers DWH)

L'objectif était d'avoir un "processus ETL fonctionnel" et "robuste". Tout est fait en **PL/pgSQL** pour garder la logique dans PostgreSQL, comme c'était demandé.

### Couche Staging

* **Choix :** On a créé un schéma `staging` séparé pour accueillir les données brutes (`_raw`).
* **Justification :** C'est une bonne pratique fondamentale. Le DWH (`dwh`) reste propre. L'ETL lit depuis `staging`, transforme, et charge dans `dwh`. Ça permet aussi de relancer l'ETL sans risque.

### Fonctions ETL (`04_etl_functions.sql`)

On a créé des fonctions pour chaque étape, orchestrées par `dwh.run_full_etl()`.

* **Chargement Dimensions (SCD) :**
    * Pour le SCD Type 1 (`dim_store`), on utilise `INSERT ... ON CONFLICT` (expliqué au-dessus).
    * Pour le SCD Type 2 (`dim_customer`, `dim_product`), on utilise une boucle `FOR ... LOOP` dans la fonction PL/pgSQL. On vérifie si une ligne a changé avec `IS DISTINCT FROM`.
    * **Justification :** On aurait pu essayer de faire une grosse requête "set-based" (tout en SQL), mais la logique du SCD Type 2 (fermer l'ancien, ouvrir le nouveau) est beaucoup plus claire et facile à débugger en PL/pgSQL. Le volume des dimensions (1000 clients, 1000 produits) est faible, donc cette approche en boucle est largement assez performante. 
    * **Gestion de l'historique :** Pour que notre jointure BETWEEN (dans le script 04) fonctionne avec les données du passé (2022-2023), on a mis DEFAULT '1900-01-01' sur la colonne valid_from directement dans le script 02_create_tables.sql.

* **Chargement des Faits (`fact_sales`) :**
    * **Choix :** On utilise une seule grosse requête `INSERT ... SELECT ...` qui fait les jointures entre `staging.sales_raw` et les dimensions.
    * **Jointure SCD (Corrigée) :** C'est le point le plus important. Pour lier un fait à la *bonne version historique* de la dimension (client ou produit), on ne fait **surtout pas** un join sur `is_current = TRUE`.
    * **Justification :** On doit lier la vente à l'état de la dimension *au moment de la transaction*. On utilise donc un `BETWEEN` sur la date de la transaction (`sr.transaction_date`) et les colonnes `valid_from` / `valid_to` de la dimension. (ex: `... AND sr.transaction_date BETWEEN dc.valid_from AND COALESCE(dc.valid_to, '9999-12-31')`)
    * **Résultat :** Une vente du 15 mai 2022 sera bien jointe à l'adresse de Paris, même si le client a déménagé à Lyon en 2023. C'est ça qui garantit que notre SCD Type 2 sert à quelque chose.
    * **Idempotence :** On a gardé `ON CONFLICT (transaction_id, product_key) DO NOTHING`. Si on relance l'ETL, on ne crée pas de doublons. C'est ce qui rend l'ETL "robuste".

### Monitoring ETL (Fonctionnalité avancée)

* **Choix :** On a créé trois tables : `etl_runs`, `etl_events`, et `etl_metrics`.
* **Justification :** C'est ce qui fait passer l'ETL de "fonctionnel" à "robuste" et "maintenable".
    * `etl_runs` : Trace chaque exécution (quand, statut `SUCCESS` ou `FAILED`).
    * `etl_events` : Nos fonctions `log_event()` y écrivent des logs. Si ça plante, on sait où et pourquoi (`SQLERRM`).
    * `etl_metrics` : On capture le nombre de lignes traitées.
    * Chaque fonction ETL est dans un bloc `BEGIN ... EXCEPTION ... END` pour attraper les erreurs et les logger avant de planter.

## 3. Choix d'Optimisation & Performance

L'objectif était d'accélérer les "requêtes analytiques" du script `06_analytics.sql`.

### Stratégie d'Indexation (Comparaison)

On a utilisé 3 types d'index différents.

1.  **Index B-Tree (standard) :**
    * **Choix :** Sur toutes les clés étrangères (FK) de `fact_sales` (ex: `idx_fact_sales_date`).
    * **Justification :** C'est le minimum obligatoire. Ça accélère les `JOIN` entre les faits et les dimensions, qui sont la base de *toutes* les requêtes.
2.  **Index Composites (B-Tree) :**
    * **Choix :** Ex: `idx_fact_sales_date_product` sur `(date_key, product_key)`.
    * **Justification :** Beaucoup de requêtes filtrent sur plusieurs colonnes (ex: "ventes de tel produit *à telle date*"). Un index composite est bien plus rapide qu'un index sur chaque colonne séparément.
3.  **Index BRIN (Avancé) :**
    * **Choix :** Sur `date_key` et `transaction_id` dans `fact_sales`.
    * **Justification :** C'est un choix spécifique aux DWH. Un index B-Tree sur 100k+ lignes triées (comme les dates) est lourd. Un index **BRIN** est très léger (il stocke min/max par bloc). Comme nos données sont triées par date, il permet à PostgreSQL d'ignorer 99% de la table lors d'un filtre sur une plage de dates. Le coût est minime pour un gain énorme.

### Couche d'Agrégation (`marts`)

* **Choix :** On a créé un schéma `marts` pour y mettre des **Vues Matérialisées** (ex: `mv_monthly_sales_country`).
* **Justification :** C'est une optimisation majeure pour les analystes et les dashboards.
    * Le `dwh` contient la donnée brute, parfaite pour les analyses complexes (cohortes, RFM). Mais il est *lent* pour des questions simples (ex: "CA total par mois").
    * Les `marts` contiennent ces agrégats pré-calculés. Une requête sur `marts.mv_monthly_sales_country` est **instantanée**.
    * **Processus :** L'ETL (`run_full_etl`) charge le `dwh`, puis on appelle `refresh_all_marts()` pour mettre à jour ces agrégats. C'est une séparation claire des responsabilités.