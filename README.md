# Service Setup Script

## Overview
This Bash script automates the process of setting up Nginx configurations and obtaining SSL certificates via Certbot for different types of services:
- **Docker-based services** (proxied via Nginx)
- **Node.js applications** (running on a specific port)
- **Static file hosting** (served directly by Nginx)

## Features
✅ Validates necessary dependencies (Nginx, Certbot, sudo).  
✅ Ensures domain validity before proceeding.  
✅ Supports static file hosting, Docker-based services, and Node.js applications.  
✅ Automatically configures Nginx with proper settings.  
✅ Requests and installs SSL certificates using Let's Encrypt.  
✅ Provides detailed user prompts for a seamless setup experience.  

## Prerequisites
Before running this script, ensure that:
- You have **Nginx** and **Certbot** installed on your system.
- You have **sudo** privileges.
- You have a domain name pointing to your server.
- Your service (Docker/Node.js/Static) is ready to be configured.

## Usage
### 1️⃣ Run the Script
```sh
bash setup_service.sh
```

### 2️⃣ Follow the Prompts
The script will guide you through the setup process, asking for the following:
1. **Domain name** (e.g., `example.com`).
2. **Service type**:
   - `Docker` (Reverse proxy to a containerized service)
   - `Node.js` (Proxy to a Node.js application running on a port)
   - `Static` (Serve HTML/CSS/JS from a directory)
3. **Port number** (for Docker/Node.js services).
4. **Root directory** (for static services or ACME challenge validation).

### 3️⃣ Nginx Configuration & SSL Setup
- The script generates an Nginx configuration file in `/etc/nginx/sites-available/`.
- If an existing configuration is found, you will be asked whether to overwrite it.
- Nginx is tested and reloaded to apply changes.
- Certbot is used to obtain an SSL certificate.
- The site is set up with **automatic HTTPS redirection**.

### 4️⃣ Confirmation
Once the setup completes successfully, you should see:
```
✅ Setup completed for example.com
```
Your site should now be accessible over **HTTPS**!

## Troubleshooting
- If the script exits with an error, check the error message and take necessary actions.
- Ensure that your firewall allows HTTP/HTTPS traffic (`sudo ufw allow 'Nginx Full'`).
- If Nginx fails to restart, verify the configuration with:
  ```sh
  sudo nginx -t
  ```
- If Certbot fails to issue a certificate, ensure your domain points to the server.

## License
This script is open-source and provided "as-is" without warranty. Use at your own risk.

Happy hosting! 🚀

