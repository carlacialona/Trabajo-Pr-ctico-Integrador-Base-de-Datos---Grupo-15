#!/bin/sh
# Aplica todas las migraciones, en orden, sobre una base VACÍA.
# Uso:  DATABASE_URL=postgresql://usuario:clave@host:5432/base sh db/scripts/aplicar_migraciones.sh
# En la nube, DATABASE_URL es la del rol propietario/administrador y termina
# en ?sslmode=require.
set -e
: "${DATABASE_URL:?Definí DATABASE_URL}"
DIR=$(dirname "$0")/../migrations
for archivo in "$DIR"/*.sql; do
  echo ">> $archivo"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q -f "$archivo"
done
echo "Migraciones aplicadas. Falta asignar contraseñas a bodegas_api y bodegas_lectura:"
echo "  psql \"\$DATABASE_URL\" -c \"ALTER ROLE bodegas_api PASSWORD '...'\""
