# ZABBIX-RPI

This repository contains a Zabbix template and setup script to monitor Raspberry Pi devices. 

I know I need to reformat this and submit it to the community, I will... But I just got this done and wanted to store it, and maybe someone will find it useful in the meantime. I do. I have a raspi in the garage running a display, it cooks! I also have one in a closet that gets into a computing backlog sometimes and heats up... So I enjoy my fruits here, maybe you will, too!

The template collects the following metrics:

- CPU Temperature
- CPU Throttling and Capping Status
- EEPROM Update Status

The template triggers alerts for the following conditions:
- CPU temperature exceeding 79 degrees Celsius
- CPU throttling and capping due to over-temperature or power issues
- Available EEPROM updates

Tested on Zabbix 7.0 with Zabbix Agent 2, but it should also work with Zabbix Agent 1 - the setup script does hunt for the folders and files by their 1.x and 2.x names... It really should work!

## Prerequisites

- Raspberry Pi running a compatible Linux distribution.
- Zabbix Agent installed (version 1.x or 2.x).

### Raspberry Pi OS Users
If you are using Raspberry Pi OS, the required tools (`vcgencmd` and `rpi-eeprom-update`) are already pre-installed. You can skip directly to the setup instructions.

### Users of Other Linux Distributions
The setup script will handle the detection and installation of any missing tools or repositories necessary for your Raspberry Pi. Simply run the script, and it will ensure all dependencies are met.

## Setup Instructions

1. **Automated Installation and Setup**

    Execute the following command to automatically set up your Raspberry Pi for Zabbix monitoring. This script handles all necessary configurations, including checking for and installing any required packages:

    ```
    git clone https://github.com/henroFall/zabbix-rpi.git
    cd zabbix-rpi
    chmod +x setup.sh
    sudo ./setup.sh
    ```

2. **Import the Zabbix Template**

    - Log in to your Zabbix web interface.
    - Navigate to **Configuration** -> **Templates**.
    - Click on **Import**.
    - Select the `zbx_rsapi_template.yaml` file from the cloned directory and import it.

3. **Link the Template to Your Host**

    - Go to **Configuration** -> **Hosts**.
    - Select the host representing your Raspberry Pi.
    - Access the **Templates** tab and click **Link new template**.
    - Search for and select the "Raspberry Pi" template.
    - Click **Add** and then **Update**.

## Troubleshooting

### Ensure the Zabbix Agent is Running

- **For Zabbix Agent 2:**
    ```
    sudo systemctl status zabbix-agent2
    ```

- **For Zabbix Agent 1:**
    ```
    sudo systemctl status zabbix-agent
    ```

### Check Zabbix Agent Logs

- **For Zabbix Agent 2:**
    ```
    sudo tail -f /var/log/zabbix/zabbix_agent2.log
    ```

- **For Zabbix Agent 1:**
    ```
    sudo tail -f /var/log/zabbix/zabbix_agentd.log
    ```

## License

This project is licensed under the MIT License.
