# TechSolutions S.A.S. · Gestión de Activos TI y Mesa de Ayuda

Un solo proyecto para las tres ACA de la CUN:

| Materia | Qué aporta este sistema |
|---|---|
| Auditoría de Sistemas | Inventario de activos (antes no existía), equipos sin parches, empleados sin MFA, revisión de privilegios y log de auditoría de 365 días |
| Administración de Bases de Datos | PostgreSQL 16: roles y GRANT/REVOKE, auditoría con triggers, respaldo verificado, recuperación ante falla, mantenimiento automático, índices y monitoreo |
| Computación en la Nube | Copia local de la arquitectura AWS (app → EC2/ALB, BD → RDS Multi-AZ, respaldos → S3) y cálculo TCO/ROI/VAN en `finops/` |

Todos los datos son **ficticios** y las contraseñas son **solo de laboratorio**.

## Requisitos (Omarchy / Arch Linux)

```bash
sudo pacman -S --needed docker docker-compose
sudo systemctl enable --now docker
sudo usermod -aG docker $USER     # cerrar sesión y volver a entrar
```

No necesitas `psql` instalado: todo corre dentro del contenedor.

## Arranque

```bash
cd ~/Projects/TechSolutions
./ts.sh up
```

| Servicio | URL | Credenciales |
|---|---|---|
| App web | http://localhost:8081 | (sin login) |
| API (Swagger) | http://localhost:8081/docs | |
| Health check | http://localhost:8081/salud | |
| pgAdmin | http://localhost:5050 | admin@techsolutions.com.co / `Admin_Lab_2026` (servidor ya registrado; clave de BD: `Admin_Lab_2026`) |
| PostgreSQL | localhost:5433, BD `techsolutions` | `dba_admin` / `Admin_Lab_2026` |

La primera vez se crea todo solo (`db/init/`): esquema, datos (120 empleados, 320 activos, unos 60 000 tickets), triggers de auditoría y roles.

## Comandos (`./ts.sh ayuda`)

| Comando | Qué hace |
|---|---|
| `up` / `down` | Levanta / detiene los contenedores (los datos se conservan) |
| `reset` | Borra todo y recrea la base desde cero (pide confirmación) |
| `psql [usuario]` | Consola SQL, p. ej. `./ts.sh psql soporte_ana` |
| `diagnostico` | Versión, configuración, tamaños, privilegios peligrosos, respaldos, índices y hallazgos |
| `seguridad` | REVOKE al practicante, GRANT de rol y pruebas de permisos (algunos errores son esperados) |
| `auditoria` | Quién cambió qué, borrados masivos, retención |
| `backup` | `pg_dump` comprimido, verificación, SHA-256, registro en `auditoria.log_respaldos` y retención de 7 días |
| `verificar [archivo]` | Restaura el respaldo en una base temporal y compara conteos |
| `falla` | Falla controlada: `practicante_tmp` borra todos los tickets |
| `restaurar [archivo]` | Recupera el esquema `app` desde el último respaldo y **conserva** el log de auditoría |
| `mantenimiento` | Purga de logs de más de 365 días y VACUUM ANALYZE; reporte en `logs/` |
| `programar` | Instala timers de systemd: respaldo diario a las 02:00 y mantenimiento los domingos |
| `optimizar` | EXPLAIN ANALYZE antes y después de crear índices |
| `monitoreo` | Conexiones, caché, top de consultas (`pg_stat_statements`), filas muertas |
| `logs [n]` | Log del servidor (conexiones, DDL, consultas lentas) |

## Demo recomendada (orden)

```bash
./ts.sh reset          # empezar limpio
./ts.sh diagnostico    # 1. problema: practicante con DELETE/TRUNCATE, 0 respaldos, sin índices
./ts.sh backup         # 2. política de respaldo
./ts.sh verificar      #    el respaldo es restaurable
./ts.sh falla          # 3. incidente: tickets 60000 -> 0
./ts.sh auditoria      # 4. el log muestra a practicante_tmp
./ts.sh restaurar      # 5. recuperación: tickets -> 60000
./ts.sh seguridad      # 6. REVOKE + mínimo privilegio
./ts.sh backup         #    nuevo respaldo YA endurecido (uno viejo traería los permisos viejos)
./ts.sh optimizar      # 7. Seq Scan -> Index Scan
./ts.sh monitoreo      # 8. evidencia de rendimiento
./ts.sh mantenimiento
```

> Si corres `seguridad` antes de `falla`, el borrado falla con *permission denied*. Eso demuestra que el control funciona.

## Estructura

```
docker-compose.yml   db (PostgreSQL 16) + app (FastAPI) + pgadmin
ts.sh                herramienta de administración DBA
db/init/             01 esquema · 02 datos · 03 auditoría · 04 seguridad
sql/                 scripts de diagnóstico, seguridad, auditoría, optimización, monitoreo, mantenimiento
app/                 app web (FastAPI + Jinja2, conexión como app_user)
finops/              cálculo TCO/ROI/VAN para Computación en la Nube
tools/md2docx_apa.py convierte notas MD a DOCX con formato APA 7
backups/  logs/      salida de respaldos y mantenimiento (ignorados por git)
```

## Modelo de datos

- `app`: `departamentos`, `empleados`, `categorias_activo`, `activos`, `tickets`, `mantenimientos`; vistas `v_equipos_sin_parches` y `v_empleados_sin_mfa`.
- `auditoria`: `log_cambios` (trigger en empleados, activos y tickets, con `session_user`, aplicación, IP, y JSON antes y después), `log_respaldos`, vista `v_resumen_actividad`.

## Usuarios y roles

| Usuario | Rol | Puede |
|---|---|---|
| `dba_admin` | superusuario | todo (solo administración) |
| `app_user` | `rol_aplicacion` | leer, insertar, actualizar; **no borrar** |
| `soporte_ana` | `rol_soporte` | tickets y mantenimientos; empleados sin documento de identidad |
| `auditor_ext` | `rol_auditor` | solo lectura, incluido el esquema `auditoria` |
| `practicante_tmp` | (ALL al inicio) | situación inicial insegura; `seguridad` lo corrige |

## Equivalencia en AWS

| Local (Docker) | AWS |
|---|---|
| contenedor `app` | EC2 en Auto Scaling Group detrás de un ALB (health check `/salud`) |
| contenedor `db` | Amazon RDS for PostgreSQL Multi-AZ |
| `ts.sh backup` + `backups/` | snapshots automáticos de RDS + `pg_dump` a S3 |
| log de PostgreSQL / `auditoria.log_cambios` | CloudWatch Logs (retención de 365 días) |
| contraseñas en `04_seguridad.sql` | AWS Secrets Manager |
| pgAdmin | no se expone; acceso administrativo por SSM Session Manager |

## Generar los DOCX en APA

```bash
uv run --with python-docx tools/md2docx_apa.py "ruta/nota.md"
```
