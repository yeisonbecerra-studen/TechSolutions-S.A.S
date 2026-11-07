"""TechSolutions S.A.S. - Gestión de Activos TI y Mesa de Ayuda.

App web mínima. Se conecta como app_user (rol_aplicacion): puede leer,
crear y actualizar, pero no borrar. Toda escritura queda en auditoria.log_cambios.
"""
import os

import psycopg
from fastapi import FastAPI, Form, Request
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from psycopg.rows import dict_row

DATABASE_URL = os.environ["DATABASE_URL"]

app = FastAPI(title="TechSolutions S.A.S.")
templates = Jinja2Templates(directory="templates")


def query(sql, params=None, one=False):
    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        rows = conn.execute(sql, params).fetchall()
    return rows[0] if one else rows


def execute(sql, params=None):
    with psycopg.connect(DATABASE_URL) as conn:
        conn.execute(sql, params)


@app.get("/")
def tablero(request: Request):
    resumen = query("""
        SELECT (SELECT count(*) FROM app.empleados WHERE activo) AS empleados,
               (SELECT count(*) FROM app.activos WHERE estado <> 'DADO_DE_BAJA') AS activos,
               (SELECT count(*) FROM app.tickets WHERE estado <> 'CERRADO') AS tickets_abiertos,
               (SELECT count(*) FROM app.v_equipos_sin_parches) AS sin_parches,
               (SELECT round(100.0 * count(*) FILTER (WHERE NOT mfa_activo) / count(*), 1)
                  FROM app.empleados WHERE activo) AS pct_sin_mfa
    """, one=True)
    por_prioridad = query("""
        SELECT prioridad, count(*) AS total FROM app.tickets
        WHERE estado <> 'CERRADO' GROUP BY prioridad
        ORDER BY array_position(ARRAY['CRITICA','ALTA','MEDIA','BAJA'], prioridad::text)
    """)
    por_categoria = query("""
        SELECT c.nombre, count(*) AS total, sum(a.valor_compra) AS valor
        FROM app.activos a JOIN app.categorias_activo c ON c.id = a.categoria_id
        GROUP BY c.nombre ORDER BY total DESC
    """)
    return templates.TemplateResponse(request, "tablero.html", {
        "r": resumen, "por_prioridad": por_prioridad, "por_categoria": por_categoria})


@app.get("/activos")
def activos(request: Request, q: str = ""):
    filas = query("""
        SELECT a.codigo, c.nombre AS categoria, a.marca, a.modelo, a.estado, a.ubicacion,
               e.nombres || ' ' || e.apellidos AS responsable, a.ultima_actualizacion_so
        FROM app.activos a
        JOIN app.categorias_activo c ON c.id = a.categoria_id
        LEFT JOIN app.empleados e ON e.id = a.empleado_id
        WHERE a.codigo ILIKE %(q)s OR a.marca ILIKE %(q)s OR c.nombre ILIKE %(q)s
        ORDER BY a.codigo LIMIT 200
    """, {"q": f"%{q}%"})
    categorias = query("SELECT id, nombre FROM app.categorias_activo ORDER BY nombre")
    return templates.TemplateResponse(request, "activos.html", {
        "filas": filas, "q": q, "categorias": categorias})


@app.post("/activos")
def crear_activo(codigo: str = Form(), categoria_id: int = Form(), marca: str = Form(),
                 modelo: str = Form(), serial: str = Form(), valor_compra: float = Form()):
    execute("""
        INSERT INTO app.activos (codigo, categoria_id, marca, modelo, serial,
                                 fecha_compra, valor_compra, ultima_actualizacion_so)
        VALUES (%s, %s, %s, %s, %s, current_date, %s, current_date)
    """, (codigo, categoria_id, marca, modelo, serial, valor_compra))
    return RedirectResponse(f"/activos?q={codigo}", status_code=303)


@app.get("/tickets")
def tickets(request: Request):
    filas = query("""
        SELECT t.id, t.prioridad, t.categoria, t.titulo, t.estado, t.creado_en,
               s.nombres || ' ' || s.apellidos AS solicitante
        FROM app.tickets t JOIN app.empleados s ON s.id = t.solicitante_id
        WHERE t.estado IN ('ABIERTO','EN_PROCESO') AND t.creado_en >= now() - interval '30 days'
        ORDER BY t.creado_en DESC
    """)
    empleados = query("SELECT id, nombres || ' ' || apellidos AS nombre FROM app.empleados ORDER BY 2")
    return templates.TemplateResponse(request, "tickets.html", {
        "filas": filas, "empleados": empleados})


@app.post("/tickets")
def crear_ticket(solicitante_id: int = Form(), categoria: str = Form(),
                 prioridad: str = Form(), titulo: str = Form()):
    execute("""
        INSERT INTO app.tickets (solicitante_id, categoria, prioridad, titulo)
        VALUES (%s, %s, %s, %s)
    """, (solicitante_id, categoria, prioridad, titulo))
    return RedirectResponse("/tickets", status_code=303)


@app.post("/tickets/{ticket_id}/cerrar")
def cerrar_ticket(ticket_id: int):
    execute("UPDATE app.tickets SET estado = 'CERRADO', cerrado_en = now() WHERE id = %s",
            (ticket_id,))
    return RedirectResponse("/tickets", status_code=303)


@app.get("/salud")
def salud():
    """Health check: en AWS lo consulta el balanceador (ALB) para la alta disponibilidad."""
    try:
        query("SELECT 1")
        return {"estado": "ok", "base_de_datos": "ok"}
    except psycopg.Error:
        return JSONResponse({"estado": "error", "base_de_datos": "sin conexión"}, status_code=503)
