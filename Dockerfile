FROM ubuntu:latest

# Update package lists and install required packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    postfix postfix-sqlite \
    dovecot-core \
    dovecot-lmtpd \
    dovecot-imapd \
    dovecot-pop3d \
    dovecot-sqlite \
    supervisor \
    sqlite3 \
    nginx \
    certbot python3-certbot-nginx python3-gpg dnsutils nano argon2 rsyslog

# Set users/groups
RUN groupadd -g 5000 vmail
RUN usermod -aG vmail dovecot
RUN useradd -u 5000 -g 5000 -G mail -d /var/mail -m vmail
RUN chown -R vmail:vmail /var/mail

# Set environment variables
ENV DATABASE_PATH=/var/mail/mailserver.db

# Copy admin script
COPY proot.sh /usr/local/bin/proot
RUN chmod +x /usr/local/bin/proot

# Copy postfix-wkd script
COPY postfix-wkd.py /var/mail/postfix-wkd.py
RUN chmod +x /var/mail/postfix-wkd.py
RUN mkdir /var/mail/.gnupg && echo "auto-key-locate local,wkd" > /var/mail/.gnupg/gpg.conf
RUN chown -R vmail:vmail /var/mail

# Copy configuration files
COPY supervisord.conf /etc/supervisord.conf
COPY dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf
COPY dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-mail.conf
COPY dovecot/conf.d/10-mailcrypt.conf /etc/dovecot/conf.d/10-mailcrypt.conf
COPY dovecot/conf.d/10-master.conf /etc/dovecot/conf.d/10-master.conf
COPY dovecot/conf.d/15-mailboxes.conf /etc/dovecot/conf.d/15-mailboxes.conf
COPY dovecot/conf.d/auth-sql.conf.ext /etc/dovecot/conf.d/auth-sql.conf.ext
COPY dovecot/dovecot.conf /etc/dovecot/dovecot.conf
COPY postfix/main.cf /etc/postfix/main.cf
COPY postfix/master.cf /etc/postfix/master.cf

# Configure Postfix to use Maildir
RUN postconf -e 'home_mailbox = /var/mail/Maildir/'

# Set permissions
RUN chmod 644 \
    /etc/postfix/master.cf \
    /etc/postfix/main.cf

# Create log file
RUN touch /var/log/mail.log && chmod a+w /var/log/mail*

EXPOSE 80 443 587 465 143 993 110 995 25

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh

# Set the entrypoint script as executable
RUN chmod +x /entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]