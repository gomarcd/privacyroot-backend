apt-get update
apt-get install -y fail2ban iptables

touch /var/log/ssh.log
touch /var/log/mail.log

JAIL_LOCAL_CONF="[DEFAULT]
banaction = iptables-allports

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/ssh.log
maxretry = 5
bantime  = 604800 # ban for 7 days

[sasl]
enabled  = true
port     = smtp
filter   = postfix-sasl
logpath  = /var/log/mail.log
maxretry = 5
ignoreip = 127.0.0.1/8 172.0.0.0/8
bantime  = 604800 # ban for 7 days"

POSTFIX_SASL_CONF="[INCLUDES]
before = common.conf
[Definition]
_daemon = postfix/smtpd
failregex = .*\[<ADDR>\].*authentication failed"

echo $JAIL_LOCAL_CONF > /etc/fail2ban/jail.local
echo $POSTFIX_SASL_CONF > /etc/fail2ban/filter.d/postfix-sasl.conf

service fail2ban force-reload