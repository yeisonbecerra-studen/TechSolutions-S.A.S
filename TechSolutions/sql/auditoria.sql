-- =====================================================================
-- Auditoría: ¿quién cambió qué, cuándo y desde dónde?
-- Uso: ./ts.sh auditoria
-- =====================================================================
\echo '== Resumen de actividad por usuario (últimas horas)'
SELECT * FROM auditoria.v_resumen_actividad LIMIT 15;

\echo '== Últimos 10 cambios con detalle'
SELECT id, fecha, usuario_bd, aplicacion, ip_cliente, tabla, operacion,
       coalesce(datos_despues, datos_antes) ->> 'id' AS registro_id,
       left(coalesce(datos_despues, datos_antes)::text, 80) AS datos
FROM auditoria.log_cambios ORDER BY id DESC LIMIT 10;

\echo '== Borrados masivos (posible incidente): más de 100 DELETE del mismo usuario'
SELECT usuario_bd, tabla, count(*) AS filas_borradas, min(fecha) AS desde, max(fecha) AS hasta
FROM auditoria.log_cambios
WHERE operacion = 'DELETE'
GROUP BY usuario_bd, tabla HAVING count(*) > 100;

\echo '== Política de retención: se conservan 365 días (antes 15)'
SELECT min(fecha) AS registro_mas_antiguo, count(*) AS total_registros,
       pg_size_pretty(pg_total_relation_size('auditoria.log_cambios')) AS tamano
FROM auditoria.log_cambios;
