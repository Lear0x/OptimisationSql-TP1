1.1

EXPLAIN ANALYZE
SELECT *
FROM title_basics
WHERE start_year = 2020;


-- response:
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

1.2

-- 1. Pourquoi PostgreSQL utilise-t-il un Parallel Sequential Scan?
--Pour améliorer la vitesse de lecture, il divise le travail entre plusieurs threads.

-- 2. La parallélisation est-elle justifiée ici? Pourquoi?
-- La volumétrie de la table (plus de 4  millions de lignes) justifie l'utilisation du Parallel Sequential Scan pour accélérer le traitement.

-- 3. Que représente la valeur "Rows Removed by Filter"?
-- C'est le nombre de lignes qui ont été lues mais qui ne correspondent pas au critère de filtrage (start_year = 2020). Ici, 3,764,950 lignes ont été ignorées.


1.3

CREATE INDEX idx_start_year ON title_basics(start_year);
--response 
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

-- Parallel Bitmap Index Scan + Heap Recheck
-- Passé de 1,9 seconde à 0,48 seconde

1.5

EXPLAIN ANALYZE
SELECT tconst, primary_title, start_year
FROM title_basics
WHERE start_year = 2020;
-- response
"Gather  (cost=5627.89..271032.56 rows=415414 width=34) (actual time=58.263..4524.473 rows=440009 loops=1)"
"  Workers Planned: 2"
"  Workers Launched: 2"
"  ->  Parallel Bitmap Heap Scan on title_basics  (cost=4627.89..228491.16 rows=173089 width=34) (actual time=21.842..4437.623 rows=146670 loops=3)"
"        Recheck Cond: (start_year = 2020)"
"        Rows Removed by Index Recheck: 671753"
"        Heap Blocks: exact=12585 lossy=11468"
"        ->  Bitmap Index Scan on idx_title_basics_start_year  (cost=0.00..4524.04 rows=415414 width=0) (actual time=48.276..48.276 rows=440009 loops=1)"
"              Index Cond: (start_year = 2020)"
"Planning Time: 0.278 ms"
"JIT:"
"  Functions: 12"
"  Options: Inlining false, Optimization false, Expressions true, Deforming true"
"  Timing: Generation 3.920 ms (Deform 0.661 ms), Inlining 0.000 ms, Optimization 0.850 ms, Emission 8.446 ms, Total 13.216 ms"
"Execution Time: 4542.901 ms"

--1. Le temps d'exécution a-t-il changé? Pourquoi?
--  Oui, il a changé — mais de façon contre-intuitive, il a augmenté.
--  Étape 1.4 (SELECT ): ~484 ms
--  Étape 1.5 (3 colonnes): ~4 691 ms ❗
--  Effet de cache, 
--2. Le plan d'exécution est-il différent?
-- le plan est structurellement le même, mais avec des variantes internes (plus de recheck, plus de blocs, plus de fonctions JIT).

-- width (taille des lignes) diminue (de 84 à 34)
-- Nombre de blocs relus légèrement plus élevé
-- JIT plus intense
--3. Pourquoi la sélection de moins de colonnes peut-elle améliorer les performances?
-- PostgreSQL lit moins de données dans les pages mémoire ou disque

1.6

-- 1. Quelle nouvelle stratégie PostgreSQL utilise-t-il maintenant ?
--  Bitmap Index Scan + Parallel Bitmap Heap Scan

-- 2. Le temps d'exécution s’est-il amélioré ? De combien ?
-- Oui, passé de ~1910 ms à ~484 ms (~4× plus rapide)

-- 3. Que signifie "Bitmap Heap Scan" et "Bitmap Index Scan" ?
-- Scan par index pour cibler les blocs, puis lecture des blocs filtrés

-- 4. Pourquoi l’amélioration n’est-elle pas plus importante ?
-- Beaucoup de lignes correspondantes, dispersées, avec relecture partielle
2.1

EXPLAIN ANALYZE
SELECT *
FROM title_basics
WHERE title_type = 'movie' AND start_year = 1950;



2.2

--1. Quelle stratégie est utilisée pour le filtre sur start_year ?
-- Bitmap Index Scan (index utilisé sur start_year)
--2. Comment est traité le filtre sur title_type ?
-- Appliqué en second dans la phase Filter (après lecture des lignes de l’index)
--3. Combien de lignes passent le premier filtre, puis le second ?
  -- 8277 lignes passent le filtre start_year
  -- 2009 lignes passent aussi le filtre title_type = 'movie'
  -- 6268 lignes rejetées ensuite (Rows Removed by Filter)
--3. Quelles sont les limitations de notre index actuel ?
-- Il ne couvre que start_year
-- PostgreSQL ne peut pas optimiser title_type avec un index
-- Résultat : scan élargi, suivi d’un filtrage manuel

2.3

CREATE INDEX idx_type_year ON title_basics(title_type, start_year);

2.4 

-- L'index composite permet d'éviter complètement le filtrage manuel (Rows Removed by Filter n’apparaît plus).
--Le nombre de blocs disques à lire a été fortement réduit (933 vs 3275).
--La requête est plus de 500 fois plus rapide.

2.5

    EXPLAIN ANALYZE
    SELECT tconst, primary_title, start_year, title_type
    FROM title_basics
    WHERE title_type = 'movie' AND start_year = 1950;



--1. Le temps d'exécution a-t-il changé ?
-- Oui, légèrement : 1.4 ms (étape 2.4) → 2.0 ms (étape 2.5)

--2. Pourquoi cette optimisation est-elle plus ou moins efficace que dans l'exercice 1 ?
-- Elle est moins significative car ici, l’index est déjà très sélectif et performant. Dans l'exercice 1, la réduction du nombre de colonnes avait plus d’impact.
--3. Dans quel cas un "covering index" serait idéal ?
-- Si l’index contenait aussi tconst et primary_title, PostgreSQL pourrait éviter la lecture des blocs et utiliser un Index Only Scan → encore plus rapide.

2.6
--1. Quelle est la différence de temps d'exécution par rapport à l'étape 2.1 ?
--De 782 ms (sans index composite) à ~2 ms → amélioration x390 ✅
--2. Comment l'index composite modifie-t-il la stratégie ?
-- Il permet un Bitmap Index Scan sur les deux colonnes, évitant le filtrage en mémoire.
--3. Pourquoi le nombre de blocs lus ("Heap Blocks") a-t-il diminué ?
--L’index cible uniquement les lignes pertinentes, donc moins de blocs disques à lire (933 vs 3275).
--4. Dans quels cas un index composite est-il particulièrement efficace ?
-- Quand les requêtes filtrent sur plusieurs colonnes combinées, dans le même ordre que l’index.

3.1

EXPLAIN ANALYZE
SELECT b.primary_title, r.average_rating
FROM title_basics b
JOIN title_ratings r ON b.tconst = r.tconst
WHERE b.title_type = 'movie'
  AND b.start_year = 1994
  AND r.average_rating > 8.5;

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
  
3.2
--1. Quel algorithme de jointure est utilisé ?
--Nested Loop (avec index sur title_ratings)

--2. Comment l'index sur start_year est-il utilisé ?
--Via un Bitmap Index Scan sur l’index composite start_year, title_type

--3. Comment est traitée la condition sur average_rating ?
--Elle est appliquée en filtre post-jointure sur chaque ligne (Filter dans Index Scan)

--4. Pourquoi PostgreSQL utilise-t-il le parallélisme ?
--Pour accélérer le Bitmap Heap Scan sur title_basics, car le filtre initial sélectionne plusieurs milliers de lignes (4252 avant jointure)

3.3

CREATE INDEX idx_ratings_rating ON title_ratings(average_rating);

3.4
--Après avoir créé l’index sur average_rating, la requête a été réexécutée et le plan reste un Nested Loop avec Bitmap Heap Scan sur title_basics, 
-- mais le temps d'exécution a fortement chuté.

3.5 
--1. L'algorithme de jointure a-t-il changé ?
--Non, toujours un Nested Loop

--2. Comment l'index sur average_rating est-il utilisé ?
--Pas encore utilisé directement dans le plan, car le filtre est appliqué après la jointure (Filter dans title_ratings)

--3. Le temps d'exécution s'est-il amélioré ? Pourquoi ?
-- Oui, de 366 ms à 30 ms ✅
-- Amélioration liée à :
    -- cache (réexécution)
    --amélioration de l’estimation du coût du filtre
    --moins de travail post-jointure

--4. Pourquoi PostgreSQL abandonne-t-il le parallélisme ?
-- Il ne l’abandonne pas totalement :
-- Le Bitmap Heap Scan est encore parallèle, mais le reste est tellement rapide que PostgreSQL n’a pas besoin d’en paralléliser davantage


4.1

EXPLAIN ANALYZE
SELECT b.start_year, COUNT(*) AS nb_films, AVG(r.average_rating) AS note_moyenne
FROM title_basics b
JOIN title_ratings r ON b.tconst = r.tconst
WHERE b.title_type = 'movie'
  AND b.start_year BETWEEN 1990 AND 2000
GROUP BY b.start_year
ORDER BY note_moyenne DESC;

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

4.2
--1. Identifiez les différentes étapes du plan (scan, hash, agrégation, tri)
-- Scan : Parallel Seq Scan sur title_ratings + Parallel Bitmap Heap Scan sur title_basics
-- Hash : Parallel Hash Join entre tconst
-- Agrégation : Partial GroupAggregate puis Finalize GroupAggregate
--2. Pourquoi l'agrégation est-elle réalisée en deux phases ("Partial" puis "Finalize") ?
-- PostgreSQL regroupe les données en parallèle sur chaque worker (Partial),
-- puis combine les résultats en une seule agrégation (Finalize) pour plus d’efficacité.
--3. Comment sont utilisés les index existants ?
-- L’index composite start_year, title_type est utilisé via un Bitmap Index Scan pour réduire les lignes à lire dans title_basics.
--4. Le tri final est-il coûteux ? Pourquoi ?
--Non, ici le tri est rapide (Memory: 25kB) car seulement 11 lignes sont triées après agrégation.

4.3

CREATE INDEX idx_title_basics_tconst ON title_basics(tconst);
CREATE INDEX idx_title_ratings_tconst ON title_ratings(tconst);


4.5 

--1. Les index de jointure sont-ils utilisés ? Pourquoi ?
-- Oui, l’index idx_title_ratings_tconst est utilisé pour l’accès à title_ratings via un Index Scan, car la jointure se fait sur tconst.

-- 2. Pourquoi le plan d'exécution reste-t-il pratiquement identique ?
-- Car PostgreSQL utilisait déjà une jointure optimisée (Nested Loop avec index), et le gain est limité à cause du petit volume de données en sortie.

--3. Dans quels cas les index de jointure seraient-ils plus efficaces ?
  -- Les tables sont très grandes

  -- La jointure porte sur une colonne très sélective

  -- Il y a beaucoup de lignes correspondantes ou un grand tri à faire ensuite


5.1

EXPLAIN ANALYZE
SELECT b.primary_title, r.average_rating
FROM title_basics b
JOIN title_ratings r ON b.tconst = r.tconst
WHERE b.tconst = 'tt0111161';


"Nested Loop  (cost=0.86..16.91 rows=1 width=26) (actual time=1.688..1.690 rows=1 loops=1)"
"  ->  Index Scan using title_basics_pkey on title_basics b  (cost=0.43..8.45 rows=1 width=30) (actual time=1.669..1.669 rows=1 loops=1)"
"        Index Cond: ((tconst)::text = 'tt0111161'::text)"
"  ->  Index Scan using idx_title_ratings_tconst on title_ratings r  (cost=0.43..8.45 rows=1 width=16) (actual time=0.014..0.015 rows=1 loops=1)"
"        Index Cond: ((tconst)::text = 'tt0111161'::text)"
"Planning Time: 0.138 ms"
"Execution Time: 1.713 ms"

5.2 

-- 1. Quel algorithme de jointure est utilisé cette fois ?
-- Nested Loop (très efficace pour une seule valeur)

--2. Comment les index sur tconst sont-ils utilisés ?
-- Deux Index Scan sont effectués sur title_basics_pkey et idx_title_ratings_tconst

--3. Comparez le temps d'exécution avec les requêtes précédentes
-- Temps record : 1.2 ms, beaucoup plus rapide que les requêtes précédentes

--4. Pourquoi cette requête est-elle si rapide ?
--Car elle utilise des recherches par clé primaire sur un identifiant unique (tconst), avec accès direct via index




