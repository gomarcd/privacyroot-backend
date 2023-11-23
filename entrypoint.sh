#!/bin/bash

# Read the hostname from the -h option or use a default value
HOSTNAME=$(hostname)
DOMAIN=$domain
CNAME=$cname

echo "Hostname set to: $HOSTNAME"
echo "Domain set to: $DOMAIN"

# Update /etc/mailname
echo "$DOMAIN" > /etc/mailname

# Update postfix main.cf
sed -i "s/myhostname =.*/myhostname = $HOSTNAME/" /etc/postfix/main.cf

# Check if database exists, if not, create it
if [ ! -f "/var/mail/database/mailserver.db" ]; then
    echo "Creating database..."
    mkdir -p /var/mail/database/
    sqlite3 /var/mail/database/mailserver.db <<EOF
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

# Add any other specified subdomains
if [ -n "$CNAME" ]; then
  # Append the main domain to each subdomain
  SUBDOMAINS=$(echo "$CNAME" | sed "s/\([^,]\+\)/\1.$DOMAIN/g")
else
  # Use only the hostname if cname is not set
  SUBDOMAINS="$HOSTNAME"
fi

# Register the hostname (ie, mail.example.com) and any other subdomains (ie, imap.example.com)
certbot certonly --nginx --staging --non-interactive --agree-tos --email admin@$DOMAIN -d "$SUBDOMAINS"

# Reference the certificate and private key paths
CERT_PATH="/etc/letsencrypt/live/$HOSTNAME/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$HOSTNAME/privkey.pem"

# Update Dovecot configuration files with the cert and key paths

DOVE_10SSL="/etc/dovecot/conf.d/10-ssl.conf"
if [ ! -f "$DOVE_10SSL" ]; then
    touch "$DOVE_10SSL"
fi

# Set the paths in the dovecot configuration if not already set
if ! grep -q "ssl_cert =" "$DOVE_10SSL"; then
    echo "ssl_cert = <$CERT_PATH" >> "$DOVE_10SSL"
fi

if ! grep -q "ssl_key =" "$DOVE_10SSL"; then
    echo "ssl_key = <$KEY_PATH" >> "$DOVE_10SSL"
fi

# Set the other values in the dovecot configuration if not already set
if ! grep -q "ssl =" "$DOVE_10SSL"; then
    echo "ssl = required" >> "$DOVE_10SSL"
fi

# Start supervisord
exec supervisord -c /etc/supervisord.conf
