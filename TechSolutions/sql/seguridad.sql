-- =====================================================================
-- Seguridad: demostración de GRANT / REVOKE y mínimo privilegio
-- Uso: ./ts.sh seguridad
-- =====================================================================
\echo '== ANTES: privilegios del practicante sobre app'
SELECT table_name, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
FROM information_schema.role_table_grants
WHERE grantee = 'practicante_tmp' GROUP BY table_name ORDER BY table_name;

\echo '== CORRECCIÓN: REVOKE de todo y se asigna el rol de soporte (mínimo privilegio)'
REVOKE ALL ON ALL TABLES IN SCHEMA app FROM practicante_tmp;
GRANT rol_soporte TO practicante_tmp;
ALTER ROLE practicante_tmp VALID UNTIL '2026-12-31' PASSWORD 'Pr4ctic@nte_2026!';

\echo '== DESPUÉS: privilegios directos (debe quedar vacío) y roles heredados'
SELECT table_name, privilege_type FROM information_schema.role_table_grants
WHERE grantee = 'practicante_tmp';
SELECT r.rolname AS usuario, g.rolname AS rol_heredado
FROM pg_auth_members m JOIN pg_roles r ON r.oid = m.member JOIN pg_roles g ON g.oid = m.roleid
WHERE r.rolname IN ('practicante_tmp','soporte_ana','auditor_ext','app_user');

\echo '== PRUEBA 1: soporte_ana PUEDE crear un ticket'
SET ROLE soporte_ana;
INSERT INTO app.tickets (solicitante_id, categoria, prioridad, titulo)
VALUES (5, 'ACCESOS', 'ALTA', 'Prueba de permisos: activar MFA') RETURNING id, titulo;

\echo '== PRUEBA 2: soporte_ana NO puede borrar tickets (debe fallar)'
\set ON_ERROR_STOP 0
DELETE FROM app.tickets WHERE id = 1;

\echo '== PRUEBA 3: soporte_ana NO puede ver el documento de los empleados (debe fallar)'
SELECT documento FROM app.empleados LIMIT 1;

\echo '== PRUEBA 4: soporte_ana SÍ ve columnas permitidas'
SELECT id, nombres, apellidos, cargo FROM app.empleados LIMIT 3;
RESET ROLE;

\echo '== PRUEBA 5: auditor_ext NO puede modificar (debe fallar)'
SET ROLE auditor_ext;
UPDATE app.activos SET estado = 'BODEGA' WHERE id = 1;
RESET ROLE;
