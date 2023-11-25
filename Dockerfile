FROM ubuntu:latest

# Update package lists and install required packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    postfix \
    dovecot-core \
    dovecot-lmtpd \
    dovecot-imapd \
    dovecot-pop3d \
    dovecot-sqlite \
    supervisor \
    sqlite3 \
    nginx \
    certbot python3-certbot-nginx dnsutils nano

# Add dovecot to the mail group
RUN adduser dovecot mail

# Set environment variables
ENV DATABASE_PATH=/var/mail/mailserver.db

# Copy configuration files
COPY supervisord.conf /etc/supervisord.conf
COPY mailname /etc/mailname
COPY dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf
COPY dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-mail.conf
COPY dovecot/conf.d/10-mailcrypt.conf /etc/dovecot/conf.d/10-mailcrypt.conf
COPY dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf
COPY dovecot/conf.d/15-mailboxes.conf /etc/dovecot/conf.d/15-mailboxes.conf
COPY dovecot/dovecot.conf /etc/dovecot/dovecot.conf
COPY postfix/main.cf /etc/postfix/main.cf
COPY postfix/master.cf /etc/postfix/master.cf
COPY postfix/sqlite_virtual_alias_maps.cf /etc/postfix/sqlite_virtual_alias_maps.cf
COPY postfix/sqlite_virtual_domains_maps.cf /etc/postfix/sqlite_virtual_domains_maps.cf
COPY postfix/sqlite_virtual_mailbox_maps.cf /etc/postfix/sqlite_virtual_mailbox_maps.cf

# Copy database
COPY mailserver.db $DATABASE_PATH

# Configure Postfix to use Maildir
RUN postconf -e 'home_mailbox = /var/mail/Maildir/'

# Set permissions
RUN chmod 644 \
    /etc/postfix/master.cf \
    /etc/postfix/main.cf \
    /etc/postfix/sqlite_virtual_mailbox_maps.cf \
    /etc/postfix/sqlite_virtual_alias_maps.cf \
    /etc/postfix/sqlite_virtual_domains_maps.cf

# Create log file
RUN touch /var/log/mail.log && chmod a+w /var/log/mail*

EXPOSE 80 443 587 465 143 993 110 995 25

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh

# Set the entrypoint script as executable
RUN chmod +x /entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]

# Start Supervisor
#CMD ["supervisord", "-c", "/etc/supervisord.conf"]