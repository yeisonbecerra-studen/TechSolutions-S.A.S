-- Conteo de filas por tabla (para comparar antes/después de falla y recuperación)
SELECT 'departamentos' AS tabla, count(*) FROM app.departamentos UNION ALL
SELECT 'empleados', count(*) FROM app.empleados UNION ALL
SELECT 'activos', count(*) FROM app.activos UNION ALL
SELECT 'tickets', count(*) FROM app.tickets UNION ALL
SELECT 'mantenimientos', count(*) FROM app.mantenimientos UNION ALL
SELECT 'auditoria.log_cambios', count(*) FROM auditoria.log_cambios;
