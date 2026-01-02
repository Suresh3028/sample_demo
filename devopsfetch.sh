#!/bin/bash
#
# devopsfetch - System Information Retrieval and Monitoring Tool

# --- Configuration ---
NGINX_CONF_DIR="/etc/nginx/sites-enabled"
LOG_FILE="/var/log/devopsfetch.log"

# --- Utility Functions ---

# Function to display help menu
show_help() {
    cat << EOF
devopsfetch - DevOps System Information Retrieval Tool

Usage: devopsfetch [OPTION] [ARGUMENT]

Options:
  -p, --port [PORT]     Display all active ports and services.
                        Optionally, provide a PORT number (e.g., 80) for details.
  -d, --docker [CONTAINER] List all Docker images and containers.
                        Optionally, provide a CONTAINER name/ID for details.
  -n, --nginx [DOMAIN]  Display all Nginx domains and their ports.
                        Optionally, provide a DOMAIN name for detailed config.
  -u, --users [USER]    List all users and their last login times.
                        Optionally, provide a USER name for detailed info.
  -t, --time <START> <END> Display activities (via journalctl) within a time range.
                        Format: "YYYY-MM-DD HH:MM:SS" (e.g., -t "2023-01-01 00:00:00" "now")
  -h, --help            Show this help message.
  -m, --monitor         Run in continuous monitoring mode (used by systemd).
EOF
}

# Function to format output into a neat table (using 'column')
format_table() {
    awk 'BEGIN {OFS="\t\t"} {print $0}' | column -t -s $'\t'
}

# --- Core Information Retrieval Functions ---

# 1. Port Information
show_ports() {
    echo "--- Active Ports and Services ---"
    if [ -z "$1" ]; then
        echo -e "PROTOCOL\tPORT\tSERVICE\tPID/Program"
        ss -tulpn | awk 'NR > 1 {
            split($5, local, ":");
            port=local[length(local)];
            app=$NF;
            print $1 "\t" port "\t-\t" app;
        }' | format_table
    else
        echo "--- Details for Port: $1 ---"
        echo -e "PID\tUSER\tCOMMAND\tPROTOCOL\tPORT"
        lsof -i ":$1" -n -P | awk 'NR > 1 && $8 == "LISTEN" {
            split($9, addr, ":");
            print $2 "\t" $3 "\t" $1 "\t" $7 "\t" addr[length(addr)]
        }' | format_table
    fi
}

# 2. Docker Information
show_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker command not found. Please install Docker." >&2
        return 1
    fi

    if [ -z "$1" ]; then
        echo "--- Docker Images ---"
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"

        echo -e "\n--- Docker Containers (Active/Exited) ---"
        docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
    else
        echo "--- Docker Container Details: $1 ---"
        docker inspect --format '{{json .}}' "$1" | jq -r '
            . |
            "Name: " + .Name,
            "State: " + .State.Status,
            "Image: " + .Config.Image,
            "Created: " + .Created,
            "IP Address: " + .NetworkSettings.IPAddress,
            "Mounts: " + ([.Mounts[] | .Source + " -> " + .Destination] | join(", "))
        '
    fi
}

# 3. Nginx Information
show_nginx() {
    if [ ! -d "$NGINX_CONF_DIR" ]; then
        echo "Error: Nginx configuration directory not found at $NGINX_CONF_DIR" >&2
        return 1
    fi

    if [ -z "$1" ]; then
        echo "--- Nginx Domains and Ports ---"
        echo -e "DOMAIN\tPORT\tCONFIG_FILE"
        find "$NGINX_CONF_DIR" -type l -exec readlink -f {} \; | while read -r config_file; do
            # Extract server_name and listen port
            domain=$(grep -E 'server_name ' "$config_file" | awk '{print $2}' | tr -d ';')
            port=$(grep -E 'listen ' "$config_file" | grep -v 'ssl' | awk '{print $2}' | tr -d ';')
            
            if [ -n "$domain" ] && [ -n "$port" ]; then
                echo -e "$domain\t$port\t$(basename "$config_file")"
            fi
        done | format_table
    else
        echo "--- Nginx Configuration Details for $1 ---"
        config_file=$(grep -lR "server_name $1" "$NGINX_CONF_DIR" 2>/dev/null)
        if [ -f "$config_file" ]; then
            echo "Configuration File: $config_file"
            echo "-----------------------------------"
            cat "$config_file"
        else
            echo "Error: No Nginx configuration found for domain $1." >&2
        fi
    fi
}

# 4. User Information
show_users() {
    if [ -z "$1" ]; then
        echo "--- System Users and Last Login ---"
        echo -e "USERNAME\tUID\tLAST_LOGIN\tLOGIN_FROM"
        while IFS=: read -r username _ uid _ _ _ shell; do
            # Only show accounts with a proper shell (i.e., not system users)
            if [ "$uid" -ge 1000 ] && [ -n "$shell" ] && [[ "$shell" != *nologin* ]] && [[ "$shell" != *false* ]]; then
                last_info=$(last -n 1 "$username" | head -n 1)
                login_time=$(echo "$last_info" | awk 'NR==1 {print $4,$5,$6,$7}')
                login_from=$(echo "$last_info" | awk 'NR==1 {print $3}')
                if [ -z "$login_time" ]; then
                    login_time="Never logged in"
                    login_from="-"
                fi
                echo -e "$username\t$uid\t$login_time\t$login_from"
            fi
        done < /etc/passwd | format_table
    else
        echo "--- Detailed Information for User: $1 ---"
        grep "^$1:" /etc/passwd | awk -F: '{
            print "Username:\t" $1;
            print "UID:\t\t" $3;
            print "GID:\t\t" $4;
            print "Home Dir:\t" $6;
            print "Shell:\t\t" $7;
        }'
        echo -e "\n--- Recent Login History for $1 ---"
        last "$1" | head -n 5
    fi
}

# 5. Time Range Activity (using journalctl)
show_time_range() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Error: Both start and end time are required. Use -t \"YYYY-MM-DD HH:MM:SS\" \"YYYY-MM-DD HH:MM:SS\"" >&2
        return 1
    fi
    echo "--- System Activities from $1 to $2 ---"
    journalctl --since "$1" --until "$2" -p info --no-pager | head -n 50
    echo -e "\n(Showing first 50 INFO/WARNING/ERROR entries)"
}

# 6. Continuous Monitoring Mode (for systemd)
continuous_monitor() {
    echo "=========================================================="
    echo "devopsfetch Monitor Run: $(date)"
    echo "=========================================================="
    show_ports
    echo -e "\n"
    show_docker
    echo -e "\n"
    show_nginx
    echo -e "\n"
    show_users
}

# --- Main Script Logic ---

if [ "$#" -eq 0 ]; then
    show_help
    exit 0
fi

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -m|--monitor)
            continuous_monitor
            shift
            ;;
        -p|--port)
            shift
            show_ports "$1"
            shift 2>/dev/null
            ;;
        -d|--docker)
            shift
            show_docker "$1"
            shift 2>/dev/null
            ;;
        -n|--nginx)
            shift
            show_nginx "$1"
            shift 2>/dev/null
            ;;
        -u|--users)
            shift
            show_users "$1"
            shift 2>/dev/null
            ;;
        -t|--time)
            shift
            show_time_range "$1" "$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done