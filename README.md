# Projet Data Warehouse RetailChain (PostgreSQL)

## 1. Description du projet

Ce projet a été réalisé dans le cadre du cours de Data Warehouse. L'objectif était de construire un data warehouse complet pour une chaîne de magasins fictive, *RetailChain*, afin d'analyser ses performances commerciales sur deux ans.

Le projet inclut :
* Un schéma en étoile (`dwh`) avec gestion de l'historique (SCD Type 1 et Type 2).
* Des processus ETL robustes en PL/pgSQL pour charger les données.
* Un système de monitoring et de logs pour l'ETL.
* Des optimisations de performance (Index BRIN, vues matérialisées).
* Des requêtes analytiques complexes (Cohortes, RFM, etc.).

## 2. Contexte métier

* **Entreprise :** RetailChain (50 magasins, 5 pays)
* **Données :** 1000 clients, 1000 produits, 1 000 000 transactions.
* **Objectifs :** Analyser les ventes, les tendances saisonnières et les performances des magasins.

## 3. Structure du rendu

Le projet respecte la structure de fichiers demandée :
```
NOM_Prenom_ProjetDW/
├── sql/
│   ├── 01_setup.sql
│   ├── 02_create_tables.sql
│   ├── 03_sample_data.sql
│   ├── 04_etl_functions.sql
│   ├── 05_optimizations.sql
│   └── 06_analytics.sql
├── docs/
│   ├── architecture.md
│   ├── choix_techniques.md
│   └── guide_utilisation.md
└── README.md
```

## 4. Comment l'utiliser ?

Pour lancer le projet de A à Z :

### Étape 1 : Installation (1 seule fois)

Exécutez les scripts `01` à `05` dans l'ordre pour créer la structure et les fonctions :
1.  `01_setup.sql`
2.  `02_create_tables.sql`
3.  `03_sample_data.sql`
4.  `04_etl_functions.sql`
5.  `05_optimizations.sql`

*(À ce stade, le DWH est construit mais encore vide)*

### Étape 2 : Lancement de l'ETL (Chargement des données)

Pour charger les 1 000 000 transactions du `staging` vers le `dwh` et mettre à jour les rapports, lancez les deux commandes suivantes :

```sql
-- 1. Charger les dimensions et les faits
SELECT dwh.run_full_etl();

-- 2. Mettre à jour les vues matérialisées pour les rapports
SELECT dwh.refresh_all_marts();
```

Le DWH est maintenant complet et prêt pour l'analyse.

### Étape 3 : Analyse

Le script `06_analytics.sql` contient de nombreux exemples de requêtes (RFM, Cohortes, etc.) prêtes à être lancées pour analyser les données.

## 5. Technologies utilisées

* SGBD : PostgreSQL 16+
* Langage ETL : PL/pgSQL