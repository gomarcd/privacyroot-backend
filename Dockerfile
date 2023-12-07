FROM ubuntu:latest

# Update package lists and install required packages
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    postfix postfix-sqlite sqlite3 opendkim opendkim-tools \
    dovecot-core dovecot-lmtpd dovecot-imapd dovecot-pop3d dovecot-sqlite \
    nginx certbot python3-certbot-nginx \
    python3-gpg dnsutils nano argon2 rsyslog supervisor

# Set users/groups
RUN groupadd -g 5000 vmail
RUN usermod -aG vmail dovecot
RUN useradd -u 5000 -g 5000 -G mail -d /var/mail -m vmail
RUN gpasswd -a postfix opendkim

# Set environment variables
ENV DATABASE_PATH=/var/mail/mailserver.db

# Copy scripts
COPY scripts/proot.sh /usr/local/bin/proot
COPY scripts/postfix-wkd.py /var/mail/postfix-wkd.py
RUN mkdir /var/mail/.gnupg && echo "auto-key-locate local,wkd" > /var/mail/.gnupg/gpg.conf
COPY scripts/opendkim.sh opendkim.sh
COPY scripts/nginx.sh nginx.sh

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
COPY opendkim/opendkim.conf /etc/opendkim.conf
COPY opendkim/default /etc/default/opendkim

# Configure Postfix to use Maildir
RUN postconf -e 'home_mailbox = /var/mail/Maildir/'

# Create log file
RUN touch /var/log/mail.log

# Copy the entrypoint script
COPY entrypoint.sh /entrypoint.sh

# Set permissions
RUN chmod +x /usr/local/bin/proot /var/mail/postfix-wkd.py /entrypoint.sh && \
    chmod a+w /var/log/mail* && \
    chmod 644 /etc/postfix/master.cf /etc/postfix/main.cf && \
    chown -R vmail:vmail /var/mail

EXPOSE 80 443 587 465 143 993 110 995 25

# Fix supervisor error "rsyslogd: imklog: cannot open kernel log (/proc/kmsg): Operation not permitted."
RUN sed -i '/imklog/s/^/#/' /etc/rsyslog.conf

# Certbot renewal cron task
RUN SLEEPTIME=$(awk 'BEGIN{srand(); print int(rand()*(3600+1))}'); echo "0 0,12 * * * root sleep $SLEEPTIME && certbot renew -q" | tee -a /etc/crontab > /dev/null

# Set the entrypoint
ENTRYPOINT ["/entrypoint.sh"]