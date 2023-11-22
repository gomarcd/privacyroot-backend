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
    certbot

# Add dovecot to the mail group
RUN adduser dovecot mail

# Copy configuration files
COPY supervisord.conf /etc/supervisord.conf
COPY mailname /etc/mailname
COPY dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf
COPY dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-mail.conf
COPY dovecot/conf.d/10-mailcrypt.conf /etc/dovecot/conf.d/10-mailcrypt.conf
COPY dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf
COPY dovecot/conf.d/10-ssl.conf /etc/dovecot/conf.d/10-ssl.conf
COPY dovecot/conf.d/15-mailboxes.conf /etc/dovecot/conf.d/15-mailboxes.conf
COPY dovecot/dovecot-sql.conf /etc/dovecot/dovecot-sql.conf
COPY dovecot/dovecot.conf /etc/dovecot/dovecot.conf
COPY postfix/main.cf /etc/postfix/main.cf
COPY postfix/master.cf /etc/postfix/master.cf
COPY postfix/sqlite_virtual_alias_maps.cf /etc/postfix/sqlite_virtual_alias_maps.cf
COPY postfix/sqlite_virtual_domains_maps.cf /etc/postfix/sqlite_virtual_domains_maps.cf
COPY postfix/sqlite_virtual_mailbox_maps.cf /etc/postfix/sqlite_virtual_mailbox_maps.cf

# Copy database
COPY mailserver.db /var/mail/database/mailserver.db

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

# Start Supervisor
CMD ["supervisord", "-c", "/etc/supervisord.conf"]