#!/bin/sh
# Genera js/config.js con la URL de la API tomada de la variable API_URL.
set -e
echo "window.API_URL = '${API_URL:-http://localhost:3000}';" > /usr/share/nginx/html/js/config.js
echo "config.js generado con API_URL=${API_URL:-http://localhost:3000}"
