# Check if the TIMEZONE environment variable is set in Docker
if [ -n "$TIMEZONE" ]; then
    # Use the provided timezone
    TZ="$TIMEZONE"
else
    # Use the default timezone
    TZ="UTC"
fi

# Check if the timezone is valid
if [ -f "/usr/share/zoneinfo/$TZ" ]; then
    # Set the timezone in /etc/timezone
    echo "$TZ" > /etc/timezone

    # Create a symbolic link to the timezone file
    ln -snf "/usr/share/zoneinfo/$TZ" /etc/localtime

    echo "Timezone set to $TZ"
else
    echo "Error: Timezone $TZ not found"
fi

# Restart fail2ban
service fail2ban force-reload