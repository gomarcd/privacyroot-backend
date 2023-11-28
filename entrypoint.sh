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

# Update /etc/mailname
echo "$DOMAIN" > /etc/mailname

# Set hostname in /etc/postfix/main.cf
grep -q '^\s*#*\s*myhostname =' /etc/postfix/main.cf && sed -i '/^\s*#*\s*myhostname =/s~.*~myhostname = '"$HOSTNAME~" /etc/postfix/main.cf || echo 'myhostname = '"$HOSTNAME" >> /etc/postfix/main.cf

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
EOF

    echo "Database created."
else
    echo "Database already exists. Continuing..."
fi

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
check_dns() {
  local result=$(dig "$1" | awk '/^;; ANSWER SECTION:/{p=1; next} p{print; exit}')
  if [ -n "$result" ]; then
    return 0  # Success, domain has a DNS record
  else
    echo "Domain $1 does not have a DNS record. Skipping..."
    return 1  # Failure, domain does not have a DNS record
  fi
}

# Add any other specified subdomains
if [ -n "$CNAME" ]; then
  # Append the main domain to each subdomain
  SUBDOMAINS=$(echo "$CNAME" | sed "s/\([^,]\+\)/\1.$DOMAIN/g")

  # Check DNS for each subdomain before adding to the list
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

# Staging
certbot certonly --nginx --staging --non-interactive --agree-tos --email admin@$DOMAIN -d "$DOMAINS"

# Certbot started nginx, stop it and let Supervisor manage nginx process
service nginx stop

# Reference the certificate and private key paths
CERT_PATH="/etc/letsencrypt/live/$HOSTNAME/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$HOSTNAME/privkey.pem"

# Update Dovecot configuration files with the cert and key paths

echo "Updating Dovecot configuration with TLS certificates..."
echo "Making backup of /etc/dovecot/conf.d/10-ssl.conf to /etc/dovecot/conf.d/10-ssl.bak"
cp /etc/dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-ssl.bak

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

# Update Postfix configuration files with the cert and key paths

echo "Updating Postfix configuration with TLS certificates..."
grep -q '^\s*#*\s*smtpd_tls_cert_file =' /etc/postfix/main.cf && sed -i "/^\s*#*\s*smtpd_tls_cert_file =/s~.*~smtpd_tls_cert_file = $CERT_PATH~" /etc/postfix/main.cf || echo "smtpd_tls_cert_file = $CERT_PATH" >> /etc/postfix/main.cf
grep -q '^\s*#*\s*smtpd_tls_key_file =' /etc/postfix/main.cf && sed -i "/^\s*#*\s*smtpd_tls_key_file =/s~.*~smtpd_tls_key_file = $KEY_PATH~" /etc/postfix/main.cf || echo "smtpd_tls_key_file = $KEY_PATH" >> /etc/postfix/main.cf

echo "Updating ssl configuration..."
echo "Making backup of /etc/ssl/openssl.cnf..."
cp /etc/ssl/openssl.cnf /etc/ssl/openssl.bak

echo "Commenting out providers = provider_sect due to known issue..."
sed -i '/^\s*providers = provider_sect/s/^/#/' /etc/ssl/openssl.cnf

# Start supervisord
exec supervisord -c /etc/supervisord.conf