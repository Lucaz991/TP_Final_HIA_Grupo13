from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import List
import statistics
from datetime import datetime

app = FastAPI(title="HIA Performance Analyser")

class SerieMetrica(BaseModel):
    metrica: str
    instancia: str
    valores: List[float]

class SolicitudAnalisis(BaseModel):
    fecha_consulta: str
    series: List[SerieMetrica]

@app.post("/analizar")
def analizar_rendimiento(payload: SolicitudAnalisis):
    if not payload.series:
        raise HTTPException(status_code=400, detail="No se recibieron series de métricas para analizar.")

    estado_global = "OPTIMO"
    detalles = []
    anomalias_count = 0

    for s in payload.series:
        if not s.valores:
            continue

        actual = s.valores[-1]
        promedio = statistics.mean(s.valores)
        maximo = max(s.valores)
        desvio = statistics.stdev(s.valores) if len(s.valores) > 1 else 0.0

        # Detección: pico estadístico (Z-score > 2) o umbral crítico (> 85%)
        es_anomalia_estadistica = (desvio > 0) and (abs(actual - promedio) > 2 * desvio)
        supera_umbral = actual > 85.0

        if supera_umbral or es_anomalia_estadistica:
            anomalias_count += 1
            if actual > 90.0:
                estado_global = "CRITICO"
            elif estado_global != "CRITICO":
                estado_global = "ADVERTENCIA"

            motivo = "Umbral crítico superado" if supera_umbral else "Desviación estadística anómala (Z > 2)"
            detalles.append(
                f"- **[ALERTA] {s.metrica}** en `{s.instancia}`: Actual **{actual:.2f}%** "
                f"(Prom: {promedio:.2f}%, Máx: {maximo:.2f}%, σ: {desvio:.2f}) — *{motivo}*"
            )
        else:
            detalles.append(
                f"- **[OK] {s.metrica}** en `{s.instancia}`: Actual **{actual:.2f}%** "
                f"(Prom: {promedio:.2f}%, Máx: {maximo:.2f}%)"
            )

    fecha_legible = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    reporte_md = (
        f"# Informe de Rendimiento de Infraestructura\n"
        f"- **Fecha de generación:** {fecha_legible}\n"
        f"- **Estado General del Clúster:** `{estado_global}`\n"
        f"- **Anomalías detectadas:** {anomalias_count}\n\n"
        f"## Detalle de Métricas Analizadas\n" + "\n".join(detalles)
    )

    return {
        "estado": estado_global,
        "anomalias": anomalias_count,
        "reporte_markdown": reporte_md
    }