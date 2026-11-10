FROM nginx:1.27-alpine
COPY index.html /usr/share/nginx/html/
COPY css /usr/share/nginx/html/css
COPY js /usr/share/nginx/html/js
COPY docker-entrypoint.d/40-config-api.sh /docker-entrypoint.d/40-config-api.sh
RUN chmod +x /docker-entrypoint.d/40-config-api.sh
