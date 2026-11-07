-- =====================================================================
-- TechSolutions S.A.S. - 04 Seguridad: roles, usuarios, GRANT/REVOKE
-- Principio de mínimo privilegio (ISO/IEC 27001:2022, control 8.2).
-- Contraseñas SOLO de laboratorio: en la nube irían en AWS Secrets Manager.
-- =====================================================================

-- Cerrar lo que PostgreSQL abre por defecto a PUBLIC
REVOKE ALL ON DATABASE techsolutions FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Roles de grupo (sin login): los permisos se asignan al rol, no a la persona
CREATE ROLE rol_aplicacion NOLOGIN;
CREATE ROLE rol_soporte    NOLOGIN;
CREATE ROLE rol_auditor    NOLOGIN;

GRANT CONNECT ON DATABASE techsolutions TO rol_aplicacion, rol_soporte, rol_auditor;
GRANT USAGE ON SCHEMA app TO rol_aplicacion, rol_soporte, rol_auditor;

-- rol_aplicacion: la app web lee y escribe, pero NO puede borrar
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA app TO rol_aplicacion;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO rol_aplicacion;

-- rol_soporte: gestiona tickets y mantenimientos; ve activos;
-- de empleados solo ve columnas no sensibles (sin documento de identidad)
GRANT SELECT, INSERT, UPDATE ON app.tickets, app.mantenimientos TO rol_soporte;
GRANT USAGE ON SEQUENCE app.tickets_id_seq, app.mantenimientos_id_seq TO rol_soporte;
GRANT SELECT ON app.activos, app.categorias_activo, app.departamentos,
                app.v_equipos_sin_parches TO rol_soporte;
GRANT SELECT (id, nombres, apellidos, correo, cargo, departamento_id, activo)
    ON app.empleados TO rol_soporte;

-- rol_auditor: solo lectura de todo, incluido el esquema de auditoría
GRANT SELECT ON ALL TABLES IN SCHEMA app TO rol_auditor;
GRANT USAGE ON SCHEMA auditoria TO rol_auditor;
GRANT SELECT ON ALL TABLES IN SCHEMA auditoria TO rol_auditor;
GRANT pg_read_all_stats TO rol_auditor;

-- Tablas futuras heredan los permisos de lectura
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT ON TABLES TO rol_auditor;

-- Usuarios (con login) que heredan de los roles
CREATE ROLE app_user    LOGIN PASSWORD 'App_Lab_2026'     IN ROLE rol_aplicacion CONNECTION LIMIT 20;
CREATE ROLE soporte_ana LOGIN PASSWORD 'Soporte_Lab_2026' IN ROLE rol_soporte VALID UNTIL '2027-06-30';
CREATE ROLE auditor_ext LOGIN PASSWORD 'Auditor_Lab_2026' IN ROLE rol_auditor VALID UNTIL '2027-06-30';

-- ---------------------------------------------------------------------
-- SITUACIÓN INICIAL (problema del diagnóstico): un practicante con
-- privilegios excesivos que nadie revisa. sql/seguridad.sql lo corrige.
-- ---------------------------------------------------------------------
CREATE ROLE practicante_tmp LOGIN PASSWORD 'Practicante123';
GRANT CONNECT ON DATABASE techsolutions TO practicante_tmp;
GRANT USAGE ON SCHEMA app TO practicante_tmp;
GRANT ALL ON ALL TABLES IN SCHEMA app TO practicante_tmp;
