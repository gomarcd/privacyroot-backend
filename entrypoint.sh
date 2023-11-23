#!/bin/bash

# Read the hostname from the -h option or use a default value
HOSTNAME=$(hostname)

echo "Hostname set to: $HOSTNAME"

# Extract domain from hostname
DOMAIN=$(echo "$HOSTNAME" | awk -F'.' '{if (NF > 1) {print $(NF-1)"."$NF} else {print $0}}')

# Update /etc/mailname
echo "$DOMAIN" > /etc/mailname

# Update /etc/mailname
echo "$DOMAIN" > /etc/mailname

# Update postfix main.cf
sed -i "s/myhostname =.*/myhostname = $HOSTNAME/" /etc/postfix/main.cf

# Update dovecot dovecot.conf
#sed -i "s/hostname =.*/hostname = $HOSTNAME/" /etc/dovecot/dovecot.conf

# Update nginx nginx.conf or other relevant configurations

# Run Certbot
#certbot --nginx -d $HOSTNAME

# Start supervisord
exec supervisord -c /etc/supervisord.conf
