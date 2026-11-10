# 8. Despliegue en la nube

> **Estado**: esta guía deja todo preparado para desplegar, pero el despliegue en sí lo tiene que hacer el grupo con su propia cuenta (crear cuentas en un proveedor no se puede automatizar desde el repositorio). Al terminar, completar la URL pública en el `README.md` y las capturas en `docs/capturas/`.

## 8.1 Elección del proveedor

El enunciado pide comparar al menos dos. Los planes gratuitos cambian seguido: **verificar las condiciones vigentes antes de elegir** y anotarlas acá.

| Criterio | Render (Postgres + Web Service + Static Site) | Neon (Postgres) + Render (API y front) | VPS propio con Docker Compose |
| --- | --- | --- | --- |
| Todo en un lugar | Sí | No (dos cuentas) | Sí |
| Red interna base ↔ API | Sí: la API usa la *Internal URL* y la base no necesita estar abierta | No: la API se conecta por internet con TLS | Sí: red de Docker |
| Restringir el puerto de la base | Reglas de IP entrantes (*Networking* → CIDR permitidos) | Según el plan | Firewall del servidor |
| HTTPS | Automático | Automático | Hay que configurarlo (por ejemplo Caddy) |
| Límites a verificar | La base gratuita **vence a los 30 días** según el changelog de Render; los servicios gratuitos se "duermen" sin uso | Almacenamiento y horas de cómputo del plan gratuito | Costo mensual |
| Esfuerzo | Bajo | Medio | Alto |

**Elegido: Render para los tres componentes** (base, API y front). Razón principal: la API se conecta a la base por la red interna del proveedor y el acceso externo a la base se puede cerrar con reglas de IP. Si la base gratuita vence antes de la defensa, la alternativa es Neon para la base (cambia solo `DATABASE_URL`).

Fuentes: [Render: crear y conectar Postgres](https://render.com/docs/postgresql-creating-connecting) (URL interna/externa, `sslmode=require`, reglas de IP), [Render: reglas de IP entrantes](https://render.com/docs/inbound-ip-rules), [Render: las bases gratuitas vencen a los 30 días](https://render.com/changelog/free-postgresql-instances-now-expire-after-30-days-previously-90), [Render: límites del plan gratuito](https://render.com/docs/free).

## 8.2 Pasos

### 1. Base de datos

1. Subir el repositorio a GitHub.
2. En Render: **New → Postgres**. Nombre `bodegas`, versión 16, región cercana (la misma que usarán la API y el front).
3. Copiar la **External Database URL** (para cargar desde tu máquina) y la **Internal Database URL** (para la API).

### 2. Migraciones y roles (con el rol administrador que crea Render)

Desde tu máquina, con `psql` instalado (o desde un contenedor `postgres:16`):

```bash
export DATABASE_URL="postgresql://USUARIO_ADMIN:CLAVE@HOST_EXTERNO/bodegas?sslmode=require"
sh db/scripts/aplicar_migraciones.sh
psql "$DATABASE_URL" -c "ALTER ROLE bodegas_api PASSWORD 'una-clave-larga-sin-simbolos'"
psql "$DATABASE_URL" -c "ALTER ROLE bodegas_lectura PASSWORD 'otra-clave-larga'"
```

En PowerShell: `$env:DATABASE_URL = "..."` y los `psql` iguales (el `.sh` se puede correr con Git Bash).

> El rol administrador del proveedor queda como **propietario** de los objetos. `007_roles.sql` crea `bodegas_api` y `bodegas_lectura` con privilegios mínimos. Las contraseñas **no** están en el repositorio.

### 3. Carga de datos

```bash
pip install -r db/seed/requirements.txt
python db/seed/cargar_datos.py                 # completa
python db/seed/cargar_datos.py --escala 0.1    # reducida, si el plan limita el almacenamiento
```

Con escala 0,1 se cargan unos 15.000 comprobantes y unos 52.000 renglones: se cumple el mínimo de 10.000 filas en una tabla. **Justificación** (para el informe): el plan gratuito limita el almacenamiento; la versión local mantiene el volumen completo. Después correr las consultas de control: `psql "$DATABASE_URL" -f db/seed/consultas_control.sql` (todas en 0).

### 4. API

1. **New → Web Service**, conectar el repositorio, *Root Directory* `api`, entorno Docker (usa `api/Dockerfile`) o Node con `npm ci` / `npm start`.
2. Variables de entorno:

| Variable | Valor |
| --- | --- |
| `DATABASE_URL` | Internal URL **cambiando usuario y clave por `bodegas_api`** |
| `DB_SSL` | `require` |
| `DB_SSL_REJECT_UNAUTHORIZED` | `false` (la red interna usa certificados autofirmados) |
| `CORS_ORIGIN` | la URL pública del front (por ejemplo `https://bodegas-front.onrender.com`) |

3. Desplegar y verificar `https://<api>.onrender.com/salud`: debe responder `"rol": "bodegas_api"`.

### 5. Front

1. **New → Static Site**, *Root Directory* `front`, sin comando de build, *Publish Directory* `.`.
2. Antes de desplegar, editar `front/js/config.js` con la URL pública de la API: `window.API_URL = 'https://<api>.onrender.com';` (no es un secreto: es una URL pública).
3. Verificar que el navegador muestre "API ok · rol bodegas_api" arriba a la derecha.

### 6. Restringir el acceso a la base

En la base → **Info → Networking**: reemplazar `0.0.0.0/0` por la IP pública de quien tenga que administrarla (`/32`). La API no se ve afectada porque usa la URL interna. Probar desde otra red (por ejemplo, datos del celular):

```bash
psql "postgresql://bodegas_lectura:CLAVE@HOST_EXTERNO/bodegas?sslmode=require" -c "select 1"
# Debe ser rechazada.
```

Conexión cifrada: Render rechaza conexiones externas con `sslmode=disable`. Comprobarlo: `psql "...?sslmode=disable"` debe fallar.

### 7. Backup y restauración

```bash
# Backup de la nube
DATABASE_URL="...externa con el rol administrador..." sh db/scripts/backup.sh backups/nube.dump
# Restaurar en una base NUEVA (local en Docker o una segunda base) y comparar conteos
createdb -h localhost -U bodegas_owner bodegas_restaurada
DATABASE_URL_DESTINO="postgresql://bodegas_owner:CLAVE@localhost:5432/bodegas_restaurada" \
  sh db/scripts/restaurar.sh backups/nube.dump
psql "$DATABASE_URL" -f db/scripts/conteos.sql > conteos_nube.txt
psql "$DATABASE_URL_DESTINO" -f db/scripts/conteos.sql > conteos_restaurada.txt
diff conteos_nube.txt conteos_restaurada.txt && echo "Conteos idénticos"
```

Este procedimiento se probó localmente: backup de la base completa (6,6 MB en formato custom), restauración en una base nueva y conteos idénticos en las 30 tablas.

### 8. Regla de negocio en la nube

Desde el front publicado, intentar vender más botellas que el stock de la sala: debe aparecer el mensaje `RN-09: stock insuficiente ...`. Guardar la captura.

## 8.3 Lista de control de seguridad

- [ ] La API usa `bodegas_api`, no el administrador (`/salud` lo muestra).
- [ ] Conexión con `sslmode=require`.
- [ ] El puerto de la base no está abierto a todo internet (reglas de IP).
- [ ] No hay secretos en el repositorio ni en su historial: `.env` está en `.gitignore`; las contraseñas se cargan en las variables del proveedor. Revisar con `git log -p | grep -i password` antes de entregar.
- [ ] Backup restaurado en una base nueva con conteos iguales.
- [ ] CORS limitado a la URL del front.
