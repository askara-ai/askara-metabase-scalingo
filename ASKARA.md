# Askara Metabase - Documentation

## Architecture

Cette instance Metabase utilise une copie de la base de données de production Askara pour générer des dashboards analytics sans impacter les performances de production.

### Bases de données

- **`molia_symfo_8824`** : Base de données configurée dans Metabase (copie de prod)
- Les données sont importées depuis un backup de la production Askara

### Structure des données analytics

1. **Vues SQL** (`view_api_usage_*`) : Définies dans les migrations Symfony, importées avec le dump prod
2. **Tables matérialisées** (`mat_api_usage_*`) : Snapshots des vues pour des requêtes instantanées

Les vues sont lentes (~2 minutes) car elles font des agrégations sur toute la table `api_usage`. Les tables matérialisées sont des copies statiques qui permettent des requêtes instantanées.

## Tables matérialisées disponibles

| Table | Description |
|-------|-------------|
| `mat_api_usage_organization_costs_summary` | Coûts par organisation (30 derniers jours) |
| `mat_api_usage_top_users_by_cost` | Top 100 utilisateurs par coût |
| `mat_api_usage_daily_costs` | Évolution des coûts journaliers (90 jours) |
| `mat_api_usage_ai_model` | Distribution par modèle IA |
| `mat_api_usage_cost_per_document` | Coût par type de document |
| `mat_api_usage_stt_quality_costs` | Qualité STT vs coût |
| `mat_api_usage_ocr_success_costs` | Taux de succès OCR |
| `mat_api_usage_monthly_cost_comparison` | Comparaison mensuelle (12 mois) |

## Problème JSON 'null' et solution NULLIF

### Le problème

Quand MySQL extrait une valeur JSON `null` avec `JSON_UNQUOTE(JSON_EXTRACT(...))`, il retourne la **string `'null'`** (4 caractères), pas un vrai SQL `NULL`.

```sql
-- Ceci échoue avec "Truncated incorrect INTEGER value: 'null'"
SELECT CAST(JSON_UNQUOTE(JSON_EXTRACT('{"tokens": null}', '$.tokens')) AS SIGNED);
-- Retourne la string 'null', pas NULL
```

### La solution

Utiliser `NULLIF` pour convertir la string `'null'` en vrai `NULL` avant le `CAST` :

```sql
-- Pattern correct
COALESCE(
    SUM(
        CAST(
            NULLIF(NULLIF(JSON_UNQUOTE(JSON_EXTRACT(operation_metadata, '$.input_tokens')), 'null'), '')
            AS SIGNED
        )
    ),
    0
) as total_input_tokens
```

- `NULLIF(..., 'null')` : Convertit la string `'null'` en SQL `NULL`
- `NULLIF(..., '')` : Convertit les strings vides en SQL `NULL`
- `COALESCE(..., 0)` : Remplace les `NULL` finaux par 0

### Vues concernées

Les vues suivantes utilisent ce pattern (dans `create-materialized-tables.sql`) :
- `view_api_usage_organization_costs_summary` (views 1) : input_tokens, output_tokens, duration_ms
- `view_api_usage_ai_model` (view 4) : input_tokens, output_tokens
- `view_api_usage_stt_quality_costs` (view 6) : quality_score, words_count, duration_ms

## Rafraîchir les données

### Méthode automatique (cron)

Un cron job est configuré pour importer automatiquement les données. Voir `cron.json`.

### Méthode manuelle

```bash
# Via Scalingo CLI
scalingo --region osc-fr1 --app askara-metabase run bash /app/scripts/database-import.sh

# Ou juste les tables matérialisées (sans ré-importer le dump)
scalingo --region osc-fr1 --app askara-metabase mysql-console < scripts/create-materialized-tables.sql
```

### Via mysql-console directement

```bash
scalingo --region osc-fr1 --app askara-metabase mysql-console <<'EOF'
USE molia_symfo_8824;
-- Rafraîchir une table spécifique
TRUNCATE TABLE mat_api_usage_organization_costs_summary;
INSERT INTO mat_api_usage_organization_costs_summary
SELECT * FROM view_api_usage_organization_costs_summary;
EOF
```

## Troubleshooting

### Erreur "Truncated incorrect INTEGER value: 'null'"

Les vues dans la base importée n'ont pas le fix NULLIF. Il faut :
1. Soit ré-exécuter `create-materialized-tables.sql` qui contient les vues corrigées
2. Soit déployer la migration sur production et ré-importer le dump

### Erreur "429 Too Many Requests"

Scalingo limite à 10 conteneurs one-off simultanés. Solutions :
- Attendre que les conteneurs précédents se terminent
- Regrouper les commandes SQL dans un seul script

### Tables non visibles dans Metabase

1. Vérifier que les tables sont dans la bonne base (`molia_symfo_8824`)
2. Dans Metabase : Admin > Databases > Sync database schema

### Vérifier l'état des tables

```bash
scalingo --region osc-fr1 --app askara-metabase mysql-console <<'EOF'
USE molia_symfo_8824;
SHOW TABLES LIKE 'mat_%';
SELECT 'org_costs' as tbl, COUNT(*) as cnt FROM mat_api_usage_organization_costs_summary
UNION ALL SELECT 'top_users', COUNT(*) FROM mat_api_usage_top_users_by_cost
UNION ALL SELECT 'daily_costs', COUNT(*) FROM mat_api_usage_daily_costs
UNION ALL SELECT 'ai_model', COUNT(*) FROM mat_api_usage_ai_model
UNION ALL SELECT 'cost_per_doc', COUNT(*) FROM mat_api_usage_cost_per_document
UNION ALL SELECT 'stt_quality', COUNT(*) FROM mat_api_usage_stt_quality_costs
UNION ALL SELECT 'ocr_success', COUNT(*) FROM mat_api_usage_ocr_success_costs
UNION ALL SELECT 'monthly_comp', COUNT(*) FROM mat_api_usage_monthly_cost_comparison;
EOF
```

## Variables d'environnement requises

| Variable | Description |
|----------|-------------|
| `SCALINGO_API_TOKEN` | Token API Scalingo pour télécharger les backups |
| `SCALINGO_SOURCE_APP` | App source (ex: `askara-symfony`) |
| `SCALINGO_ADDON_KIND` | Type d'addon (ex: `mysql`) |
| `METABASE_ASKARA_DB_USER` | User MySQL |
| `METABASE_ASKARA_DB_PASSWORD` | Password MySQL |
| `METABASE_ASKARA_DB_HOST` | Host MySQL |
| `METABASE_ASKARA_DB_PORT` | Port MySQL |
| `METABASE_ASKARA_DB_NAME` | Nom de la base (ex: `molia_symfo_8824`) |

## Liens utiles

- [Askara Symfony (source)](https://github.com/askara-ai/askara-symfony)
- [Migration des vues](../askara-symfony/migrations/Version20251205151700.php)
- [Scalingo MySQL docs](https://doc.scalingo.com/databases/mysql)
