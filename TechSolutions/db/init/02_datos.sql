-- =====================================================================
-- TechSolutions S.A.S. - 02 Datos de prueba (ficticios, uso académico)
-- 6 departamentos, 120 empleados, 320 activos, ~60.000 tickets.
-- setseed() hace que los datos sean iguales en cada instalación.
-- =====================================================================
SELECT setseed(0.42);

INSERT INTO app.departamentos (nombre, centro_costo) VALUES
  ('Gerencia', 'CC-100'),
  ('Tecnología', 'CC-200'),
  ('Desarrollo de Software', 'CC-300'),
  ('Comercial', 'CC-400'),
  ('Finanzas', 'CC-500'),
  ('Talento Humano', 'CC-600');

INSERT INTO app.categorias_activo (nombre, vida_util_meses) VALUES
  ('Portátil', 36),
  ('Equipo de escritorio', 48),
  ('Servidor', 60),
  ('Equipo de red', 60),
  ('Licencia de software', 12),
  ('Servicio en la nube', 12),
  ('Móvil', 24);

-- 120 empleados. departamento = 1 + (g % 6); los de Tecnología (id 2) son técnicos.
-- Solo el 10 % tiene MFA activo (hallazgo de auditoría).
INSERT INTO app.empleados (documento, nombres, apellidos, correo, cargo,
                           departamento_id, mfa_activo, fecha_ingreso)
SELECT (1000000000 + g * 7919)::text,
       (ARRAY['Ana','Carlos','Laura','Andrés','Valentina','Juan','Camila','Santiago',
              'Daniela','Felipe','Mariana','Sebastián','Paula','Diego','Natalia'])[1 + g % 15],
       (ARRAY['Gómez','Rodríguez','Martínez','López','García','Hernández',
              'Pérez','Ramírez','Torres','Castro','Rojas','Moreno'])[1 + (g * 7) % 12]
       || ' ' ||
       (ARRAY['Gómez','Rodríguez','Martínez','López','García','Hernández',
              'Pérez','Ramírez','Torres','Castro','Rojas','Moreno'])[1 + (g * 5) % 12],
       'emp' || lpad(g::text, 3, '0') || '@techsolutions.com.co',
       (ARRAY['Gerente','Técnico de soporte','Desarrollador','Ejecutivo comercial',
              'Analista financiero','Analista de talento humano'])[1 + g % 6],
       1 + g % 6,
       g % 10 = 0,
       date '2018-01-01' + (g * 23) % 3000
FROM generate_series(1, 120) AS g;

-- 320 activos tecnológicos
INSERT INTO app.activos (codigo, categoria_id, marca, modelo, serial, empleado_id,
                         estado, ubicacion, fecha_compra, valor_compra, ultima_actualizacion_so)
SELECT 'TS-' || (ARRAY['POR','ESC','SRV','RED','LIC','NUB','MOV'])[cat] || '-' || lpad(g::text, 4, '0'),
       cat,
       (ARRAY['Lenovo','Dell','HP','Cisco','Microsoft','AWS','Samsung'])[cat],
       (ARRAY['ThinkPad T14','OptiPlex 7010','PowerEdge R650','Catalyst 9200',
              'Microsoft 365 E3','EC2 t3.medium','Galaxy A55'])[cat],
       'SN' || md5(g::text)::varchar(12),
       CASE WHEN cat IN (1, 2, 7) THEN 1 + (g % 120) END,
       CASE WHEN g % 25 = 0 THEN 'MANTENIMIENTO'
            WHEN g % 40 = 0 THEN 'BODEGA'
            ELSE 'EN_USO' END,
       CASE WHEN cat = 6 THEN 'NUBE_AWS'
            WHEN cat = 1 AND g % 3 = 0 THEN 'REMOTO'
            ELSE 'OFICINA_BOGOTA' END,
       current_date - (200 + (random() * 1200)::int),
       (ARRAY[4200000, 3100000, 28000000, 6500000, 1300000, 450000, 1600000])[cat],
       CASE WHEN cat IN (1, 2, 3) THEN current_date - (random() * 200)::int END
FROM (
  SELECT g,
         CASE WHEN g <= 120 THEN 1   -- un portátil por empleado
              WHEN g <= 160 THEN 2
              WHEN g <= 166 THEN 3
              WHEN g <= 178 THEN 4
              WHEN g <= 238 THEN 5
              WHEN g <= 253 THEN 6
              ELSE 7 END AS cat
  FROM generate_series(1, 320) AS g
) s;

-- ~60.000 tickets en 2 años: 92 % cerrados, 5 % en proceso, 3 % abiertos
INSERT INTO app.tickets (activo_id, solicitante_id, tecnico_id, categoria, prioridad,
                         estado, titulo, descripcion, creado_en, cerrado_en)
SELECT 1 + (r1 * 319)::int,
       1 + (r2 * 119)::int,
       2 + 6 * (r3 * 19)::int,                       -- ids de Tecnología: 2, 8, 14, ...
       (ARRAY['HARDWARE','SOFTWARE','ACCESOS','RED','SEGURIDAD'])[1 + (r4 * 4)::int],
       CASE WHEN r5 < 0.50 THEN 'MEDIA' WHEN r5 < 0.75 THEN 'BAJA'
            WHEN r5 < 0.95 THEN 'ALTA' ELSE 'CRITICA' END,
       estado,
       (ARRAY['Equipo lento','No abre el correo','Restablecer contraseña','Sin acceso a la VPN',
              'Instalar software','Pantalla dañada','Correo sospechoso (phishing)',
              'Solicitud de permisos'])[1 + (r4 * 7)::int],
       'Ticket generado para laboratorio',
       creado,
       CASE WHEN estado = 'CERRADO' THEN creado + (1 + r1 * 72) * interval '1 hour' END
FROM (
  SELECT random() r1, random() r2, random() r3, random() r4, random() r5,
         CASE WHEN g % 100 < 92 THEN 'CERRADO'
              WHEN g % 100 < 97 THEN 'EN_PROCESO'
              ELSE 'ABIERTO' END AS estado,
         now() - random() * interval '730 days' AS creado
  FROM generate_series(1, 60000) AS g
) s;

INSERT INTO app.mantenimientos (activo_id, tipo, fecha, descripcion, costo)
SELECT 1 + (random() * 165)::int,
       (ARRAY['PREVENTIVO','CORRECTIVO','PARCHE_SO'])[1 + (random() * 2)::int],
       current_date - (random() * 365)::int,
       'Mantenimiento registrado para laboratorio',
       (random() * 400000)::numeric(12,2)
FROM generate_series(1, 400);

ANALYZE;
