-- 5 -- 
-- Comptage simple
SELECT COUNT(*) FROM title_basics;
--11734860

-- Distribution par type
SELECT title_type, COUNT(*)
	FROM title_basics
GROUP BY title_type
ORDER BY COUNT(*) DESC;
-- "tvEpisode" | 9031292

-- Films les mieux notés
SELECT b.primary_title, r.average_rating, r.num_votes
	FROM title_basics b
	JOIN title_ratings r ON b.tconst = r.tconst
	WHERE b.title_type = 'movie'
	ORDER BY r.average_rating DESC
LIMIT 10;
-- "One Decision" | 10.0 | 7

-- 6 -- 

EXPLAIN ANALYZE
	SELECT b.primary_title, r.average_rating
	FROM title_basics b
	JOIN title_ratings r ON b.tconst = r.tconst
	WHERE r.num_votes > 1000
	ORDER BY r.average_rating DESC
LIMIT 10;

--"Limit  (cost=22367.97..22424.01 rows=10 width=26) (actual time=57.763..65.977 rows=10 loops=1)"
"  ->  Nested Loop  (cost=22367.97..556693.91 rows=95356 width=26) (actual time=57.762..65.968 rows=10 loops=1)"
"        ->  Gather Merge  (cost=22367.54..33473.32 rows=95356 width=16) (actual time=57.716..61.395 rows=10 loops=1)"
"              Workers Planned: 2"
"              Workers Launched: 2"
"              ->  Sort  (cost=21367.52..21466.85 rows=39732 width=16) (actual time=39.774..39.814 rows=937 loops=3)"
"                    Sort Key: r.average_rating DESC"
"                    Sort Method: quicksort  Memory: 3525kB"
"                    Worker 0:  Sort Method: quicksort  Memory: 1575kB"
"                    Worker 1:  Sort Method: quicksort  Memory: 1709kB"
"                    ->  Parallel Seq Scan on title_ratings r  (cost=0.00..18332.39 rows=39732 width=16) (actual time=0.061..29.293 rows=32504 loops=3)"
"                          Filter: (num_votes > 1000)"
"                          Rows Removed by Filter: 494624"
"        ->  Index Scan using title_basics_pkey on title_basics b  (cost=0.43..5.49 rows=1 width=30) (actual time=0.453..0.453 rows=1 loops=10)"
"              Index Cond: ((tconst)::text = (r.tconst)::text)"
"Planning Time: 0.265 ms"
"Execution Time: 66.302 ms"