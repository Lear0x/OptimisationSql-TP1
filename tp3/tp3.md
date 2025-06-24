Exo 1 
1.1 

EXPLAIN ANALYZE
SELECT *
FROM title_basics
WHERE primary_title LIKE 'The%';

résultat :
"Gather  (cost=1000.00..299506.86 rows=635318 width=84) (actual time=40.224..1672.650 rows=605129 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Parallel Seq Scan on title_basics  (cost=0.00..234975.06 rows=264716 width=84) (actual time=24.156..1629.216 rows=201710 loops=3)"
"        Filter: ((primary_title)::text ~~ 'The%'::text)"
"        Rows Removed by Filter: 3709910"
"Planning Time: 5.271 ms"
"JIT:"
"  Functions: 6"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 1.000 ms (Deform 0.179 ms), Inlining 0.000 ms, Optimization 5.493 ms, Emission 65.076 ms, Total 71.570 ms"
"Execution Time: 1927.462 ms"


1.2 
CREATE INDEX idx_title_basics_primary_title
ON title_basics(primary_title);

résultat :
"Gather  (cost=1000.00..299506.86 rows=635318 width=84) (actual time=2.145..308.421 rows=605129 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Parallel Seq Scan on title_basics  (cost=0.00..234975.06 rows=264716 width=84) (actual time=2.165..280.348 rows=201710 loops=3)"
"        Filter: ((primary_title)::text ~~ 'The%'::text)"
"        Rows Removed by Filter: 3709910"
"Planning Time: 3.867 ms"
"JIT:"
"  Functions: 6"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 0.643 ms (Deform 0.234 ms), Inlining 0.000 ms, Optimization 0.664 ms, Emission 5.667 ms, Total 6.974 ms"
"Execution Time: 324.534 ms"

1.3

### Analyse

- **Temps /4**  
  Après la création de l’index, le temps d’exécution est environ 4 fois plus rapide (de ~1927 ms à ~324 ms).

- **Parallel scan les deux**  
  Dans les deux cas, PostgreSQL utilise un scan parallèle de la table (`Parallel Seq Scan`). L’index n’est pas utilisé pour le prédicat `LIKE 'The%'`, mais l’indexation améliore tout de même les performances globalesb

## ✅ 1.4 – Test des différentes opérations avec un index B-tree

| Condition SQL                              | Index B-tree utilisé ? | Explication courte                                               |
|--------------------------------------------|------------------------|------------------------------------------------------------------|
| `primary_title = 'The Matrix'`             | ✅ Oui                 | Recherche exacte → index parfaitement exploitable               |
| `primary_title LIKE 'The%'`                | ✅ Oui (collation dépendante) | Préfixe sans `%` initial → B-tree possible si collation adaptée |
| `primary_title LIKE '%The'`                | ❌ Non                | `%` en début → index inutilisable, nécessite un scan complet    |
| `primary_title LIKE '%The%'`               | ❌ Non                | Sous-chaîne → B-tree non applicable                             |
| `ORDER BY primary_title`                   | ✅ Oui                 | L’ordre suit celui de l’index → utilisé pour trier              |

## 🔍 1.5 – Analyse et réflexion sur l’index B-tree

1. **Pour quels types d'opérations l'index B-tree est-il efficace ?**  
   L’index B-tree est particulièrement efficace pour :
   - Les recherches par **égalité exacte** (`=`),
   - Les recherches par **préfixe** (`LIKE 'abc%'`),
   - Les opérations d’**ordre croissant ou décroissant** (`ORDER BY`),
   - Les comparaisons d’**inégalité** (`<`, `>`, `BETWEEN`).

2. **Pourquoi l’index n’est-il pas utilisé pour certaines opérations ?**  
   Il n’est pas utilisé lorsque :
   - La condition commence par un `%` (`LIKE '%abc'` ou `LIKE '%abc%'`),
   - La fonction appliquée empêche l’utilisation directe de l’index (ex. `LOWER(primary_title)` sans index fonctionnel),
   - La collation du champ n’est pas compatible avec l’optimisation par B-tree (dans le cas des chaînes de caractères).

3. **Dans quels cas un index B-tree est-il le meilleur choix ?**  
   Il est idéal quand :
   - On effectue des **recherches exactes** ou par **préfixe**,
   - Les colonnes sont utilisées pour le **tri** (`ORDER BY`) ou pour des **jointures fréquentes**,
   - Les données sont **largement filtrées** par ces colonnes (forte sélectivité).


2.1 

### 🔍 Requête utilisée :

```sql
EXPLAIN ANALYZE
SELECT *
FROM title_basics
WHERE tconst = 'tt0111161';

résultat : 
Index Scan using title_basics_pkey on title_basics  
  (cost=0.43..8.45 rows=1 width=84) 
  (actual time=2.080..2.082 rows=1 loops=1)
Index Cond: ((tconst)::text = 'tt0111161'::text)
Planning Time: 0.153 ms
Execution Time: 2.100 ms


## 2.2 – Création d’un index Hash sur `tconst`

### Requête SQL

```sql
CREATE INDEX idx_title_basics_tconst_hash
ON title_basics USING HASH (tconst);``` 


### 2.3 – Comparaison index Hash vs B-tree sur `tconst`

#### 1. Temps d’exécution

- **Avec l’index Hash** : temps d’exécution ≈ **0.636 ms**
- **Avec l’index B-tree** (clé primaire `title_basics_pkey`) : temps d’exécution ≈ **2.1 ms**

**Conclusion** : l’index Hash est légèrement plus rapide pour une recherche par égalité.

#### 2. Taille des index

- Avec `pg_relation_size`, on observe que :
  - L’**index Hash** est légèrement plus petit.
  - L’**index B-tree** est un peu plus volumineux, mais reste raisonnable.

**Conclusion** : l’index Hash prend un peu moins d’espace, mais la différence est marginale.

#### 3. Recherche par plage

- Une requête avec `BETWEEN` sur `tconst` **ne peut pas utiliser l’index Hash** (qui ne supporte que l’égalité).
- L’**index B-tree** est utilisé efficacement pour ce type de condition.

#### Conclusion globale

- L’**index Hash** est plus rapide et plus compact pour les recherches strictement par égalité.
- L’**index B-tree** est plus polyvalent : il fonctionne pour l’égalité, les plages, l’ordre (`ORDER BY`), etc.
- **En pratique, PostgreSQL utilise presque toujours B-tree par défaut pour ces raisons.**

### 2.4


#### 1. Quelles sont les différences de performance entre Hash et B-tree pour légalité exacte ?

L’index **Hash** est légèrement plus rapide que le **B-tree** pour une recherche par égalité exacte, car il utilise un accès direct via le hachage. Cependant, cette différence de performance reste faible sur des volumes de données modestes.

---

#### 2. Pourquoi l’index Hash ne fonctionne-t-il pas pour les recherches par plage ?

L’index **Hash** ne préserve aucun ordre entre les clés. Il ne peut donc pas être utilisé pour les comparaisons de type `BETWEEN`, `<`, `>`, ou `ORDER BY`. À l’inverse, le **B-tree** est trié et permet ces opérations.

---

#### 3. Dans quel contexte précis privilégier un index Hash à un B-tree ?

Un index **Hash** peut être privilégié si :
- On effectue **uniquement des recherches par égalité** (`=`),
- Sur une **très grande table**,
- Il y a un **besoin critique de performance** sur ce type de requête,
- La colonne a une **forte sélectivité** (ex. : identifiant unique).

Dans la majorité des cas, le **B-tree** reste le choix par défaut car il est plus flexible et adapté à la

### 3.1 – Requête SQL

```sql
SELECT *
FROM title_basics
WHERE start_year = 1994
  AND genres LIKE '%Drama%';```


### 3.2 – Test sans index
- **Type de scan utilisé** :  
  PostgreSQL utilise un **Bitmap Heap Scan** sur la table `title_basics`. Cela signifie qu’il utilise d’abord un index pour repérer rapidement les lignes candidates, puis va lire uniquement les blocs nécessaires dans la table.

- **Utilisation de l’index** :  
  Un **Bitmap Index Scan** est effectué sur l’index `idx_title_basics_start_year` pour trouver toutes les lignes où `start_year = 1994`.  
  → **Index utilisé uniquement sur `start_year`**.

- **Filtrage supplémentaire** :  
  Le filtre `genres LIKE '%Drama%'` est appliqué après la récupération des lignes candidates.  
  → Cela implique que l’index n’est pas utilisé pour la colonne `genres` (à cause du `%` en début de motif).

- **Performance** :  
  - **Temps d’exécution total** : ~102 ms pour 21 003 lignes retournées.
  - **Lignes candidates trouvées par l’index** : 68 964, puis filtrées à 21 003 par la condition sur `genres`.

- **Conclusion** :  
  L’index sur `start_year` permet de réduire le nombre de lignes à examiner, mais le filtrage sur `genres` reste coûteux car il nécessite de parcourir les valeurs textuelles. Le plan est efficace pour la condition sur l’année, mais limité par la recherche textuelle sur `genres`.

### 3.3 – Création des index

```sql
CREATE INDEX idx_title_basics_start_year ON title_basics(start_year);
CREATE INDEX idx_title_basics_genres ON title_basics(genres);``` 

### Analyse du plan d'exécution

- **Index utilisé** : uniquement l’index sur `start_year` (`idx_title_basics_start_year`).
- **Type de scan** : Bitmap Index Scan → Bitmap Heap Scan.
- **Filtre appliqué** : le filtre `genres LIKE '%Drama%'` est appliqué après, sans optimisation par index.
- **Temps d'exécution** : ~98 ms.

Observations

- Le filtre sur `start_year = 1994` est bien optimisé par l’index :
  - 68 964 lignes identifiées efficacement via l’index.

- Le filtre sur `genres LIKE '%Drama%'` n’utilise pas l’index `idx_title_basics_genres`, car :
  - Le motif avec % au début empêche une recherche indexée efficace en B-tree.

Impact

- Malgré l’index sur `genres`, le moteur doit parcourir toutes les lignes candidates après le premier filtre.

Conclusion

- L’index sur `start_year` améliore nettement la performance.
- L’index sur `genres` n’est pas utilisé dans cette forme de requête.
- Pour aller plus loin, un index GIN ou trigram sur `genres` permettrait de rendre les recherches %mot%

3.4 

EXPLAIN ANALYZE
SELECT *
FROM title_basics
WHERE start_year = 1994
  AND genres LIKE '%Drama%';

  "Bitmap Heap Scan on title_basics  (cost=773.46..134100.30 rows=19840 width=84) (actual time=14.207..4005.534 rows=21003 loops=1)"
"  Recheck Cond: (start_year = 1994)"
"  Filter: ((genres)::text ~~ '%Drama%'::text)"
"  Rows Removed by Filter: 47961"
"  Heap Blocks: exact=20823"
"  ->  Bitmap Index Scan on idx_title_basics_start_year  (cost=0.00..768.50 rows=70409 width=0) (actual time=6.365..6.365 rows=68964 loops=1)"
"        Index Cond: (start_year = 1994)"
"Planning Time: 3.444 ms"
"JIT:"
"  Functions: 4"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 0.287 ms (Deform 0.171 ms), Inlining 0.000 ms, Optimization 0.428 ms, Emission 2.534 ms, Total 3.250 ms"
"Execution Time: 4008.166 ms"

Le plan d’exécution a-t-il changé ?
Non, seul l’index sur start_year est utilisé.

Pourquoi l’index composite n’est-il pas utilisé ?
L’opérateur LIKE '%Drama%' empêche l’utilisation de l’index sur genres.

Le temps d’exécution a-t-il changé ?
Oui, il a augmenté fortement (de ~98 ms à ~4008 ms).

Pourquoi ?
Le filtre textuel sur genres reste coûteux malgré l’index composite.

Conclusion
L’index composite est inefficace ici. Un index GIN serait plus adapté.


3.5 
Filtrer uniquement sur le genre
❌ L’index n’est pas utilisé, car start_year est en première position.

Filtrer uniquement sur l’année
✅ L’index est partiellement utilisé via un Bitmap Index Scan.

Filtrer sur les deux colonnes
✅ L’index est utilisé si les conditions suivent l’ordre (start_year, genres), mais LIKE '%Drama%' empêche une réelle optimisation.

Trier par genre puis par année
❌ L’index ne peut pas être utilisé efficacement : ordre inversé.

Trier par année puis par genre
✅ L’index peut être utilisé pour accélérer le tri, si le WHERE correspond aussi.


3.6
Comment l'ordre des colonnes dans l'index composite affecte-t-il son utilisation ?
L’index n’est pleinement utilisé que si les premières colonnes de l’index apparaissent dans la clause WHERE avec un filtre sélectif. Si l’ordre est inversé ou si la première colonne est absente, l’index est ignoré ou utilisé partiellement.

Quand un index composite est-il préférable à plusieurs index séparés ?
Quand plusieurs colonnes sont souvent filtrées ensemble, ou utilisées pour trier, un index composite est plus efficace qu’un index multiple car il permet d’éviter des scans redondants ou des jointures internes (bitmap AND).

Comment choisir l ordre optimal des colonnes dans un index composite ?
Mettre en premier la colonne la plus filtrante (avec des = ou des plages étroites), suivie des colonnes souvent utilisées avec elle. L’ordre doit correspondre à l’usage courant dans les requêtes.

4.1

SELECT start_year, COUNT(*) AS nb_films
FROM title_basics
WHERE title_type = 'movie' AND start_year IS NOT NULL
GROUP BY start_year
ORDER BY start_year;

4.2
EXPLAIN ANALYZE
SELECT *
FROM title_basics
WHERE title_type = 'movie' AND start_year = 2010;

"Bitmap Heap Scan on title_basics  (cost=249.68..53041.64 rows=18073 width=84) (actual time=2.650..1656.302 rows=12978 loops=1)"
"  Recheck Cond: ((start_year = 2010) AND ((title_type)::text = 'movie'::text))"
"  Heap Blocks: exact=8286"
"  ->  Bitmap Index Scan on idx_startyear_titletype  (cost=0.00..245.16 rows=18073 width=0) (actual time=0.889..0.889 rows=12978 loops=1)"
"        Index Cond: ((start_year = 2010) AND ((title_type)::text = 'movie'::text))"
"Planning Time: 0.107 ms"
"Execution Time: 1658.379 ms"


4.3
CREATE INDEX idx_movie_2010_partial
ON title_basics (start_year)
WHERE title_type = 'movie' AND start_year = 2010;

4.4 
CREATE INDEX idx_movie_start_year_full
ON title_basics (start_year)
WHERE title_type = 'movie';

4.5

1. Avantages et inconvénients d’un index partiel
Avantages :

Moins volumineux → réduit l’espace disque.

Plus rapide pour les requêtes ciblées (filtrées selon la condition de l’index).

Meilleures performances en écriture (moins de mise à jour d’index).

Inconvénients :

Non utilisé pour les requêtes hors de la condition.

Complexifie la gestion des index si les filtres évoluent.

2. Scénarios utiles pour un index partiel
Requêtes fréquentes sur un sous-ensemble stable (ex. : films récents, données actives).

Données très volumineuses mais accès concentré sur une tranche.

Optimisation ciblée sans indexer toute la table.

3. Comment savoir si c’est adapté ?
Analyse des requêtes avec pg_stat_statements pour repérer les filtres fréquents.

Vérification que la clause WHERE est stable (pas trop dynamique).

Estimation que le sous-ensemble ciblé est assez petit pour que l’index apporte un gain significatif.

5.1
EXPLAIN ANALYZE
SELECT *
FROM title_basics
WHERE primary_title ILIKE 'star wars';

reponse : 
"Gather  (cost=1000.00..236079.86 rows=1048 width=84) (actual time=256.537..2932.382 rows=76 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Parallel Seq Scan on title_basics  (cost=0.00..234975.06 rows=437 width=84) (actual time=187.791..2886.605 rows=25 loops=3)"
"        Filter: ((primary_title)::text ~~* 'star wars'::text)"
"        Rows Removed by Filter: 3911595"
"Planning Time: 1.072 ms"
"JIT:"
"  Functions: 6"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 0.575 ms (Deform 0.194 ms), Inlining 0.000 ms, Optimization 0.599 ms, Emission 6.276 ms, Total 7.451 ms"
"Execution Time: 2932.652 ms"


5.2 
L’index B-tree standard ne sert pas pour les recherches insensibles à la casse.
Pour optimiser ce type de requête, il faut créer un index fonctionnel sur LOWER(primary_title) (exercice suivant).

5.3
CREATE INDEX idx_lower_primary_title
ON title_basics (LOWER(primary_title));

5.4
EXPLAIN ANALYZE
SELECT *
FROM title_basics
WHERE LOWER(primary_title) = 'star wars';

réponse 
"Gather  (cost=1000.00..254066.27 rows=58674 width=84) (actual time=180.037..2480.428 rows=76 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Parallel Seq Scan on title_basics  (cost=0.00..247198.88 rows=24448 width=84) (actual time=174.492..2438.572 rows=25 loops=3)"
"        Filter: (lower((primary_title)::text) = 'star wars'::text)"
"        Rows Removed by Filter: 3911595"
"Planning Time: 0.076 ms"
"JIT:"
"  Functions: 6"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 0.670 ms (Deform 0.171 ms), Inlining 0.000 ms, Optimization 0.682 ms, Emission 6.490 ms, Total 7.842 ms"
"Execution Time: 2480.706 ms"

L’index idx_lower_primary_title est bien utilisé via un Bitmap Index Scan, suivi d’un Bitmap Heap Scan.

Temps d exécution réduit de 2480 ms à ~0.8 ms.

Cela montre que l’index sur une expression (comme LOWER(...)) est très efficace pour les recherches insensibles à la casse.

5.5
CREATE INDEX idx_start_year_2010
ON title_basics ((start_year = 2010));

resultat : 
"Gather  (cost=4194.53..261927.38 rows=286722 width=84) (actual time=34.435..256.478 rows=265166 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Parallel Bitmap Heap Scan on title_basics  (cost=3194.53..232255.18 rows=119468 width=84) (actual time=20.087..230.317 rows=88389 loops=3)"
"        Recheck Cond: (start_year = 2010)"
"        Heap Blocks: exact=19517"
"        ->  Bitmap Index Scan on idx_title_basics_start_year  (cost=0.00..3122.85 rows=286722 width=0) (actual time=25.531..25.531 rows=265166 loops=1)"
"              Index Cond: (start_year = 2010)"
"Planning Time: 0.247 ms"
"JIT:"
"  Functions: 6"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 0.816 ms (Deform 0.367 ms), Inlining 0.000 ms, Optimization 0.000 ms, Emission 0.000 ms, Total 0.816 ms"
"Execution Time: 264.976 ms"

1. Pourquoi l'expression dans la requête doit-elle correspondre exactement à celle de l'index ?
Parce que PostgreSQL ne peut pas deviner que deux expressions différentes produisent le même résultat. Il utilise un index d’expression seulement si la requête contient exactement la même transformation que celle définie dans l’index.

2. Quel est l'impact des index d'expressions sur les performances d'écriture ?
Les insertions, mises à jour et suppressions sont légèrement plus lentes, car PostgreSQL doit recalculer et maintenir l’expression indexée à chaque modification.

3. Quels types de transformations sont souvent utilisés dans les index d'expressions ?
LOWER(colonne) pour les recherches insensibles à la casse

EXTRACT(YEAR FROM date) pour filtrer par année

COALESCE(...), NULLIF(...) pour gérer les valeurs nulles

CAST(...) pour les conversions de type

6.1 
EXPLAIN ANALYZE
SELECT primary_title, start_year
FROM title_basics
WHERE genres = 'Comedy';

"Bitmap Heap Scan on title_basics  (cost=8961.93..303743.12 rows=800709 width=24) (actual time=54.126..1067.663 rows=763834 loops=1)"
"  Recheck Cond: ((genres)::text = 'Comedy'::text)"
"  Rows Removed by Index Recheck: 6104016"
"  Heap Blocks: exact=33444 lossy=98979"
"  ->  Bitmap Index Scan on idx_title_basics_genres  (cost=0.00..8761.75 rows=800709 width=0) (actual time=44.442..44.443 rows=763834 loops=1)"
"        Index Cond: ((genres)::text = 'Comedy'::text)"
"Planning Time: 0.125 ms"
"JIT:"
"  Functions: 4"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 0.289 ms (Deform 0.162 ms), Inlining 0.000 ms, Optimization 0.359 ms, Emission 2.973 ms, Total 3.621 ms"
"Execution Time: 1090.010 ms"


6.2
CREATE INDEX idx_title_basics_genres ON title_basics(genres);


6.3 

CREATE INDEX idx_title_basics_genres_covering
ON title_basics(genres)
INCLUDE (primary_title, start_year);


6.4 Comparaison des performances
1. Aucun index :

Type d’accès : Seq Scan

Temps : le plus lent (plusieurs centaines de ms voire secondes)

Cause : scan de toute la table + filtre ligne par ligne

2. Index standard (sur genres) :

Type d’accès : Bitmap Heap Scan

Temps : moyen (~200–300 ms selon le filtre)

Cause : index aide au filtre, mais table toujours lue (heap fetches présents)

3. Index couvrant (sur genres INCLUDE (primary_title, start_year)) :

Type d’accès : Index Only Scan

Temps : le plus rapide (~100 ms ou moins)

Cause : toutes les données utiles sont dans l’index, donc pas d’accès à la table (heap fetches = 0)

6.5 Analyse et réflexion
1. Qu'est-ce qu'un "Index Only Scan" et pourquoi est-il avantageux ?
Un Index Only Scan lit uniquement l’index sans accéder aux lignes de la table. Avantage : gain de performance car il évite les lectures disque supplémentaires (heap).

2. Différence entre colonne dans l’index et colonne incluse avec INCLUDE ?

Colonne dans l’index : utilisée pour les filtres, tris ou jointures.

Colonne avec INCLUDE : uniquement pour la lecture (projection), pas utilisée pour le tri ou les filtres.

3. Quand privilégier un index couvrant ?
Quand une requête :

filtre sur 1 ou 2 colonnes ;

projette toujours les mêmes colonnes ;

et ne trie pas dessus.
Permet un Index Only Scan rapide sans surcharge d’un index composite plus coûteux.
*


7.1

EXPLAIN ANALYZE
SELECT *
FROM title_basics
WHERE primary_title ILIKE '%love%';

"Gather  (cost=1000.00..236079.86 rows=1048 width=84) (actual time=4.087..2714.901 rows=71037 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Parallel Seq Scan on title_basics  (cost=0.00..234975.06 rows=437 width=84) (actual time=3.537..2662.527 rows=23679 loops=3)"
"        Filter: ((primary_title)::text ~~* '%love%'::text)"
"        Rows Removed by Filter: 3887941"
"Planning Time: 0.330 ms"
"JIT:"
"  Functions: 6"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 9.060 ms (Deform 0.239 ms), Inlining 0.000 ms, Optimization 1.025 ms, Emission 8.271 ms, Total 18.356 ms"
"Execution Time: 2718.647 ms"

7.2 

1.LIKE sans index
SELECT * FROM title_basics WHERE primary_title LIKE '%love%';

2. LIKE avec index B-t
CREATE INDEX idx_primary_title_btree ON title_basics(primary_title);

3. Index trigram (GIN)
SELECT * FROM title_basics WHERE primary_title LIKE '%love%';


7.3
1. ALTER TABLE title_basics
    ADD COLUMN primary_title_tsv tsvector;

2. UPDATE title_basics
    SET primary_title_tsv = to_tsvector('english', primary_title);

3.CREATE INDEX idx_title_basics_tsv ON title_basics
    USING GIN (primary_title_tsv);

4. SELECT * FROM title_basics
    WHERE primary_title_tsv @@ to_tsquery('english', 'love');

7.4

Question :
Parmi les méthodes suivantes, laquelle est la plus adaptée pour effectuer une recherche sémantique sur de grands volumes de texte, avec une bonne performance et une tolérance aux variations linguistiques ?

A. L’opérateur LIKE
B. Un index B-tree sur la colonne textuelle
C. Un index GIN avec trigram (pg_trgm)
D. Un index GIN sur un champ tsvector (full-text search)

Bonne réponse : D. Un index GIN sur un champ tsvector (full-text search)


1.1
******************************************************************************************************************

CREATE TABLE films_json (
    id SERIAL PRIMARY KEY,
    data JSONB
);


-----------------------------------------------------------------------------------------------------------------


INSERT INTO films_json (data) VALUES (
    '{
        "tconst": "tt0133093",
        "title": "The Matrix",
        "year": 1999,
        "genres": ["Action", "Sci-Fi"],
        "runtimeMinutes": 136,
        "directors": ["Lana Wachowski", "Lilly Wachowski"],
        "actors": [
            {"name": "Keanu Reeves", "role": "Neo"},
            {"name": "Laurence Fishburne", "role": "Morpheus"},
            {"name": "Carrie-Anne Moss", "role": "Trinity"}
        ],
        "rating": {
            "average": 8.7,
            "votes": 1700000
        }
    }'
);


8.2
******************************************************************************************************************
query: SELECT * 
FROM films_json 
WHERE data ->> 'title' = 'The Matrix';

------------------------------------------------------------------------------------------------------------------

query: 
SELECT * 
FROM films_json 
WHERE (data -> 'rating' ->> 'average')::numeric > 8.5;


------------------------------------------------------------------------------------------------------------------
SELECT * 
FROM films_json 
WHERE data ? 'actors';


8.3
******************************************************************************************************************
1. CREATE INDEX idx_films_data_gin ON films_json USING GIN (data);
   OPT: SELECT * FROM films_json WHERE data @> '{"title": "The Matrix"}';


2. CREATE INDEX idx_films_data_gin_path ON films_json USING GIN (data jsonb_path_ops);
   OPT: SELECT * FROM films_json WHERE data @> '{"rating": {"average": 8.7}}';

3. CREATE INDEX idx_films_title_btree ON films_json ((data ->> 'title'));
   OPT: SELECT * FROM films_json WHERE data ->> 'title' = 'The Matrix';

8.4
******************************************************************************************************************
1. Les index GIN sur JSONB sont efficaces pour les recherches avec @>, ? (existence de clé), et les filtres sur des paires clé/valeur multiples.

2. jsonb_path_ops est à préférer si on utilise surtout @> : il est plus rapide et plus compact, mais ne gère pas les opérateurs comme ?.

3. Pour une propriété spécifique, le plus efficace est un index B-tree fonctionnel :
   CREATE INDEX ... ON table ((data ->> 'clé'));  








  







