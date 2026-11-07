"""TechSolutions S.A.S. - Evaluación FinOps: TCO a 3 años On-Premise vs AWS, ROI y VAN.

Uso:  python3 finops/tco.py

Todos los supuestos están en SUPUESTOS. Los precios de AWS son estimaciones
on-demand aproximadas de la región us-east-1 (N. Virginia); deben validarse con
AWS Pricing Calculator (https://calculator.aws) en la fecha de la sustentación.
"""

HORAS_MES = 730
ANIOS = 3

SUPUESTOS = {
    "trm_cop_usd": 4100,          # tasa de cambio supuesta COP por USD
    "tasa_descuento": 0.12,       # 12 % efectivo anual para el VAN
    # Escenario: la infraestructura actual llegó a fin de vida útil y debe renovarse.
    # La decisión es: comprar servidores nuevos (on-premise) o migrar a AWS.

    # ---- AWS (USD/mes, on-demand us-east-1) ---------------------------------
    "aws": {
        "EC2 2x t3.medium (app, Auto Scaling)": 2 * 0.0416 * HORAS_MES,
        "EBS gp3 2x30 GB (discos EC2)": 2 * 30 * 0.08,
        "RDS PostgreSQL db.t3.medium Multi-AZ": 0.144 * HORAS_MES,
        "RDS almacenamiento gp3 100 GB Multi-AZ": 100 * 0.23,
        "Application Load Balancer (+1 LCU)": (0.0225 + 0.008) * HORAS_MES,
        "NAT Gateway (+50 GB procesados)": 0.045 * HORAS_MES + 50 * 0.045,
        "S3 respaldos 200 GB + solicitudes": 200 * 0.023 + 1.0,
        "CloudWatch (logs 365 días, métricas, alarmas)": 10 * 0.50 + 50 * 0.03 + 5.0,
        "AWS WAF (1 ACL, 5 reglas, 2 M solicitudes)": 5 + 5 * 1 + 2 * 0.60,
        "Transferencia de datos salida 100 GB": 100 * 0.09,
        "Secrets Manager (5 secretos)": 5 * 0.40,
        "Site-to-Site VPN oficina Bogotá": 0.05 * HORAS_MES,
        "Plan de soporte AWS Developer": 29.0,
    },
    # Descuentos por compromiso a 1 año (Compute Savings Plan / RDS Reserved), aprox.
    "descuento_ec2_savings_plan": 0.28,
    "descuento_rds_reservada": 0.35,
    "aws_migracion_usd": 5000,            # única vez: 160 h de migración, pruebas y capacitación
    "aws_personal_fte": 0.25,             # fracción de un administrador cloud

    # ---- On-Premise ----------------------------------------------------------
    "onprem_capex_usd": {
        "2 servidores (rack 1U, 64 GB RAM, RAID)": 2 * 7000,
        "Almacenamiento NAS/SAN 8 TB": 5000,
        "UPS, rack, PDU y aire acondicionado": 3000,
        "Firewall y switches de centro de datos": 2500,
        "Equipo de respaldo (NAS secundario)": 2000,
        "Licencias (sistema operativo y virtualización)": 4000,
    },
    "onprem_consumo_kw": 0.8,             # servidores + almacenamiento + red
    "onprem_pue": 1.8,                    # eficiencia energética de un cuarto de servidores pequeño
    "tarifa_kwh_cop": 900,                # tarifa comercial aproximada Bogotá
    "onprem_mantenimiento_pct": 0.15,     # garantía/soporte anual sobre hardware
    "onprem_canal_internet_usd_mes": 150, # canal dedicado adicional para publicar servicios
    "onprem_respaldo_externo_usd_anio": 1500,  # custodia externa de copias
    "onprem_renovacion_anio3_usd": 1500,  # discos y baterías UPS
    "onprem_personal_fte": 0.5,

    # Administrador de infraestructura: salario + 52 % de carga prestacional
    "salario_admin_cop_mes": 6_000_000,
    "factor_prestacional": 1.52,
}

S = SUPUESTOS


def usd(v):
    return f"US$ {v:>10,.0f}"


def cop(v_usd):
    return f"COP {v_usd * S['trm_cop_usd']:>14,.0f}"


def tabla(titulo, filas, total=None):
    print(f"\n{titulo}")
    print("-" * 78)
    for nombre, v in filas:
        print(f"  {nombre:<48}{usd(v)}  {cop(v)}")
    if total is not None:
        print("-" * 78)
        print(f"  {'TOTAL':<48}{usd(total)}  {cop(total)}")


def personal_anual(fte):
    return S["salario_admin_cop_mes"] * S["factor_prestacional"] * 12 * fte / S["trm_cop_usd"]


def calcular():
    # ---------- AWS ----------
    aws_mes = sum(S["aws"].values())
    ec2 = S["aws"]["EC2 2x t3.medium (app, Auto Scaling)"]
    rds = S["aws"]["RDS PostgreSQL db.t3.medium Multi-AZ"]
    ahorro_compromiso = ec2 * S["descuento_ec2_savings_plan"] + rds * S["descuento_rds_reservada"]
    aws_mes_opt = aws_mes - ahorro_compromiso
    aws_infra_anual = aws_mes_opt * 12
    aws_personal = personal_anual(S["aws_personal_fte"])
    aws_anual = aws_infra_anual + aws_personal

    # ---------- On-Premise ----------
    capex = sum(S["onprem_capex_usd"].values())
    hardware = capex - S["onprem_capex_usd"]["Licencias (sistema operativo y virtualización)"]
    energia = S["onprem_consumo_kw"] * S["onprem_pue"] * 8760 * S["tarifa_kwh_cop"] / S["trm_cop_usd"]
    onprem_opex = {
        "Energía y refrigeración": energia,
        "Mantenimiento y garantías (15 % hardware)": hardware * S["onprem_mantenimiento_pct"],
        "Canal de internet dedicado adicional": S["onprem_canal_internet_usd_mes"] * 12,
        "Custodia externa de respaldos": S["onprem_respaldo_externo_usd_anio"],
        f"Personal ({S['onprem_personal_fte']} FTE administrador)": personal_anual(S["onprem_personal_fte"]),
    }
    onprem_anual = sum(onprem_opex.values())

    # ---------- Flujos por año (año 0 = inversión) ----------
    onprem_flujo = [capex] + [onprem_anual] * ANIOS
    onprem_flujo[3] += S["onprem_renovacion_anio3_usd"]
    aws_flujo = [S["aws_migracion_usd"]] + [aws_anual] * ANIOS

    tco_onprem = sum(onprem_flujo)
    tco_aws = sum(aws_flujo)
    ahorros = [o - a for o, a in zip(onprem_flujo, aws_flujo)]
    van = sum(f / (1 + S["tasa_descuento"]) ** t for t, f in enumerate(ahorros))
    roi = (tco_onprem - tco_aws) / tco_aws

    # ---------- Impresión ----------
    print("=" * 78)
    print(" TechSolutions S.A.S. - TCO a 3 años: On-Premise vs AWS (us-east-1)")
    print(f" TRM supuesta: {S['trm_cop_usd']:,} COP/USD   Tasa de descuento VAN: {S['tasa_descuento']:.0%} E.A.")
    print(" Precios AWS aproximados; validar en https://calculator.aws")
    print("=" * 78)

    tabla("1. AWS - costo mensual on-demand (USD/mes)", list(S["aws"].items()), aws_mes)
    tabla("   Optimización FinOps (compromiso 1 año)", [
        ("(-) Compute Savings Plan EC2 (28 %)", -ec2 * S["descuento_ec2_savings_plan"]),
        ("(-) Instancia reservada RDS (35 %)", -rds * S["descuento_rds_reservada"]),
    ], aws_mes_opt)
    tabla("   AWS - costo anual", [
        ("Infraestructura optimizada (x12)", aws_infra_anual),
        (f"Personal ({S['aws_personal_fte']} FTE administrador cloud)", aws_personal),
    ], aws_anual)

    tabla("2. On-Premise - inversión inicial (CAPEX, año 0)", list(S["onprem_capex_usd"].items()), capex)
    tabla("   On-Premise - costo anual (OPEX)", list(onprem_opex.items()), onprem_anual)

    print("\n3. Flujo de costos por año (USD)")
    print("-" * 78)
    print(f"  {'Año':<8}{'On-Premise':>16}{'AWS':>16}{'Ahorro':>16}")
    for t in range(ANIOS + 1):
        print(f"  {t:<8}{onprem_flujo[t]:>16,.0f}{aws_flujo[t]:>16,.0f}{ahorros[t]:>16,.0f}")
    print("-" * 78)
    print(f"  {'TCO':<8}{tco_onprem:>16,.0f}{tco_aws:>16,.0f}{tco_onprem - tco_aws:>16,.0f}")

    print("\n4. Indicadores")
    print("-" * 78)
    print(f"  TCO 3 años On-Premise            {usd(tco_onprem)}  {cop(tco_onprem)}")
    print(f"  TCO 3 años AWS                   {usd(tco_aws)}  {cop(tco_aws)}")
    print(f"  Ahorro total                     {usd(tco_onprem - tco_aws)}  {cop(tco_onprem - tco_aws)}"
          f"  ({(tco_onprem - tco_aws) / tco_onprem:.1%})")
    print(f"  ROI de migrar ((TCO on-prem - TCO AWS) / TCO AWS)   {roi:.1%}")
    print(f"  VAN del ahorro al {S['tasa_descuento']:.0%}            {usd(van)}  {cop(van)}")
    print(f"  Costo AWS on-demand sin optimizar: {usd(aws_mes * 12)} /año")
    print("=" * 78)


if __name__ == "__main__":
    calcular()
