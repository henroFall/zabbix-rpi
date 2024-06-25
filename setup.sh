#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Function to safely remove files
safe_remove_file() {
  if [ -f "$1" ]; then
    rm "$1"
  fi
}

# Function to safely remove directories if empty
safe_remove_dir_if_empty() {
  if [ -d "$1" ] && [ -z "$(ls -A "$1")" ]; then
    rmdir "$1"
  fi
}

# Add Zabbix user to 'video' group to run vcgencmd commands
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
elif [ -d "/etc/zabbix/zabbix_agentd.conf.d" ]; then
  # Zabbix Agent 1.x detected
  ZABBIX_AGENT_SERVICE="zabbix-agent"
  ZABBIX_AGENT_CONF_DIR="/etc/zabbix/zabbix_agentd.conf.d"
else
  echo "Unable to determine Zabbix Agent version. Check Zabbix Agent installation."
  exit 1
fi

# Create directories if they don't exist
mkdir -p /usr/local/bin
mkdir -p /etc/zabbix/scripts
mkdir -p /var/lib/zabbix

# Add the UnsafeUserParameters setting and UserParameter to the Zabbix agent configuration if not already present
if [ -d "$ZABBIX_AGENT_CONF_DIR" ]; then
  conf_file="$ZABBIX_AGENT_CONF_DIR/raspberry_pi_eeprom.conf"

  # Check if the configuration file exists
  if [ ! -f "$conf_file" ]; then
    echo "Configuration file ($conf_file) not found. Creating a new one."
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
  else
    # Add the UnsafeUserParameters setting if not already present
    if ! grep -q "UnsafeUserParameters=1" "$conf_file"; then
      echo "UnsafeUserParameters=1" >> "$conf_file"
    fi

    # Add the UserParameter for EEPROM update if not already present
    if ! grep -q "UserParameter=raspi.eeprom_update,/etc/zabbix/scripts/read_eeprom_status.sh" "$conf_file"; then
      echo "UserParameter=raspi.eeprom_update,/etc/zabbix/scripts/read_eeprom_status.sh" >> "$conf_file"
    fi

    # Add the UserParameter for CPU temperature if not already present
    if ! grep -q "UserParameter=raspi.cpuTemperature,vcgencmd measure_temp | grep -oP '\\d+\\.\\d+'" "$conf_file"; then
      echo "UserParameter=raspi.cpuTemperature,vcgencmd measure_temp | grep -oP '\\d+\\.\\d+'" >> "$conf_file"
    fi

    # Add the UserParameter for CPU throttled status if not already present
    if ! grep -q "UserParameter=raspi.cpuThrottled,vcgencmd get_throttled | awk -F\"=\" '{print \$2}'" "$conf_file"; then
      echo "UserParameter=raspi.cpuThrottled,vcgencmd get_throttled | awk -F\"=\" '{print \$2}'" >> "$conf_file"
    fi
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

# Make the check_eeprom_update.sh script executable
chmod 755 /usr/local/bin/check_eeprom_update.sh

# Create the update_eeprom_status.sh script
cat <<EOL > /usr/local/bin/update_eeprom_status.sh
#!/bin/bash

# Run the check_eeprom_update.sh script and store the result in a file
/usr/local/bin/check_eeprom_update.sh > /var/lib/zabbix/eeprom_status
EOL

# Make the update_eeprom_status.sh script executable
chmod 755 /usr/local/bin/update_eeprom_status.sh

# Create the read_eeprom_status.sh script
cat <<EOL > /etc/zabbix/scripts/read_eeprom_status.sh
#!/bin/bash

# Read the EEPROM status from the file
cat /var/lib/zabbix/eeprom_status
EOL

# Make the read_eeprom_status.sh script executable
chmod 755 /etc/zabbix/scripts/read_eeprom_status.sh

# Ensure the Zabbix user can read the status file
touch /var/lib/zabbix/eeprom_status
chown zabbix:zabbix /var/lib/zabbix/eeprom_status
chmod 644 /var/lib/zabbix/eeprom_status

# Add a cron job to run the update script every 6 hours
(echo "0 */6 * * * /usr/local/bin/update_eeprom_status.sh") | crontab -

# Run Once
/usr/local/bin/update_eeprom_status.sh

# Restart the Zabbix Agent service
systemctl restart "$ZABBIX_AGENT_SERVICE"

echo "Setup completed. Zabbix Agent is now configured to check for EEPROM updates every 6 hours."
