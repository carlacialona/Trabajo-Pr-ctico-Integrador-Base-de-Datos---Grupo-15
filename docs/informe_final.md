# Informe final · TPI Bodegas del Atuel

Bases de Datos · Ingeniería en Sistemas · UTN Facultad Regional San Rafael · 2026

Integrantes: _completar_ · Roles por etapa: _completar_

## 1. Introducción y alcance

Sistema de gestión y distribución de una empresa vitivinícola ficticia: producción de uva (fincas, parcelas, cosechas y análisis), elaboración (bodegas y vinos), distribución (depósito central, ingresos, transferencias a salas) y venta (clientes de tres tipos, comprobantes con descuentos).

El foco del trabajo es la **capa de datos**: el modelo está normalizado hasta 3FN y las 15 reglas de negocio se garantizan **dentro de PostgreSQL** (constraints, funciones, procedimientos y triggers), de modo que se cumplen aunque alguien acceda a la base sin pasar por la API. La API y el front son el medio para mostrar que la base funciona como parte de un sistema: no calculan totales, descuentos ni stock.

| Componente | Tecnología |
| --- | --- |
| Base de datos | PostgreSQL 16 |
| Carga masiva | Python 3 + psycopg 3 + Faker (semilla fija), `COPY` |
| API | Node.js 22 + Express + `pg` (driver nativo, sin ORM), OpenAPI/Swagger |
| Front | HTML + CSS + JavaScript (sin frameworks), nginx |
| Contenedores | Docker Compose (base, carga, API, front) |
| Modelado | Mermaid (DER fuente `docs/der/der.mmd`, exportado a SVG y PNG) |

## 2. Modelo de datos

Ver [`01_modelo_de_datos.md`](01_modelo_de_datos.md): DER, entidades y claves (naturales y subrogadas), relaciones y cardinalidades, esquema relacional, dependencias funcionales y normalización, redundancias conservadas, decisiones de diseño (jerarquía de clientes, descuento almacenado, stock en tabla aparte, tipos de datos, acciones referenciales) y límites conocidos. Diccionario de datos: [`diccionario_datos.md`](diccionario_datos.md), generado desde el catálogo de la base.

## 3. Integridad y lógica en la base

Ver [`02_integridad_y_logica.md`](02_integridad_y_logica.md): guía de "dónde va cada regla", **tabla de trazabilidad regla → mecanismo → prueba** para RN-01 a RN-15, cobertura de los mínimos, funciones y su volatilidad, triggers y su momento, procedimientos transaccionales, roles y privilegios. Demostración de concurrencia: [`informes/etapa2_concurrencia.md`](informes/etapa2_concurrencia.md).

## 4. Carga masiva

Ver [`03_carga_masiva.md`](03_carga_masiva.md): catálogos reales en CSV, orden de carga, simulación cronológica para datos coherentes, reproducibilidad, estrategia frente a los triggers y sus riesgos, eficiencia de `COPY`. Conteos, tiempos y consultas de control: [`informes/etapa3_reporte_carga.md`](informes/etapa3_reporte_carga.md).

## 5. Índices y rendimiento

Ver [`04_indices_y_rendimiento.md`](04_indices_y_rendimiento.md). Tabla comparativa medida antes y después: [`informes/etapa4_indices.md`](informes/etapa4_indices.md). Planes completos: [`informes/etapa4_planes.md`](informes/etapa4_planes.md).

## 6. Consultas SQL

Ver [`05_consultas_sql.md`](05_consultas_sql.md) y los archivos de `consultas/`. Planes de S9 a S12: [`informes/etapa5_explain_avanzadas.md`](informes/etapa5_explain_avanzadas.md).

## 7. API y front

Ver [`06_api_y_front.md`](06_api_y_front.md): arquitectura, endpoints, traducción de errores, pruebas automáticas y demostración de inyección SQL fallida. Capturas: `capturas/`.

## 8. Despliegue en la nube

Ver [`07_despliegue_nube.md`](07_despliegue_nube.md): comparación de proveedores, pasos, seguridad, backup y restauración. _Completar con la URL pública, las capturas y los resultados obtenidos en la nube._

## 9. Conclusiones

_Completar por el grupo._ Puntos para desarrollar:

- **Dificultades**: generar datos históricos coherentes con un stock que nunca sea negativo (se resolvió simulando día por día en vez de generar cada tabla por separado); decidir qué hacer con los triggers durante la carga; distinguir un UPDATE manual de los importes del que hace el propio trigger (`pg_trigger_depth`).
- **Decisiones que cambiaríamos**: obligar la participación total de la jerarquía de clientes desde la base (constraint trigger diferido); modelar el encargado regional como persona si el negocio lo requiriera; generar historial de precios en la carga.
- **Aprendizajes**: un CHECK no alcanza para reglas que miran otras filas; PostgreSQL no indexa las claves foráneas y eso se nota al borrar; el orden de columnas de un índice compuesto importa; READ COMMITTED no evita una venta duplicada si se decide con un dato leído antes, y `FOR UPDATE` sí.
