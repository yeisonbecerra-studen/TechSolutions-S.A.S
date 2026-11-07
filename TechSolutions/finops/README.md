# FinOps – TCO, ROI y VAN

Compara cuánto cuesta en 3 años **renovar los servidores propios (On-Premise)** frente a **migrar a AWS** (us-east-1).

```bash
python3 finops/tco.py
```

- Solo necesita Python 3, sin librerías extra.
- Los supuestos (TRM, precios, energía, personal, tasa de descuento) están en el diccionario `SUPUESTOS`, al inicio del archivo. Cámbialos y vuelve a ejecutar.
- Los precios de AWS son **estimaciones on-demand aproximadas**. Valídalos en [AWS Pricing Calculator](https://calculator.aws) antes de la sustentación.
- ROI = (TCO On-Premise − TCO AWS) / TCO AWS.
- VAN = el ahorro de cada año (0 a 3) traído a valor de hoy con la tasa de descuento.
