#!/bin/bash

DKIM_PATH="/etc/opendkim/keys/$DOMAIN"

# Create signing table if it doesn't exist
if [ ! -f "/etc/opendkim/signing.table" ]; then
	echo "Updating /etc/opendkim/signing.table..."
	touch /etc/opendkim/signing.table
	cat <<EOF >> /etc/opendkim/signing.table
*@$DOMAIN    default._domainkey.$DOMAIN
*@*.$DOMAIN    default._domainkey.$DOMAIN
EOF
else
	echo "/etc/opendkim/signing.table already exists, skipping..."
fi

# Create key table if it doesn't exist
if [ ! -f "/etc/opendkim/key.table" ]; then
	echo "Updating /etc/opendkim/key.table..."
	touch /etc/opendkim/key.table
	cat <<EOF >> /etc/opendkim/key.table
default._domainkey.$DOMAIN     $DOMAIN:default:/etc/opendkim/keys/$DOMAIN/default.private
EOF
else
	echo "/etc/opendkim/key.table already exists, skipping..."
fi

# Create trusted hosts if it doesn't exist
if [ ! -f "/etc/opendkim/trusted.hosts" ]; then
	echo "Updating /etc/opendkim/trusted.hosts..."
	touch /etc/opendkim/trusted.hosts
	cat <<EOF >> /etc/opendkim/trusted.hosts
127.0.0.1
localhost

.$DOMAIN
EOF
else
	echo "/etc/opendkim/trusted.hosts already exists, skipping..."
fi

# Create opendkim postfix spool dir if it doesn't exist
if [ ! -d "/var/spool/postfix/opendkim" ]; then
	echo "Creating /var/spool/postfix/opendkim..."
	mkdir /var/spool/postfix/opendkim
else
	echo "/var/spool/postfix/opendkim already exists, skipping..."
fi

# Create DKIM keypair if it doesn't already exist
if [ ! -d "$DKIM_PATH" ]; then
	echo "Generating keypair..."
	mkdir -p $DKIM_PATH
	opendkim-genkey -b 2048 -d $DOMAIN -D $DKIM_PATH -s default -v
else
	echo "$DKIM_PATH already exists, skipping..."
fi

# Set permissions
chown -R opendkim:opendkim /etc/opendkim
chmod go-rw /etc/opendkim/keys
chown opendkim:postfix /var/spool/postfix/opendkim