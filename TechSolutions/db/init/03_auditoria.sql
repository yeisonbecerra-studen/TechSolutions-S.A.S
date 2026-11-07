-- =====================================================================
-- TechSolutions S.A.S. - 03 Auditoría
-- Trigger genérico que registra INSERT/UPDATE/DELETE con el usuario real
-- (session_user), la aplicación, la IP y los datos antes/después.
-- Se crea DESPUÉS de cargar los datos de prueba para no registrar la carga.
-- =====================================================================

CREATE OR REPLACE FUNCTION auditoria.fn_registrar_cambio()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER                 -- escribe en auditoria aunque el usuario no tenga permiso
SET search_path = auditoria, pg_temp
AS $$
BEGIN
    INSERT INTO auditoria.log_cambios (tabla, operacion, datos_antes, datos_despues)
    VALUES (TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
            TG_OP,
            CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) END,
            CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) END);
    RETURN NULL;                 -- trigger AFTER: el valor de retorno se ignora
END;
$$;

CREATE TRIGGER trg_audit_empleados AFTER INSERT OR UPDATE OR DELETE ON app.empleados
    FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar_cambio();
CREATE TRIGGER trg_audit_activos AFTER INSERT OR UPDATE OR DELETE ON app.activos
    FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar_cambio();
CREATE TRIGGER trg_audit_tickets AFTER INSERT OR UPDATE OR DELETE ON app.tickets
    FOR EACH ROW EXECUTE FUNCTION auditoria.fn_registrar_cambio();

-- Política de retención: 365 días (antes la empresa solo guardaba 15 días)
CREATE OR REPLACE FUNCTION auditoria.fn_purgar_logs(dias_retencion int DEFAULT 365)
RETURNS bigint
LANGUAGE sql
AS $$
    WITH borrados AS (
        DELETE FROM auditoria.log_cambios
        WHERE fecha < now() - make_interval(days => dias_retencion)
        RETURNING 1
    )
    SELECT count(*) FROM borrados;
$$;

-- Resumen para el auditor: quién hizo qué y cuántas veces
CREATE VIEW auditoria.v_resumen_actividad AS
SELECT date_trunc('hour', fecha) AS hora, usuario_bd, aplicacion, tabla, operacion,
       count(*) AS registros
FROM auditoria.log_cambios
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1 DESC, registros DESC;
