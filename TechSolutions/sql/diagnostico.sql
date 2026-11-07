-- =====================================================================
-- Diagnóstico DBA inicial: ¿cómo está la base de datos HOY?
-- Uso: ./ts.sh diagnostico
-- =====================================================================
\echo '== 1. Versión del SGBD y configuración relevante'
SELECT version();
SELECT name, setting FROM pg_settings
WHERE name IN ('shared_buffers','max_connections','log_connections',
               'log_statement','log_min_duration_statement','shared_preload_libraries','TimeZone');

\echo '== 2. Recursos: tamaño de la base y de cada tabla'
SELECT pg_size_pretty(pg_database_size('techsolutions')) AS tamano_bd;
SELECT n.nspname AS esquema, c.relname AS tabla,
       c.reltuples::bigint AS filas_aprox,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS tamano_total,
       pg_size_pretty(pg_indexes_size(c.oid))        AS tamano_indices
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' AND n.nspname IN ('app','auditoria')
ORDER BY pg_total_relation_size(c.oid) DESC;

\echo '== 3. Seguridad: usuarios con privilegios de borrado o totales sobre app'
SELECT grantee, table_name, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
FROM information_schema.role_table_grants
WHERE table_schema = 'app' AND grantee NOT IN ('dba_admin')
  AND privilege_type IN ('DELETE','TRUNCATE') AND table_name NOT LIKE 'v\_%'
GROUP BY grantee, table_name
ORDER BY grantee, table_name;

\echo '== 4. Usuarios con login, vencimiento y superusuarios'
SELECT rolname, rolsuper AS superusuario, rolcanlogin AS login,
       rolconnlimit AS limite_conexiones, rolvaliduntil AS vence
FROM pg_roles WHERE rolname !~ '^pg_' ORDER BY rolcanlogin DESC, rolname;

\echo '== 5. Respaldos registrados (último respaldo exitoso)'
SELECT count(*) AS respaldos, max(fin) AS ultimo_respaldo,
       now() - max(fin) AS antiguedad
FROM auditoria.log_respaldos WHERE estado = 'OK';

\echo '== 6. Índices existentes en app.tickets (¿faltan índices?)'
SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'app' AND tablename = 'tickets';

\echo '== 7. Hallazgos de auditoría visibles en los datos'
SELECT count(*) AS equipos_sin_parches_30_dias FROM app.v_equipos_sin_parches;
SELECT * FROM app.v_empleados_sin_mfa ORDER BY pct_sin_mfa DESC;
