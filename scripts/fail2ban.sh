apt-get update
apt-get install -y fail2ban iptables

touch /var/log/ssh.log
touch /var/log/mail.log

cat <<EOL > /etc/fail2ban/jail.local
[DEFAULT]
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
bantime  = 604800 # ban for 7 days
EOL

cat <<EOL > /etc/fail2ban/filter.d/postfix-sasl.conf
[INCLUDES]
before = common.conf
[Definition]
_daemon = postfix/smtpd
failregex = .*\[<ADDR>\].*authentication failed
EOL

service fail2ban force-reload