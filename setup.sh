#!/bin/bash

#v1.
# Raspberry Pi CPU Monitor Installer
# I will set up a template along with items and triggers to monitor
# a Raspberry Pi for critical information not normally gathered.
# Today I monitor:
# CPU Temperature, and will alert when exceeding 79 degrees.
# CPU Throttling and Capping status, I will alert on either condition.
# EEPROM Update Available, will I check once on install and then again
# every 6 hours.
# Most of the code here is to work around allowing the Zabbix user to
# execute as sudo without entering a password.

# I am ROOT?
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

safe_remove_file() {
  if [ -f "$1" ]; then
    rm "$1"
  fi
}

safe_remove_dir_if_empty() {
  if [ -d "$1" ] && [ -z "$(ls -A "$1")" ]; then
    rmdir "$1"
  fi
}

# To run vcgencmd commands
usermod -aG video zabbix

# Remove existing scripts and files if they exist
safe_remove_file /usr/local/bin/check_eeprom_update.sh
safe_remove_file /usr/local/bin/update_eeprom_status.sh
safe_remove_file /etc/zabbix/scripts/read_eeprom_status.sh
safe_remove_file /var/lib/zabbix/eeprom_status

# Remove cron job if it exists
echo "You may ignore any message that says, 'no crontab for root'."
crontab -l 2>/dev/null | grep -v '/usr/local/bin/update_eeprom_status.sh' | crontab -

# Determine Zabbix Agent service name and configuration directory based on existence
if [ -d "/etc/zabbix/zabbix_agent2.d" ]; then
  # Zabbix Agent 2.x detected
  ZABBIX_AGENT_SERVICE="zabbix-agent2"
  ZABBIX_AGENT_CONF_DIR="/etc/zabbix/zabbix_agent2.d"
  echo  "Determined that we are installing into zabbix-agent2."
elif [ -d "/etc/zabbix/zabbix_agentd.conf.d" ]; then
  # Zabbix Agent 1.x detected
  echo  "Determined that we are installing into zabbix-agent (not part deux, hot shot)."
  ZABBIX_AGENT_SERVICE="zabbix-agent"
  ZABBIX_AGENT_CONF_DIR="/etc/zabbix/zabbix_agentd.conf.d"
else
  echo "Nuts, I've failed. I can't figure out what version of Zabbix Agent is installed. That's crazy."
  exit 1
fi

# Create directories if they don't exist
mkdir -p /usr/local/bin
mkdir -p /etc/zabbix/scripts
mkdir -p /var/lib/zabbix

if [ -d "$ZABBIX_AGENT_CONF_DIR" ]; then
  conf_file="$ZABBIX_AGENT_CONF_DIR/raspberry_pi_eeprom.conf"
# Build the configuration file
if [ -f "$conf_file" ]; then
  rm "$conf_file"
  echo "### Option: UnsafeUserParameters
#       Allow all characters to be passed in arguments to user-defined parameters.
#       The following characters are not allowed:
#       \\ ' \" \` * ? [ ] { } ~ \$ ! & ; ( ) < > | # @
#       Additionally, newline characters are not allowed.
#       0 - do not allow
#       1 - allow
#
# Mandatory: no
# Range: 0-1
# Default:
UnsafeUserParameters=1

# Zabbix UserParameter for Raspberry Pi EEPROM update check
UserParameter=raspi.eeprom_update,/etc/zabbix/scripts/read_eeprom_status.sh

# Zabbix UserParameter for Raspberry Pi CPU temperature
UserParameter=raspi.cpuTemperature,vcgencmd measure_temp | grep -oP '\\d+\\.\\d+'

# Zabbix UserParameter for Raspberry Pi CPU throttled status
UserParameter=raspi.cpuThrottled,vcgencmd get_throttled | awk -F\"=\" '{print \$2}'" > "$conf_file"
fi
else
  echo "Zabbix Agent configuration directory ($ZABBIX_AGENT_CONF_DIR) not found. Please check your Zabbix Agent installation."
  exit 1
fi

# Create the check_eeprom_update.sh script
cat <<EOL > /usr/local/bin/check_eeprom_update.sh
#!/bin/bash

# Run the rpi-eeprom-update command and capture its output
output=\$(/usr/bin/rpi-eeprom-update)

# Check if there is an update available
if echo "\$output" | grep -q "UPDATE_REQUIRED"; then
  echo 1  # Update available
else
  echo 0  # No update available
fi
EOL

chmod 755 /usr/local/bin/check_eeprom_update.sh

# Create the update_eeprom_status.sh script
cat <<EOL > /usr/local/bin/update_eeprom_status.sh
#!/bin/bash

# Run the check_eeprom_update.sh script and store the result in a file
/usr/local/bin/check_eeprom_update.sh > /var/lib/zabbix/eeprom_status
EOL

chmod 755 /usr/local/bin/update_eeprom_status.sh

# Create the read_eeprom_status.sh script
cat <<EOL > /etc/zabbix/scripts/read_eeprom_status.sh
#!/bin/bash

# Read the EEPROM status from the file
cat /var/lib/zabbix/eeprom_status
EOL

chmod 755 /etc/zabbix/scripts/read_eeprom_status.sh

touch /var/lib/zabbix/eeprom_status
chown zabbix:zabbix /var/lib/zabbix/eeprom_status
chmod 644 /var/lib/zabbix/eeprom_status

# Add a cron job to run the update script every 6 hours
(echo "0 */6 * * * /usr/local/bin/update_eeprom_status.sh") | crontab -

# Run once to get an initial value for Zabbix
/usr/local/bin/update_eeprom_status.sh

systemctl restart "$ZABBIX_AGENT_SERVICE"

echo "Setup completed. Zabbix Agent is now configured to check for EEPROM updates every 6 hours."
