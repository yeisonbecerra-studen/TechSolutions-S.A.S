-- =====================================================================
-- Monitoreo de recursos y rendimiento
-- Uso: ./ts.sh monitoreo
-- =====================================================================
\echo '== Conexiones activas por usuario y aplicación'
SELECT usename AS usuario, application_name AS aplicacion, state AS estado, count(*)
FROM pg_stat_activity WHERE datname = 'techsolutions'
GROUP BY 1, 2, 3 ORDER BY 4 DESC;

\echo '== Tasa de aciertos en caché (ideal > 99 %)'
SELECT round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
       xact_commit AS commits, xact_rollback AS rollbacks, deadlocks
FROM pg_stat_database WHERE datname = 'techsolutions';

\echo '== Top 5 consultas más costosas (pg_stat_statements)'
SELECT calls AS llamadas, round(total_exec_time::numeric, 1) AS ms_total,
       round(mean_exec_time::numeric, 2) AS ms_promedio,
       left(regexp_replace(query, '\s+', ' ', 'g'), 70) AS consulta
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'techsolutions')
ORDER BY total_exec_time DESC LIMIT 5;

\echo '== Tablas: lecturas secuenciales vs por índice y filas muertas'
SELECT relname AS tabla, seq_scan, idx_scan, n_live_tup AS filas_vivas,
       n_dead_tup AS filas_muertas, last_autovacuum, last_analyze
FROM pg_stat_user_tables ORDER BY n_dead_tup DESC;

\echo '== Crecimiento: tamaño actual de la base'
SELECT pg_size_pretty(pg_database_size('techsolutions')) AS tamano_bd;
