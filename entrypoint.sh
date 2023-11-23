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
  # Use only the main domain if cname is not set
  SUBDOMAINS="$HOSTNAME"
fi

# Register the hostname (ie, mail.example.com) and any other subdomains (ie, imap.example.com)
certbot certonly --nginx --staging --non-interactive --agree-tos --email admin@$DOMAIN -d $(echo "$SUBDOMAINS" | sed 's/,/ -d /g')

# Start supervisord
exec supervisord -c /etc/supervisord.conf
