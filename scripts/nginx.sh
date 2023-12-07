# Creat nginx conf for $DOMAIN if it doesn't exist
NGINX_DOMAIN_CONF="/etc/nginx/conf.d/$DOMAIN.conf"
if [ ! -f "$NGINX_DOMAIN_CONF" ]; then
    echo "Creating nginx configuration for $DOMAIN..."
    touch $NGINX_DOMAIN_CONF
    cat <<EOF > "$NGINX_DOMAIN_CONF"
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

    location /.well-known/ {
        default_type application/octet-stream;
        add_header Access-Control-Allow-Origin *;
        root /var/www/$DOMAIN;
        try_files \$uri \$uri/ =404;
    }
}
EOF
else
    echo "nginx configuration for $DOMAIN already exists. Continuing..."
fi

# Create nginx conf for mta-sts.$DOMAIN if it doesn't exist
NGINX_MTASTS_CONF="/etc/nginx/conf.d/mta-sts.$DOMAIN.conf"
if [ ! -f "$NGINX_MTASTS_CONF" ]; then
    echo "Creating nginx configuration for mta-sts.$DOMAIN..."
    touch $NGINX_MTASTS_CONF
    cat <<EOF > "$NGINX_MTASTS_CONF"
server {
    listen 80;
    server_name mta-sts.$DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name mta-sts.$DOMAIN;
    ssl_certificate /etc/letsencrypt/live/mta-sts.$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mta-sts.$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

    location /.well-known/ {
        default_type application/octet-stream;
        add_header Access-Control-Allow-Origin *;
        root /var/www/mta-sts.$DOMAIN;
        try_files \$uri \$uri/ =404;
    }
}
EOF
else
    echo "nginx configuration for mta-sts.$DOMAIN already exists. Continuing..."
fi