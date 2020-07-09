FROM nginx:alpine
COPY hugo-site/public/ /usr/share/nginx/html/
