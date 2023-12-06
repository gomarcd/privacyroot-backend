#!/bin/bash

echo "Updating /etc/opendkim.conf..."
echo "LogWhy               yes"
grep -q '^\s*#*\s*LogWhy\s\+' /etc/opendkim.conf && sed -i "/^\s*#*\s*LogWhy\s\+/s~.*~LogWhy                  yes~" /etc/opendkim.conf || echo "LogWhy                  yes" >> /etc/opendkim.conf