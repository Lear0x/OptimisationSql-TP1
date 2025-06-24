# TP2 : Optimisation des requêtes avec les index

## Exercice 1 : Analyse d'une requête simple

### 1.1 Première analyse
```sql
EXPLAIN ANALYZE SELECT * FROM title_basics WHERE start_year = 2020;
```

```
"Gather  (cost=1000.00..277488.74 rows=415302 width=84) (actual time=32.395..1821.556 rows=440009 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Parallel Seq Scan on title_basics  (cost=0.00..234958.54 rows=173042 width=84) (actual time=23.444..1784.393 rows=146670 loops=3)"
"        Filter: (start_year = 2020)"
"        Rows Removed by Filter: 3764950"
"Planning Time: 1.375 ms"
"JIT:"
"  Functions: 6"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 1.071 ms (Deform 0.390 ms), Inlining 0.000 ms, Optimization 1.737 ms, Emission 20.747 ms, Total 23.555 ms"
"Execution Time: 1910.996 ms"
```

### 1.2  Analyse du plan d'exécution
* Postgresql utilise un Parallel Seq scan
* 415302 lignes retournée
* 3764950 lignes rejetée
* Temps d'execution = 1910.996ms

1.2.1) Car la table est trop grande il divise le travail en plusieur pour améliorer la vitesse de lecture

1.2.2) Car il y a trop de ligne dans la table plus de 4 millions il est utiliser pour aller plus vite

1.2.3) C'est le nombre de lignes qui ont été lues mais qui ne correspondent pas au critère de filtrage (start_year = 2020). Ici, 3,764,950 lignes ont été ignorées.

### 1.3 Création d'index
```sql
CREATE INDEX idx_start_year ON title_basics(start_year);
```
```
"Gather  (cost=5627.89..271032.56 rows=415414 width=84) (actual time=41.390..470.835 rows=440009 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Parallel Bitmap Heap Scan on title_basics  (cost=4627.89..228491.16 rows=173089 width=84) (actual time=27.385..436.332 rows=146670 loops=3)"
"        Recheck Cond: (start_year = 2020)"
"        Rows Removed by Index Recheck: 671753"
"        Heap Blocks: exact=12165 lossy=10853"
"        ->  Bitmap Index Scan on idx_title_basics_start_year  (cost=0.00..4524.04 rows=415414 width=0) (actual time=35.512..35.512 rows=440009 loops=1)"
"              Index Cond: (start_year = 2020)"
"Planning Time: 0.480 ms"
"JIT:"
"  Functions: 6"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 0.931 ms (Deform 0.294 ms), Inlining 0.000 ms, Optimization 0.731 ms, Emission 8.225 ms, Total 9.887 ms"
"Execution Time: 484.312 ms"
```

### 1.4 Analyse apres indexation
Cette fois on  utilise un Parallel Bitmap Scan et un Parallel Heap Scan et cette fois on est passé de 1.9s à 0.48s

### 1.5 Impact du nombre de colonnes
```sql
EXPLAIN ANALYZE SELECT tconst, primary_title, start_year FROM title_basics WHERE start_year = 2020;
```
1.5.1) Oui, il a changé mais de façon contre-intuitive, il a augmenté, à l'étape 1.4 (SELECT ): ~484 ms, à l'étape 1.5 (3 colonnes): ~4 691 ms. Il a changé à cause d'un effet de cache.

1.5.2) le plan est structurellement le même, mais avec des variantes internes (plus de recheck, plus de blocs, plus de fonctions JIT), la taille des lignes diminue et passe de 84 à 34, il relis plus de bloc et le JIT est plus intense.

1.5.3) PostgreSQL lit moins de données dans les pages mémoire ou disque

### 1.6 Analyse de l'impact global
1.6.1) Maintenant il utilise des Bitmap Index Scan et des Parallel Bitmap Heat Scan.

1.6.2) Oui, il est passé de 1910 ms à 484 ms (~4× plus rapide).

1.6.3) Scan par index pour cibler les blocs, puis lecture des blocs filtrés.

1.6.4) Car il y a beaucoup de lignes correspondantes, qui sont dispersées, ce qui nececite une relecture partielle.

## Exercice 2: Requêtes avec filtres multiples

### 2.1 Requête avec conditions multiples
```sql
EXPLAIN ANALYZE SELECT * FROM title_basics WHERE title_type = 'movie' AND start_year = 1950;
```
```
"Bitmap Heap Scan on title_basics (cost=10.25..2189.61 rows=567 width=84) (actual time=0.708..13.558 rows=2009 loops=1)" " Recheck Cond: ((start_year = 1950) AND ((title_type)::text = 'movie'::text))" " Heap Blocks: exact=933" " -> Bitmap Index Scan on idx_startyear_titletype (cost=0.00..10.11 rows=567 width=0) (actual time=0.595..0.596 rows=2009 loops=1)" " Index Cond: ((start_year = 1950) AND ((title_type)::text = 'movie'::text))" "Planning Time: 0.569 ms" "Execution Time: 13.758 ms"
```

### 2.2 Analyse du plan d'exécution
2.2.1) il utilise un Bitmap Index Scan sur start_year. le filtre sur title_Type est traité en apres la lecture des lignes de l'index

2.2.2) 8277 lignes passent le filtre start_year, 2009 lignes passent aussi le filtre title_type = 'movie'.

2.2.3) l'index n'est que sur une seule colonnes, il ne couvre pas tout.

### 2.3  Index composite
```sql
CREATE INDEX idx_type_year ON title_basics(title_type, start_year);
```

### 2.4  Analyse après index composite
L'index composite permet d'éviter complètement le filtrage manuel, le nombre de blocs disques à lire a été fortement réduit (933 vs 3275), ce qui fait que la requête est plus de 500 fois plus rapide.

### 2.5 Impact du nombre de colonnes
```sql
EXPLAIN ANALYZE SELECT tconst, primary_title, start_year, title_type FROM title_basics WHERE title_type = 'movie' AND start_year = 1950;
```

```
"Bitmap Heap Scan on title_basics (cost=10.25..2189.61 rows=567 width=43) (actual time=0.516..3.238 rows=2009 loops=1)" " Recheck Cond: ((start_year = 1950) AND ((title_type)::text = 'movie'::text))" " Heap Blocks: exact=933" " -> Bitmap Index Scan on idx_startyear_titletype (cost=0.00..10.11 rows=567 width=0) (actual time=0.378..0.378 rows=2009 loops=1)" " Index Cond: ((start_year = 1950) AND ((title_type)::text = 'movie'::text))" "Planning Time: 0.125 ms" "Execution Time: 3.430 ms"
```

2.5.1) Oui, légèrement : 1.4 ms (étape 2.4) → 2.0 ms (étape 2.5).

2.5.2) Elle est moins significative car ici, l’index est déjà très sélectif et performant. Dans l'exercice 1, la réduction du nombre de colonnes avait plus d’impact.

2.5.3) dans le cas où l’index contenait aussi tconst et primary_title, PostgreSQL pourrait éviter la lecture des blocs et utiliser un Index Only Scan → encore plus rapide.

### 2.6 Analyse de l'amélioration globale

2.6.1) La différence de temps est de 782 ms (sans index composite) à ~2 ms

2.6.2) Il permet un Bitmap Index Scan sur les deux colonnes, évitant le filtrage en mémoire.

2.6.3) L’index cible uniquement les lignes pertinentes, donc moins de blocs disques à lire.

2.6.4) Quand les requêtes filtrent sur plusieurs colonnes combinées, dans le même ordre que l’index.


## Exercice 3: Jointures et filtres

### 3.1 Jointure avec filtre
```sql
EXPLAIN ANALYZE
SELECT b.primary_title, r.average_rating
FROM title_basics b JOIN title_ratings r ON b.tconst = r.tconst 
WHERE b.title_type = 'movie' AND b.start_year = 1994 AND r.average_rating > 8.5;
```
```
  "Gather  (cost=1062.35..28852.65 rows=57 width=26) (actual time=17.839..394.775 rows=37 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Nested Loop  (cost=62.35..27846.95 rows=24 width=26) (actual time=21.175..341.872 rows=12 loops=3)"
"        ->  Parallel Bitmap Heap Scan on title_basics b  (cost=61.92..15533.89 rows=1849 width=30) (actual time=1.663..182.157 rows=1417 loops=3)"
"              Recheck Cond: ((start_year = 1994) AND ((title_type)::text = 'movie'::text))"
"              Heap Blocks: exact=875"
"              ->  Bitmap Index Scan on idx_startyear_titletype  (cost=0.00..60.82 rows=4438 width=0) (actual time=3.235..3.236 rows=4252 loops=1)"
"                    Index Cond: ((start_year = 1994) AND ((title_type)::text = 'movie'::text))"
"        ->  Index Scan using idx_title_ratings_tconst on title_ratings r  (cost=0.43..6.66 rows=1 width=16) (actual time=0.111..0.111 rows=0 loops=4252)"
"              Index Cond: ((tconst)::text = (b.tconst)::text)"
"              Filter: (average_rating > 8.5)"
"              Rows Removed by Filter: 1"
"Planning Time: 5.421 ms"
"Execution Time: 394.873 ms"
```

### 3.2 Analyse du plan de jointure
3.2.1) ici le Nested Loop est utilisé sur l'index title_ratings)

3.2.2) il est utilisé via un Bitmap Index Scan sur l'index start_year, title_year

3.2.3) Elle est appliquée en filtre post-jointure sur chaque ligne.

3.3.3) il l'utilise pour accélérer le Bitmap Heap Scan sur title_basics, car le filtre initial sélectionne plusieurs milliers de lignes

### 3.3 Indexation de la seconde condition
```sql
CREATE INDEX idx_ratings_rating ON title_ratings(average_rating);
```

### 3.4 Analyse apres indexation
Après avoir créé l’index sur average_rating, la requête a été réexécutée et le plan reste un Nested Loop avec Bitmap Heap Scan sur title_basics mais le temps d'exécution a fortement chuté.

### 3.5 Analyse de l'impact
3.5.1) Non, l'algo de jointure est toujours un Nested Loop

3.5.2) il n'est pas encore utilisé dans le plan car le filtre s'applique apres la jointure.

3.5.3) Il c'est grandement amélioré il est passé de 366ms à 30ms grâce à une réexécution, une amélioration de l'estimation du coup du filtre et car il y a moins de travail apres une jointure.

3.5.4) Il ne l’abandonne pas totalement : Le Bitmap Heap Scan est encore parallèle, mais le reste est tellement rapide que PostgreSQL n’a pas besoin d’en paralléliser davantage.

## Exercice 4: Agrégation et tri

### 4.1 Requete complexe
```sql
EXPLAIN ANALYZE
SELECT b.start_year,
       COUNT(*) AS nb_films,
       AVG(r.average_rating) AS moyenne_notes
FROM title_basics b
JOIN title_ratings r ON b.tconst = r.tconst
WHERE b.title_type = 'movie'
  AND b.start_year BETWEEN 1990 AND 2000
GROUP BY b.start_year
ORDER BY moyenne_notes DESC;
```

```
"Sort  (cost=151521.87..151522.20 rows=131 width=44) (actual time=1471.541..1474.860 rows=11 loops=1)"
"  Sort Key: (avg(r.average_rating)) DESC"
"  Sort Method: quicksort  Memory: 25kB"
"  ->  Finalize GroupAggregate  (cost=151449.59..151517.26 rows=131 width=44) (actual time=1470.453..1474.797 rows=11 loops=1)"
"        Group Key: b.start_year"
"        ->  Gather Merge  (cost=151449.59..151513.00 rows=262 width=44) (actual time=1470.218..1474.727 rows=33 loops=1)"
"              Workers Planned: 2"
"              Workers Launched: 2"
"              ->  Partial GroupAggregate  (cost=150449.56..150482.74 rows=131 width=44) (actual time=1450.894..1451.934 rows=11 loops=3)"
"                    Group Key: b.start_year"
"                    ->  Sort  (cost=150449.56..150457.45 rows=3154 width=10) (actual time=1450.715..1451.125 rows=10346 loops=3)"
"                          Sort Key: b.start_year"
"                          Sort Method: quicksort  Memory: 713kB"
"                          Worker 0:  Sort Method: quicksort  Memory: 719kB"
"                          Worker 1:  Sort Method: quicksort  Memory: 692kB"
"                          ->  Parallel Hash Join  (cost=131851.52..150266.27 rows=3154 width=10) (actual time=1203.655..1448.585 rows=10346 loops=3)"
"                                Hash Cond: ((r.tconst)::text = (b.tconst)::text)"
"                                ->  Parallel Seq Scan on title_ratings r  (cost=0.00..16685.11 rows=658911 width=16) (actual time=0.416..150.919 rows=527129 loops=3)"
"                                ->  Parallel Hash  (cost=131558.99..131558.99 rows=23402 width=14) (actual time=1197.262..1197.263 rows=17113 loops=3)"
"                                      Buckets: 65536  Batches: 1  Memory Usage: 2976kB"
"                                      ->  Parallel Bitmap Heap Scan on title_basics b  (cost=14232.59..131558.99 rows=23402 width=14) (actual time=15.567..1183.698 rows=17113 loops=3)"
"                                            Recheck Cond: ((start_year >= 1990) AND (start_year <= 2000) AND ((title_type)::text = 'movie'::text))"
"                                            Heap Blocks: exact=5357"
"                                            ->  Bitmap Index Scan on idx_startyear_titletype  (cost=0.00..14218.55 rows=56166 width=0) (actual time=18.409..18.409 rows=51338 loops=1)"
"                                                  Index Cond: ((start_year >= 1990) AND (start_year <= 2000) AND ((title_type)::text = 'movie'::text))"
"Planning Time: 2.322 ms"
"JIT:"
"  Functions: 57"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 8.973 ms (Deform 1.336 ms), Inlining 0.000 ms, Optimization 1.365 ms, Emission 24.241 ms, Total 34.579 ms"
"Execution Time: 1475.620 ms"
```

### 4.2 Analyse du plan complexe

4.2.1) Lors du scan il y a un Parallel Seq Scan sur title_ratings et un Parallel Bitmap Heat Scan sur title_basics. Lors du Hash il y a un Parallel Hash Join entre Tconst et enfin il y a une Partial GrouopAggregate puis une Finalize GroupAggregate.

4.2.2) Car postgreSQL regroupe les données en parallèle sur chaque worker (Partial), puis combine les résultats en une seule agrégation (Finalize) pour plus d’efficacité.

4.2.3) L’index start_year, title_type est utilisé via un Bitmap Index Scan pour réduire les lignes à lire dans title_basics.

4.2.4) Non, ici le tri est rapide (Memory: 25kB) car seulement 11 lignes sont triées après agrégation.

### 4.3 Indexation des colonnes de jointure
```sql
CREATE INDEX idx_title_basics_tconst ON title_basics(tconst);
CREATE INDEX idx_title_ratings_tconst ON title_ratings(tconst);
```

### 4.4 Analyse apres indexation


### 4.5 Analyse des résultats
4.5.1) Oui, l’index idx_title_ratings_tconst est utilisé pour l’accès à title_ratings via un Index Scan, car la jointure se fait sur tconst.

4.5.2) Car PostgreSQL utilisait déjà une jointure optimisée (Nested Loop avec index), et le gain est limité à cause du petit volume de données en sortie.

4.5.3) Quand les tables sont tres grandes, quand la jointure porte sur une colonne tres selective et quand il y a beaucoup de lignes correspondante ou un grand tri à faire ensuite.

## Exercice 5: Recherche ponctuelle

### 5.1 REquête de recherche par identifiant
```sql
EXPLAIN ANALYZE
SELECT b.primary_title, r.average_rating
FROM title_basics b
JOIN title_ratings r ON b.tconst = r.tconst
WHERE b.tconst = 'tt0111161';
```

```
"Nested Loop  (cost=0.86..16.91 rows=1 width=26) (actual time=1.688..1.690 rows=1 loops=1)"
"  ->  Index Scan using title_basics_pkey on title_basics b  (cost=0.43..8.45 rows=1 width=30) (actual time=1.669..1.669 rows=1 loops=1)"
"        Index Cond: ((tconst)::text = 'tt0111161'::text)"
"  ->  Index Scan using idx_title_ratings_tconst on title_ratings r  (cost=0.43..8.45 rows=1 width=16) (actual time=0.014..0.015 rows=1 loops=1)"
"        Index Cond: ((tconst)::text = 'tt0111161'::text)"
"Planning Time: 0.138 ms"
"Execution Time: 1.713 ms"
```

### 5.2 Analyse du plan
5.2.1) Un Nested Loop car il est tres efficace pour une seule valeur.

5.2.2) Deux Index Scan sont effectués sur title_basics_pkey et idx_title_ratings_tconst.

5.2.3) Le temps est beaucoup plus rapide que les requetes precedentes cette fois on à 1.2ms

5.2.4) Car elle utilise des recherches par clé primaire sur un identifiant unique (tconst), avec accès direct via index.

## Exercice 6: Synthèse et réflexion

#### 1. **Quand un index est-il le plus efficace ?**

* Il est efficace pour des recherches ciblées, car il permet d’accéder rapidement aux lignes concernées sans parcourir toute la table.

* Sur des colonnes contenant beaucoup de valeurs distinctes et une colonne avec très peu de valeurs différentes.

* l'index est performant pour les recherche par egalité.

#### 2. **Quels algorithmes de jointure avez-vous observés ?**

* Nested Loop Join a utiliser quand on a une petite table et qu'un indexe de disponible sur la deuxieme table. l'optimiseur l'evite sur il y a un gros volmume pour utiliser les deux autre
* Hash Join, tres bon sur de grands table et bien quand il n'y a pas d'ordre
* Merge Join, préférable quand les deux table sont trié sur la jointure

### 3. **Quand le parallélisme est-il activé ?**

* Quand les tables sont trop grandes
* Quand il y a de grosse jointures

Il n'est pas toujours utilisé car lecoût de gestion des threads peut dépasser le gain si la requête est trop simple ou rapide.
Certaines opérations ou fonctions ne sont pas **parallel-safe**.

### 4. **Quels types d'index utiliser dans les cas suivants ?**

* Pour une recherche exacte sur une colonne l'Index B-tree simple est utilisé.
* Pour un filtrage sur plusieurs colonnes combinées on utilise l'indexe multicolonne.
* Pour le tri fréquent sur une colonne c'est l'Index B-tree trié qui est utilisé.
* Pour les jointures fréquentes entre tables on utilise l'index sur la clé de jointure.



