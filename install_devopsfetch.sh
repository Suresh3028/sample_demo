#!/bin/bash
#
# install_devopsfetch.sh - Installation script for devopsfetch

set -e # Exit immediately if a command exits with a non-zero status.

DEVOPSE_SCRIPT_PATH="/usr/local/bin/devopsfetch"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/devopsfetch.service"
LOG_FILE="/var/log/devopsfetch.log"
LOGROTATE_CONF_FILE="/etc/logrotate.d/devopsfetch"
MONITOR_INTERVAL="5min" # How often the monitor runs

echo "--- Starting devopsfetch Installation ---"

# 1. Check for necessary dependencies
echo "1. Checking dependencies (jq, column, last)..."
if ! command -v jq &> /dev/null || ! command -v column &> /dev/null || ! command -v last &> /dev/null; then
    echo "Warning: Required dependencies (jq, column, last) not found. Attempting to install..."
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y jq bsdmainutils util-linux
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq util-linux
    else
        echo "Error: Cannot automatically install dependencies. Please install jq and column manually."
        exit 1
    fi
fi
echo "Dependencies checked/installed."

# 2. Install the main script
echo "2. Installing devopsfetch script to $DEVOPSE_SCRIPT_PATH..."
# NOTE: In a real scenario, you'd copy the devopsfetch file here, e.g.,
# sudo cp devopsfetch_script_name "$DEVOPSE_SCRIPT_PATH"
# For this example, we assume the script is in the current directory.
# We'll use a placeholder echo for demonstration in the absence of the file.
sudo cp devopsfetch "$DEVOPSE_SCRIPT_PATH"
sudo chmod +x "$DEVOPSE_SCRIPT_PATH"
echo "devopsfetch installed successfully."

# 3. Create the Systemd Service file
echo "3. Creating systemd service file: $SYSTEMD_SERVICE_FILE..."
sudo tee "$SYSTEMD_SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=DevOps System Monitoring Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c "while true; do $DEVOPSE_SCRIPT_PATH -m >> $LOG_FILE; sleep $MONITOR_INTERVAL; done"
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 4. Enable and Start the Systemd Service
echo "4. Enabling and starting devopsfetch monitoring service..."
sudo systemctl daemon-reload
sudo systemctl enable devopsfetch.service
sudo systemctl start devopsfetch.service
echo "devopsfetch monitoring service started. Check status with: sudo systemctl status devopsfetch"

# 5. Configure Log Rotation
echo "5. Configuring log rotation for $LOG_FILE..."
sudo tee "$LOGROTATE_CONF_FILE" > /dev/null << EOF
$LOG_FILE {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF
echo "Log rotation configured. Logs will rotate daily, keeping 7 days."

echo "--- Installation Complete! ---"
echo "You can now run 'devopsfetch -h' for usage."
