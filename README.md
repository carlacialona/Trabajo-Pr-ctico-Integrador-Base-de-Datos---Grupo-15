# Bodegas del Atuel · TPI Bases de Datos

Sistema de gestión y distribución de una empresa vitivinícola. Trabajo Práctico Integrador de Bases de Datos, Ingeniería en Sistemas, UTN Facultad Regional San Rafael (2026).

- **Base de datos**: PostgreSQL 16. Modelo en 3FN; las 15 reglas de negocio viven en la base (constraints, 8 funciones, 2 procedimientos, 12 triggers, 4 vistas, 3 roles).
- **Carga masiva**: Python + Faker con semilla fija. ~150.000 comprobantes y ~520.000 renglones.
- **API REST**: Node.js + Express + `pg` (SQL directo y parametrizado, sin ORM). Documentada con OpenAPI en `/docs`.
- **Front**: HTML + JavaScript, consume solo la API.
- **Todo con un comando**: `docker compose up --build`.

Trabajo individual: Carla Cialona (Grupo 15) · Versión en la nube: pendiente de despliegue · Informe: [`docs/informe_final.md`](docs/informe_final.md) (también en PDF: `docs/informe_final.pdf`) · Guía para la defensa: [`docs/GUIA_DEFENSA.md`](docs/GUIA_DEFENSA.md)

## Requisitos

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (incluye Docker Compose).
- Opcional, para correr cosas fuera de Docker: `psql` (PostgreSQL 16), Python 3.10+ y Node.js 20+.

## Levantar todo en local

```bash
cp .env.example .env          # en Windows: copy .env.example .env
# editar .env y cambiar las tres contraseñas
docker compose up --build
```

La primera vez:

1. `db` crea la base y aplica `db/migrations/001` a `009` en orden (`db/docker-init/00_init.sh`), y asigna las contraseñas de los roles desde `.env`.
2. `seed` hace la carga masiva (1 a 3 minutos; para una carga rápida poner `SEED_ESCALA=0.1` en `.env`). Si la base ya tiene datos, no hace nada.
3. `api` arranca cuando la carga terminó.

| Servicio | URL |
| --- | --- |
| Front | http://localhost:8080 |
| API | http://localhost:3000 (salud: `/salud`) |
| Documentación de la API | http://localhost:3000/docs |
| Base (solo desde tu máquina) | `localhost:5432`, base `bodegas` |

Empezar de cero (borra los datos): `docker compose down -v && docker compose up --build`.

Conectarse con `psql` dentro del contenedor: `docker compose exec db psql -U bodegas_owner -d bodegas`.

## Pruebas

```bash
# Pruebas de las reglas de negocio en SQL (terminan en ROLLBACK, no dejan cambios)
docker compose exec -T db psql -U bodegas_owner -d bodegas -v ON_ERROR_STOP=1 < db/tests/db_tests.sql

# Consultas de control de la carga (todas deben dar 0)
docker compose exec -T db psql -U bodegas_owner -d bodegas < db/seed/consultas_control.sql

# Pruebas automáticas de la API (con la base levantada)
cd api
npm install
# Linux/Mac:
DATABASE_URL=postgresql://bodegas_api:CLAVE_API@localhost:5432/bodegas npm test
# Windows PowerShell:
$env:DATABASE_URL = "postgresql://bodegas_api:CLAVE_API@localhost:5432/bodegas"; npm test
```

## Consultas de la sección 8

```bash
docker compose exec -T db psql -U bodegas_owner -d bodegas < consultas/select.sql
docker compose exec -T db psql -U bodegas_owner -d bodegas < consultas/update.sql   # cada una en BEGIN ... ROLLBACK
docker compose exec -T db psql -U bodegas_owner -d bodegas < consultas/insert.sql
docker compose exec -T db psql -U bodegas_owner -d bodegas < consultas/delete.sql
```

## Mediciones y reportes (opcional, requieren Python)

```bash
pip install -r db/seed/requirements.txt
export DATABASE_URL=postgresql://bodegas_owner:CLAVE@localhost:5432/bodegas
python db/bench/medir_indices.py          # Etapa 4: antes/después de los índices
python db/bench/demo_concurrencia.py      # Etapa 2: la última botella
python db/scripts/generar_diccionario.py  # regenera docs/diccionario_datos.md
python db/seed/cargar_datos.py --forzar --benchmark --reporte docs/informes/etapa3_reporte_carga.md
```

## Estructura del repositorio

```
/
├── README.md
├── docker-compose.yml
├── .env.example                 (copiar a .env; .env no se sube)
├── db/
│   ├── migrations/
│   │   ├── 001_esquema.sql      tipos, dominios, tablas, PK, FK
│   │   ├── 002_constraints.sql  UNIQUE, CHECK, DEFAULT
│   │   ├── 003_funciones.sql
│   │   ├── 004_procedimientos.sql
│   │   ├── 005_triggers.sql
│   │   ├── 006_vistas.sql
│   │   ├── 007_roles.sql
│   │   ├── 008_indices.sql
│   │   └── 009_comentarios.sql  descripciones (diccionario de datos)
│   ├── docker-init/             script que aplica las migraciones en Docker
│   ├── seed/                    CSV de catálogos, script de carga, consultas de control
│   ├── tests/db_tests.sql       pruebas de RN-01 a RN-15 y roles
│   ├── bench/                   medición de índices, demo de concurrencia, EXPLAIN
│   └── scripts/                 migraciones, backup, restauración, conteos, diccionario
├── consultas/                   insert.sql, update.sql, delete.sql, select.sql
├── api/                         API REST (src/, tests/, openapi.yaml)
├── front/                       front estático
└── docs/
    ├── informe_final.md
    ├── 01_modelo_de_datos.md … 07_despliegue_nube.md
    ├── diccionario_datos.md
    ├── GUIA_DEFENSA.md
    ├── der/                     DER (der.mmd fuente, der.svg, der.png)
    ├── informes/                reportes generados (carga, índices, planes, concurrencia)
    └── capturas/
```

## Notas

- **Windows**: el archivo `.gitattributes` fuerza fin de línea LF en los `.sh`. Si el contenedor `db` falla con `bad interpreter` o `\r`, ejecutar `git config core.autocrlf false`, volver a clonar y reintentar.
- Las contraseñas nunca van al repositorio: están en `.env` (local) o en las variables del proveedor (nube).
- La API se conecta con el rol `bodegas_api`, sin privilegios de propietario.
