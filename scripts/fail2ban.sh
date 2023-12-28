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
_daemon = (?:postfix/smtp(d|s){1,2}|postfix/submission/smtp(d|s){1,2})
failregex = ^%(__prefix_line)swarning: [-._\w]+\[<HOST>\]: SASL ((?i)LOGIN|PLAIN|(?:CRAM|DIGEST)-MD5) authentication failed:?(\s?[A-Za-z0-9+/:]*={0,4})?\s*$
EOL

service fail2ban force-reload