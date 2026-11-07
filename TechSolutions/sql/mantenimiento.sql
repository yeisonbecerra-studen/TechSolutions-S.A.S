-- =====================================================================
-- Mantenimiento automatizado (lo ejecuta ./ts.sh mantenimiento y el timer)
-- =====================================================================
\echo '== Filas muertas ANTES'
SELECT relname, n_dead_tup FROM pg_stat_user_tables WHERE n_dead_tup > 0 ORDER BY 2 DESC;

\echo '== Purga de logs de auditoría con más de 365 días'
SELECT auditoria.fn_purgar_logs(365) AS registros_purgados;

\echo '== VACUUM ANALYZE (recupera espacio y actualiza estadísticas del optimizador)'
VACUUM (ANALYZE) app.tickets;
VACUUM (ANALYZE) app.activos;
VACUUM (ANALYZE) app.empleados;
VACUUM (ANALYZE) app.mantenimientos;
VACUUM (ANALYZE) auditoria.log_cambios;

\echo '== Filas muertas DESPUÉS'
SELECT pg_sleep(1);
SELECT relname, n_dead_tup, last_vacuum, last_analyze FROM pg_stat_user_tables ORDER BY relname;
