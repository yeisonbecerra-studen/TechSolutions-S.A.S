-- =====================================================================
-- Optimización: consulta lenta del tablero de la mesa de ayuda
-- "Tickets abiertos o en proceso de los últimos 30 días"
-- Uso: ./ts.sh optimizar
-- =====================================================================
\timing on
DROP INDEX IF EXISTS app.idx_tickets_estado_fecha;
DROP INDEX IF EXISTS app.idx_tickets_solicitante;

\echo '== ANTES (sin índice): observe "Seq Scan" y el tiempo de ejecución'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id, prioridad, titulo, creado_en
FROM app.tickets
WHERE estado IN ('ABIERTO','EN_PROCESO') AND creado_en >= now() - interval '30 days'
ORDER BY creado_en DESC;

\echo '== ACCIÓN: índice compuesto (estado, creado_en) + índice en la llave foránea'
CREATE INDEX idx_tickets_estado_fecha ON app.tickets (estado, creado_en DESC);
CREATE INDEX idx_tickets_solicitante  ON app.tickets (solicitante_id);
ANALYZE app.tickets;

\echo '== DESPUÉS (con índice): observe "Index Scan"/"Bitmap" y el nuevo tiempo'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT id, prioridad, titulo, creado_en
FROM app.tickets
WHERE estado IN ('ABIERTO','EN_PROCESO') AND creado_en >= now() - interval '30 days'
ORDER BY creado_en DESC;

\echo '== Costo del índice en almacenamiento'
SELECT indexrelname AS indice, pg_size_pretty(pg_relation_size(indexrelid)) AS tamano
FROM pg_stat_user_indexes WHERE relname = 'tickets';
