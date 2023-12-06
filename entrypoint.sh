#!/bin/bash

# Read hostname from Docker -h option and domain/cname from -e flags
HOSTNAME=$(hostname)
DOMAIN=$DOMAIN
CNAME=$CNAME

# Get database path
DATABASE_PATH=$DATABASE_PATH

# Check if $HOSTNAME and $DOMAIN are provided
if [ -z "$HOSTNAME" ] || [ -z "$DOMAIN" ]; then
  echo "Error: Both HOSTNAME and DOMAIN must be provided. Check your docker run command or docker compose yaml."
  exit 1
fi

echo "Database path is: $DATABASE_PATH"
echo "Hostname set to: $HOSTNAME"
echo "Domain set to: $DOMAIN"

# Ensure Postfix has the needed DNS config
cp /etc/resolv.conf /var/spool/postfix/etc/

# Update /etc/mailname
echo "$DOMAIN" > /etc/mailname

# Set hostname in /etc/postfix/main.cf
grep -q '^\s*#*\s*myhostname =' /etc/postfix/main.cf && sed -i '/^\s*#*\s*myhostname =/s~.*~myhostname = '"$HOSTNAME~" /etc/postfix/main.cf || echo 'myhostname = '"$HOSTNAME" >> /etc/postfix/main.cf

# Add /etc/dovecot/dovecot-sql.conf configuration
echo "Configuring Dovecot for use with database..."
echo "Writing to /etc/dovecot/dovecot-sql.conf..."
touch /etc/dovecot/dovecot-sql.conf
echo "driver = sqlite
connect = $DATABASE_PATH

password_query = SELECT password, crypt AS userdb_mail_crypt_save_version, \
password AS userdb_mail_crypt_private_password, username, domain \
FROM mailbox WHERE username = '%n';" > /etc/dovecot/dovecot-sql.conf

echo "Dovecot configured."

# Check if database exists, if not, create it
if [ ! -f "$DATABASE_PATH" ]; then
    echo "Creating database..."
    sqlite3 $DATABASE_PATH <<EOF
CREATE TABLE mailbox (
    username varchar(255) NOT NULL,
    password varchar(255) NOT NULL,
    domain varchar(255) NOT NULL,
    crypt int(10) NOT NULL
);

CREATE TABLE virtual_domains (
    domain varchar(255) NOT NULL,
    aliases int(10) NOT NULL default '0',
    mailboxes int(10) NOT NULL default '0'
);

CREATE TABLE virtual_aliases (
    source varchar(255) NOT NULL,
    destination varchar(255) NOT NULL
);

INSERT INTO virtual_domains (domain,aliases,mailboxes) VALUES ('$DOMAIN',0,0);

INSERT INTO virtual_aliases (source,destination) VALUES ('admin@$DOMAIN','test@$DOMAIN');
EOF

    # Add test user
    echo "Creating test user..."
    service dovecot start
    proot -adduser -u test -p test
    service dovecot stop
    echo "Database created."
else
    echo "Database already exists. Continuing..."
fi

# Create or overwrite /etc/postfix/sqlite_virtual_domains_maps.cf
echo "Configuring Postfix for use with database..."
echo "Writing to /etc/postfix/sqlite_virtual_domains_maps.cf..."
echo "dbpath = $DATABASE_PATH
query = SELECT 1 FROM virtual_domains WHERE domain='%s'" > /etc/postfix/sqlite_virtual_domains_maps.cf

# Create or overwrite /etc/postfix/sqlite_virtual_mailbox_maps.cf
echo "Writing to sqlite_virtual_mailbox_maps.cf..."
echo "dbpath = $DATABASE_PATH
query = SELECT 1 FROM mailbox WHERE username || '@' || domain = '%s';" > /etc/postfix/sqlite_virtual_mailbox_maps.cf

# Create or overwrite /etc/postfix/sqlite_virtual_alias_maps.cf
echo "Writing to sqlite_virtual_alias_maps.cf..."
echo "dbpath = $DATABASE_PATH
query = SELECT destination FROM virtual_aliases WHERE source='%s'" > /etc/postfix/sqlite_virtual_alias_maps.cf

echo "Postfix configured."

# Function to check if a domain has a DNS record to avoid certbot failure
echo "Verifying required DNS A/CNAME records before running Certbot..."
check_dns() {
  local result=$(dig "$1" | awk '/^;; ANSWER SECTION:/{p=1; next} p{print; exit}')
  if [ -n "$result" ]; then
    echo "Valid DNS record found for domain $1. Certbot will request a certificate."
    return 0  # Success, domain has a DNS record
  else
    echo "NO DNS RECORD FOUND for domain $1. Skipping..."
    return 1  # Failure, domain does not have a DNS record
  fi
}

# Add any other specified subdomains
if [ -n "$CNAME" ]; then
  # Append domain name to each subdomain hostname
  SUBDOMAINS=$(echo "$CNAME" | sed "s/\([^,]\+\)/\1.$DOMAIN/g")

  # Add any domains with valid DNS records to a list to be requested by Certbot
  VALID_SUBDOMAINS=""
  IFS=',' read -ra SUBDOMAINS_ARRAY <<< "$SUBDOMAINS"
  first=true
  for subdomain in "${SUBDOMAINS_ARRAY[@]}"; do
    if check_dns "$subdomain"; then
      if $first; then
        VALID_SUBDOMAINS+="$subdomain"
        first=false
      else
        VALID_SUBDOMAINS+=",$subdomain"
      fi
    fi
  done

  # Combine the main domain and valid subdomains
  DOMAINS="$HOSTNAME,$VALID_SUBDOMAINS"
else
  # Use only the hostname if cname is not set
  DOMAINS="$HOSTNAME"
fi

# Register all domains (main domain and subdomains)
echo "Registering Let's Encrypt account under admin@$DOMAIN..."
certbot certonly --nginx --non-interactive --agree-tos --email admin@$DOMAIN -d "$DOMAIN"
certbot certonly --nginx --non-interactive --agree-tos --email admin@$DOMAIN -d "$DOMAINS"

# Reference the certificate and private key paths
CERT_PATH="/etc/letsencrypt/live/$HOSTNAME/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$HOSTNAME/privkey.pem"

# Creat nginx conf if it doesn't exist
NGINX_CONF="/etc/nginx/conf.d/$DOMAIN.conf"
if [ ! -f "$NGINX_CONF" ]; then
    echo "Creating nginx configuration..."
    touch $NGINX_CONF
    cat <<EOF > "$NGINX_CONF"
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384';

    location /.well-known/openpgpkey/ {
        default_type application/octet-stream;
        add_header Access-Control-Allow-Origin *;
        root /var/www/$DOMAIN;
        try_files \$uri \$uri/ =404;
    }
}
EOF
else
    echo "nginx configuration already exists. Continuing..."
fi

# Create WKD directory structure
mkdir -p /var/www/$DOMAIN/.well-known/openpgpkey/hu
touch /var/www/$DOMAIN/.well-known/openpgpkey/policy

# Certbot started nginx, stop it and let Supervisor manage nginx process
service nginx stop

# Update Dovecot configuration files with the cert and key paths
echo "Updating Dovecot configuration with TLS certificates..."

echo "Setting ssl = required..."
grep -q '^\s*#*\s*ssl =' /etc/dovecot/conf.d/10-ssl.conf && sed -i '/^\s*#*\s*ssl =/s/.*/ssl = required/' /etc/dovecot/conf.d/10-ssl.conf || echo 'ssl = required' >> /etc/dovecot/conf.d/10-ssl.conf

echo "Setting ssl_prefer_server_ciphers = yes..."
grep -q '^\s*#*\s*ssl_prefer_server_ciphers =' /etc/dovecot/conf.d/10-ssl.conf && sed -i '/^\s*#*\s*ssl_prefer_server_ciphers =/s/.*/ssl_prefer_server_ciphers = yes/' /etc/dovecot/conf.d/10-ssl.conf || echo 'ssl_prefer_server_ciphers = yes' >> /etc/dovecot/conf.d/10-ssl.conf

echo "Setting ssl_cert path..."
grep -q '^\s*#*\s*ssl_cert =' /etc/dovecot/conf.d/10-ssl.conf && sed -i "/^\s*#*\s*ssl_cert =/s~.*~ssl_cert = <$CERT_PATH~" /etc/dovecot/conf.d/10-ssl.conf || echo "ssl_cert = <$CERT_PATH" >> /etc/dovecot/conf.d/10-ssl.conf

echo "Setting ssl_key path..."
grep -q '^\s*#*\s*ssl_key =' /etc/dovecot/conf.d/10-ssl.conf && sed -i "/^\s*#*\s*ssl_key =/s~.*~ssl_key = <$KEY_PATH~" /etc/dovecot/conf.d/10-ssl.conf || echo "ssl_key = <$KEY_PATH" >> /etc/dovecot/conf.d/10-ssl.conf

echo "Setting ssl_min_protocol = TLSv1.2..."
grep -q '^\s*#*\s*ssl_min_protocol =' /etc/dovecot/conf.d/10-ssl.conf && sed -i "/^\s*#*\s*ssl_min_protocol =/s~.*~ssl_min_protocol = TLSv1.2~" /etc/dovecot/conf.d/10-ssl.conf || echo "ssl_min_protocol = TLSv1.2" >> /etc/dovecot/conf.d/10-ssl.conf

echo "Making backup of /etc/dovecot/conf.d/10-ssl.conf..."
cp /etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-ssl.bak

# Update Postfix configuration files with the cert and key paths
echo "Updating Postfix configuration with TLS certificates..."
grep -q '^\s*#*\s*smtpd_tls_cert_file =' /etc/postfix/main.cf && sed -i "/^\s*#*\s*smtpd_tls_cert_file =/s~.*~smtpd_tls_cert_file = $CERT_PATH~" /etc/postfix/main.cf || echo "smtpd_tls_cert_file = $CERT_PATH" >> /etc/postfix/main.cf
grep -q '^\s*#*\s*smtpd_tls_key_file =' /etc/postfix/main.cf && sed -i "/^\s*#*\s*smtpd_tls_key_file =/s~.*~smtpd_tls_key_file = $KEY_PATH~" /etc/postfix/main.cf || echo "smtpd_tls_key_file = $KEY_PATH" >> /etc/postfix/main.cf
echo "Making backup of /etc/postfix/main.cf..."
cp /etc/postfix/main.cf /etc/postfix/main.bak

echo "Updating ssl configuration..."
echo "Making backup of /etc/ssl/openssl.cnf..."
cp /etc/ssl/openssl.cnf /etc/ssl/openssl.bak

# Commenting out providers = provider_sect due to known issue
sed -i '/^\s*providers = provider_sect/s/^/#/' /etc/ssl/openssl.cnf

# Make sure vmail user owns /var/mail
chown -R vmail:vmail /var/mail

# Set up OpenDKIM
source opendkim.sh

# Start supervisord
exec supervisord -c /etc/supervisord.conf