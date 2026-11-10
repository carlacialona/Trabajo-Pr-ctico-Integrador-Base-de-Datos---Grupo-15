#!/bin/sh
# Genera un backup completo en formato "custom" de pg_dump (comprimido).
# Uso:  DATABASE_URL=... sh db/scripts/backup.sh [archivo]
# Con Docker:  docker compose exec db pg_dump -U bodegas_owner -d bodegas -Fc > backups/bodegas.dump
set -e
: "${DATABASE_URL:?Definí DATABASE_URL}"
SALIDA=${1:-backups/bodegas_$(date +%Y%m%d_%H%M).dump}
mkdir -p "$(dirname "$SALIDA")"
pg_dump "$DATABASE_URL" --format=custom --no-owner --file="$SALIDA"
echo "Backup generado: $SALIDA ($(du -h "$SALIDA" | cut -f1))"
