#!/bin/bash
set -euo pipefail

#############################
# Utility Functions
#############################

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Exit with an error message
error_exit() {
    echo "❌ $1" >&2
    exit 1
}

# Read non-empty input from the user
read_input() {
    local prompt="$1"
    local input=""
    while true; do
        read -rp "$prompt" input
        if [[ -n "$input" ]]; then
            echo "$input"
            break
        else
            echo "Input cannot be empty. Please try again."
        fi
    done
}

# Validate domain using a regex pattern (basic validation)
validate_domain() {
    local domain=$1
    if [[ "$domain" =~ ^(([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[A-Za-z]{2,})$ ]]; then
        return 0
    else
        return 1
    fi
}

#############################
# Pre-flight Checks
#############################

for cmd in nginx certbot sudo; do
    if ! command_exists "$cmd"; then
        error_exit "$cmd is not installed. Aborting."
    fi
done

#############################
# Service Setup Function
#############################

setup_service() {
    local domain=$1
    local port=${2:-""}
    local directory=${3:-""}
    local service_type=$4

    # For static services the directory is required and must exist.
    # For docker/node services, directory is optional (default provided if empty).
    if [[ "$service_type" == "static" ]]; then
        if [[ -z "$directory" ]]; then
            error_exit "For a static file service, a root directory is required."
        fi
        if [[ ! -d "$directory" ]]; then
            error_exit "Directory '$directory' does not exist."
        fi
    else
        if [[ -z "$directory" ]]; then
            directory="/var/www/acme-challenge"
            echo "No directory provided for ACME challenge; using default: $directory"
        fi
        # Create the directory if it doesn't exist
        if [[ ! -d "$directory" ]]; then
            echo "Directory '$directory' does not exist. Creating it..."
            sudo mkdir -p "$directory" || error_exit "Failed to create directory '$directory'."
        fi
    fi

    local nginx_conf="/etc/nginx/sites-available/${domain}.conf"

    # Check for an existing configuration file
    if [[ -f "$nginx_conf" ]]; then
        read -rp "Configuration file $nginx_conf already exists. Overwrite? (y/n): " response
        if [[ "$response" != "y" && "$response" != "Y" ]]; then
            echo "Aborting setup."
            exit 0
        fi
    fi

    echo "Setting up Nginx configuration for ${domain}..."

    if [[ "$service_type" == "docker" || "$service_type" == "node" ]]; then
        # Validate that the port is provided and numeric
        if [[ -z "$port" ]]; then
            error_exit "Port number is required for Docker or Node.js services."
        fi
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            error_exit "Port must be numeric."
        fi

        sudo tee "$nginx_conf" > /dev/null <<EOF
server {
    listen 80;
    server_name ${domain} www.${domain};

    location / {
        proxy_pass http://localhost:${port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ ^/\.well-known/acme-challenge {
        root ${directory};
        allow all;
    }
}
EOF
    else
        sudo tee "$nginx_conf" > /dev/null <<EOF
server {
    listen 80;
    server_name ${domain} www.${domain};

    root ${directory};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ ^/\.well-known/acme-challenge {
        root ${directory};
        allow all;
    }
}
EOF
    fi

    # Ensure the configuration is enabled
    if [[ ! -L "/etc/nginx/sites-enabled/${domain}.conf" ]]; then
        sudo ln -sf "$nginx_conf" /etc/nginx/sites-enabled/
    fi

    echo "Testing Nginx configuration..."
    if ! sudo nginx -t; then
        error_exit "Nginx configuration test failed."
    fi

    echo "Reloading Nginx..."
    sudo systemctl reload nginx

    # Ask for an email for Let's Encrypt (default: admin@domain)
    local email="admin@${domain}"
    read -rp "Enter email for Let's Encrypt registration [default: $email]: " input_email
    if [[ -n "$input_email" ]]; then
        email="$input_email"
    fi

    echo "Requesting SSL certificate from Certbot for ${domain} and www.${domain}..."
    sudo certbot --nginx -d "${domain}" -d "www.${domain}" --non-interactive --agree-tos --redirect -m "${email}"

    echo "✅ Setup completed for ${domain}"
}

#############################
# Main Script Execution
#############################

main() {
    echo "🔧 Starting service setup..."

    # Get and validate the domain name
    local domain=""
    while true; do
        domain=$(read_input "Enter domain name (e.g., example.com): ")
        # Remove leading "www." if present
        domain=${domain#www.}
        if validate_domain "$domain"; then
            break
        else
            echo "Invalid domain format. Please try again."
        fi
    done

    local service_type=""
    local port=""
    local directory=""

    # Select the service type
    echo "Select the service type:"
    echo "1) Docker"
    echo "2) Node.js"
    echo "3) Static files"
    local service_choice=""
    while true; do
        read -rp "Enter service type (1/2/3): " service_choice
        case $service_choice in
            1) service_type="docker"; break;;
            2) service_type="node"; break;;
            3) service_type="static"; break;;
            *) echo "❌ Invalid option. Please enter 1, 2, or 3.";;
        esac
    done

    # Ask for a port if needed
    if [[ "$service_type" == "docker" || "$service_type" == "node" ]]; then
        while true; do
            port=$(read_input "Enter port number for service (e.g., 3000): ")
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                break
            else
                echo "Port must be numeric. Please try again."
            fi
        done

        # Optional directory for the ACME challenge; default will be used if left blank.
        read -rp "Enter root directory for ACME challenge (press Enter to use default /var/www/acme-challenge): " directory
    else
        # For static services, a directory is mandatory.
        directory=$(read_input "Enter root directory for static files (e.g., /var/www/html): ")
    fi

    echo ""
    echo "Summary of configuration:"
    echo "Domain: $domain"
    echo "Service type: $service_type"
    if [[ "$service_type" == "docker" || "$service_type" == "node" ]]; then
        echo "Port: $port"
    fi
    echo "Directory: $directory"
    echo ""
    read -rp "Proceed with this configuration? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborting setup."
        exit 0
    fi

    setup_service "$domain" "$port" "$directory" "$service_type"
    echo "🎉 All done!"
}

main
