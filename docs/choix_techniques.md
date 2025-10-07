# Documentation technique – Scripts principaux

## 1. `02_create_tables.sql` – Schéma du Data Warehouse

### Objectif
Ce script définit la structure du Data Warehouse (DWH) en respectant un modèle en étoile.  
Il crée les dimensions principales (`dim_date`, `dim_customer`, `dim_store`, `dim_product`) et la table de faits (`fact_sales`).

### Choix de modélisation
- **Modèle en étoile** : adapté aux analyses OLAP, simple et performant pour les jointures.
- **Dimensions enrichies** : ajout de colonnes utiles (email, genre, marque, prix catalogue, etc.) pour permettre des analyses marketing et commerciales plus fines.
- **Gestion des SCD Type 2** : intégrée directement dans le schéma via les colonnes `valid_from`, `valid_to`, `is_current` et des index partiels garantissant l’unicité uniquement sur les enregistrements courants.
- **Contraintes d’intégrité** : clés primaires et étrangères pour assurer la cohérence des données.
- **Fact table** : contrainte d’unicité `(transaction_id, product_key)` pour éviter les doublons.

### Optimisations
- Index sur les clés étrangères de la table de faits.
- Index supplémentaires sur les colonnes de filtrage fréquentes (pays, région, catégorie).
- Index partiels pour la gestion des SCD.

---

## 2. `03_sample_data.sql` – Génération de données de test

### Objectif
Ce script génère des données de test réalistes pour valider le modèle et tester les performances.  
Les données sont insérées dans la **zone staging** et non directement dans le DWH, afin de respecter la logique ETL.

### Structure staging
- `staging.customers_raw` : 1000 clients avec informations personnelles (nom, email, genre, pays, ville, date de naissance).
- `staging.stores_raw` : 50 magasins répartis dans 5 pays européens, avec type et date d’ouverture.
- `staging.products_raw` : 1000 produits avec marque, catégorie, sous-catégorie et prix catalogue.
- `staging.sales_raw` : 100 000 transactions simulées, avec quantités, prix unitaires, remises et montants totaux.

### Particularité
La dimension Date est directement alimentée dans `dwh.dim_date` via la fonction fournie par l’enseignant (`populate_test_date`).

---

## 3. `04_etl_functions.sql` – Processus ETL

### Objectif
Ce script implémente le processus ETL (Extract, Transform, Load) pour charger les données de la zone staging vers le DWH.  
Il inclut également un système de monitoring et de métriques pour assurer la robustesse et la traçabilité.

### Étapes du processus
1. **Extract** : lecture des données brutes depuis les tables staging.
2. **Transform** : nettoyage, mapping des clés de substitution, gestion des doublons.
3. **Load** : insertion dans les dimensions et la table de faits du DWH.

### Monitoring et métriques
- Table `etl_runs` : suivi des exécutions (statut, début, fin, erreurs éventuelles).
- Table `etl_events` : journalisation des événements (étape, niveau, message).
- Table `etl_metrics` : enregistrement de métriques (nombre d’insertions, mises à jour, etc.).

### Gestion des dimensions
- **Customer et Product** : upsert avec `ON CONFLICT DO UPDATE`. La gestion des SCD est assurée par la structure du schéma (index partiels).
- **Store** : gestion en Type 1 (mise à jour simple).
- **Date** : déjà alimentée par la fonction fournie.

### Gestion de la fact table
- Chargement des transactions avec jointure sur les dimensions.
- Dédoublonnage via la contrainte `(transaction_id, product_key)`.

---

## Conclusion
Ces trois scripts constituent la base du projet :
- `02_create_tables.sql` définit un schéma robuste et compatible avec la gestion des SCD.
- `03_sample_data.sql` fournit des données de test réalistes dans la zone staging.
- `04_etl_functions.sql` assure un processus ETL complet, traçable et robuste, avec monitoring et métriques.  

---