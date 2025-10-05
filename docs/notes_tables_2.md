# Notes détaillées sur les tables du Data Warehouse

Ces notes servent à expliquer les choix de conception et les colonnes ajoutées pour analyses avancées.

---

## 1️⃣ dim_date – Dimension Temps

**Objectif :** Fournir toutes les informations temporelles nécessaires pour analyses commerciales et tendances.

| Colonne       | Description / Utilité |
|---------------|---------------------|
| `date_key`    | Identifiant unique de la date (YYYYMMDD), utilisé pour les jointures avec `fact_sales`. |
| `full_date`   | Date complète pour reporting. |
| `year_number` | Regroupement par année pour analyses annuelles. |
| `month_number` / `month_name` | Analyse mensuelle des ventes et saisonnalité. |
| `quarter_number` | Suivi des performances trimestrielles. |
| `day_of_week` | Permet analyse par jour de la semaine (0=dimanche). |
| `day_name`    | Nom du jour pour reporting lisible (Lundi, Mardi…). |
| `is_weekend`  | Identifier week-ends pour comparer comportements d’achat. |
| `week_number` | Analyse hebdomadaire pour suivre tendances rapides. |
| `is_holiday`  | Identifier jours fériés pour mesurer impact sur les ventes. |

**Note pour documentation :**  
> La dimension `dim_date` enrichie avec `week_number`, `day_name` et `is_holiday` permet d’effectuer des analyses avancées sur tendances saisonnières et impact des jours particuliers.

---

## 2️⃣ dim_customer – Dimension Client

**Objectif :** Historiser les clients et permettre analyses démographiques et comportementales.

| Colonne              | Description / Utilité |
|----------------------|---------------------|
| `customer_key`       | Identifiant unique interne. |
| `customer_business_key` | Identifiant métier du client. |
| `first_name` / `last_name` | Pour reporting et segmentation. |
| `country`            | Analyse par pays. |
| `email`              | Pour campagnes marketing et segmentation. |
| `gender`             | Pour analyses démographiques. |
| `birth_date`         | Permet segmentation par tranche d’âge. |
| `loyalty_level`      | Indique niveau de fidélité, utile pour analyses RFM. |
| `valid_from`         | SCD Type 2 → date début validité de la ligne. |
| `valid_to`           | SCD Type 2 → date fin validité, pour historisation. |
| `is_current`         | SCD Type 2 → indique si la ligne est active. |

**Note pour documentation :**  
> `dim_customer` utilise SCD Type 2 pour historiser les changements de données clients (ex: changement de pays ou email). Les colonnes analytiques permettent segmentations et analyses comportementales.

---

## 3️⃣ dim_store – Dimension Magasin

**Objectif :** Permettre analyses géographiques et par type de magasin.

| Colonne        | Description / Utilité |
|----------------|---------------------|
| `store_key`    | Identifiant interne unique. |
| `store_business_key` | Identifiant métier du magasin. |
| `store_name`   | Nom du magasin. |
| `city` / `country` | Localisation pour analyses géographiques. |
| `store_type`   | Type de magasin (flagship, outlet…) pour comparer performances. |
| `region`       | Analyse par région au sein du pays. |

**Note pour documentation :**  
> Les colonnes `store_type` et `region` permettent d’identifier les magasins les plus performants par catégorie et localisation.

---

## 4️⃣ dim_product – Dimension Produit

**Objectif :** Suivre produits, catégories, marque et informations financières.

| Colonne         | Description / Utilité |
|-----------------|---------------------|
| `product_key`   | Identifiant interne unique. |
| `product_business_key` | Identifiant métier du produit. |
| `product_name`  | Nom du produit. |
| `category` / `subcategory` | Analyse par catégorie et sous-catégorie. |
| `brand`         | Analyse par marque pour études marketing. |
| `unit_cost`     | Coût unitaire, pour calculer marge. |
| `margin`        | Marge estimée ou réelle, pour performance financière. |
| `valid_from`    | SCD Type 2 → date début validité du produit. |
| `valid_to`      | SCD Type 2 → date fin validité. |
| `is_current`    | SCD Type 2 → ligne active ou historique. |

**Note pour documentation :**  
> `dim_product` peut historiser les changements (prix, catégorie), et contient des colonnes financières et marketing pour analyses avancées.

---

## 5️⃣ fact_sales – Table de faits Ventes

**Objectif :** Stocker toutes les transactions, quantités, prix et montants totaux.

| Colonne        | Description / Utilité |
|----------------|---------------------|
| `sales_key`    | Identifiant interne unique. |
| `date_key`     | FK → `dim_date`, analyse temporelle. |
| `customer_key` | FK → `dim_customer`, analyse par client. |
| `store_key`    | FK → `dim_store`, analyse par magasin. |
| `product_key`  | FK → `dim_product`, analyse par produit. |
| `transaction_id` | Identifiant de transaction, unique. |
| `quantity`     | Quantité vendue. |
| `unit_price`   | Prix unitaire. |
| `total_amount` | Montant total = `quantity * unit_price`. |

**Indexes ajoutés :**  
- `date_key`, `customer_key`, `store_key`, `product_key`  
> Permettent de **rapidement filtrer et agréger** les ventes par dimension.  

**Note pour documentation :**  
> `fact_sales` centralise toutes les transactions pour analyses par période, client, magasin et produit. Les indexes améliorent la performance des requêtes analytiques.

---

## 💡 Astuce pour la documentation finale

- Ces notes peuvent être **copiées directement** dans `choix_techniques.md` ou `architecture.md`.  
- Chaque colonne est **justifiée**, ce qui montre au prof que tu maîtrises les choix de modélisation et la logique analytique.
