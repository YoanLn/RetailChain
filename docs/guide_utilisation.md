# Guide d'utilisation du Data Warehouse RetailChain

Ce document explique comment installer, charger et utiliser le data warehouse.

## 1. Prérequis

* PostgreSQL version 16 ou supérieure.

## 2. Installation (Mise en place initiale)

Pour construire le data warehouse de A à Z, il faut exécuter les scripts SQL du dossier `/sql` **une seule fois**, et **dans l'ordre suivant** :

1.  `01_setup.sql`
    * **Action :** Crée les trois schémas (`staging`, `dwh`, `marts`).
2.  `02_create_tables.sql`
    * **Action :** Crée toutes les tables (dimensions et faits) dans le schéma `dwh`, avec les index de base et les index partiels pour le SCD2.
3.  `03_sample_data.sql`
    * **Action :** Crée les tables `_raw` dans le schéma `staging` et insère les 100 000+ lignes de données de test. Il peuple aussi la `dim_date`.
4.  `04_etl_functions.sql`
    * **Action :** **Définit** toutes les fonctions PL/pgSQL nécessaires pour l'ETL (monitoring, gestion des SCD Type 1 & 2, et la fonction principale `dwh.run_full_etl()`).
5.  `05_optimizations.sql`
    * **Action :** Crée les optimisations de performance : index composites, index BRIN, et les vues matérialisées (`marts`). Il définit aussi la fonction `dwh.refresh_all_marts()`.

À la fin de cette étape, la structure est en place, mais **le DWH est encore vide**.

## 3. Utilisation (Chargement des données)

Une fois l'installation faite, on peut charger les données.

Ce processus est en **deux étapes** qu'il faut toujours lancer dans cet ordre. On utilise les fonctions qu'on a créées à l'étape d'installation.

```sql
-- Étape 1: Lancer l'ETL principal
-- (Prend les données de 'staging' et charge 'dwh' en gérant les SCD)
SELECT dwh.run_full_etl();

-- Étape 2: Rafraîchir les vues matérialisées
-- (Met à jour les agrégats pré-calculés dans 'marts')
SELECT dwh.refresh_all_marts();
```

Après avoir lancé ces deux commandes, le DWH est chargé et prêt pour l'analyse.

## 4. Analyse (Exemples de requêtes)

Le script `06_analytics.sql` n'est **pas un script à exécuter** d'un coup.

C'est un fichier qui contient 12 exemples de requêtes métier pour interroger le data warehouse et répondre aux objectifs analytiques.

On y trouve deux types de requêtes :
* **Requêtes sur les `marts` :** Pour les analyses simples et rapides (ex: CA total par pays). Elles sont quasi-instantanées.
* **Requêtes sur le `dwh` :** Pour les analyses complexes et ad-hoc qui demandent la donnée brute (ex: cohortes, RFM, saisonnalité).

## 5. Suivi de l'ETL (Monitoring)

On a mis en place un système de monitoring simple. Pour voir si les chargements se sont bien passés, on peut interroger la table `dwh.etl_runs` :

```sql
-- Voir les 5 derniers chargements (ETL ou refresh de marts)
SELECT 
    run_id, 
    status, 
    started_at, 
    ended_at, 
    error_message
FROM dwh.etl_runs 
ORDER BY started_at DESC 
LIMIT 5;
```