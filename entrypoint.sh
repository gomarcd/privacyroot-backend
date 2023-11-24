#!/bin/bash

# Read hostname from Docker -h option and domain/cname from -e flags
HOSTNAME=$(hostname)
DOMAIN=$domain
CNAME=$cname

# Check if $HOSTNAME and $DOMAIN are provided
if [ -z "$HOSTNAME" ] || [ -z "$DOMAIN" ]; then
  echo "Error: Both HOSTNAME and DOMAIN must be provided. Check your docker run command or docker compose yaml."
  exit 1
fi

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
certbot certonly --nginx --staging --non-interactive --agree-tos --email admin@$DOMAIN -d "$DOMAINS"

# Certbot stared nginx, stop it and let Supervisor manage nginx process
service nginx stop

# Reference the certificate and private key paths
CERT_PATH="/etc/letsencrypt/live/$HOSTNAME/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$HOSTNAME/privkey.pem"

# Update Dovecot configuration files with the certificate paths
DOVE_10SSL="/etc/dovecot/conf.d/10-ssl.conf"

# Overwrite or set the paths in the dovecot configuration
sed -i -e "/^ssl_cert /s|=.*$|= <$CERT_PATH|" \
       -e "/^ssl_key /s|=.*$|= <$KEY_PATH|" \
       -e "/^ssl /s|=.*$|= required|" \
       "$DOVE_10SSL"

# Start supervisord
exec supervisord -c /etc/supervisord.conf