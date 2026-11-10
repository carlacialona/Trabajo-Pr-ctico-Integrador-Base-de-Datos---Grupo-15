#!/bin/sh
# Restaura un backup en una base NUEVA y compara los conteos de filas.
# Uso:  DATABASE_URL_DESTINO=... sh db/scripts/restaurar.sh backups/archivo.dump
# La base destino debe existir y estar vacía. Los roles bodegas_api y
# bodegas_lectura deben existir en el servidor destino (007_roles.sql los crea).
set -e
: "${DATABASE_URL_DESTINO:?Definí DATABASE_URL_DESTINO}"
ARCHIVO=${1:?Indicá el archivo .dump}
pg_restore --dbname="$DATABASE_URL_DESTINO" --no-owner --exit-on-error "$ARCHIVO"
psql "$DATABASE_URL_DESTINO" -c "REFRESH MATERIALIZED VIEW mv_ventas_mensuales_sala" -q
echo "Conteos en la base restaurada:"
psql "$DATABASE_URL_DESTINO" -f "$(dirname "$0")/conteos.sql"
