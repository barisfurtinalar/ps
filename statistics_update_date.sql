SELECT name AS Stats,
STATS_DATE(object_id, stats_id) AS LastStatsUpdate
FROM sys.stats
WHERE object_id = OBJECT_ID('<table_name>')
and left(name,4)!='_WA_';