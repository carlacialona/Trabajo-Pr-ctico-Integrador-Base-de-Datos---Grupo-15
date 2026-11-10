#!/bin/sh
# Lo ejecuta la imagen oficial de PostgreSQL SOLO la primera vez que se crea
# el volumen de datos. Aplica las migraciones en orden y asigna las
# contraseñas de los roles desde variables de entorno (no hay secretos en el
# repositorio).
set -e

for archivo in /migrations/*.sql; do
  echo ">> Aplicando $archivo"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$archivo"
done

echo ">> Asignando contraseñas a los roles bodegas_api y bodegas_lectura"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v api_pass="$API_DB_PASSWORD" -v lectura_pass="$LECTURA_DB_PASSWORD" <<'EOSQL'
ALTER ROLE bodegas_api     PASSWORD :'api_pass';
ALTER ROLE bodegas_lectura PASSWORD :'lectura_pass';
EOSQL
