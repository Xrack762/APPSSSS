#!/bin/bash

# ================================================================================
# === ENYX DEV | Smart, Secure & Fully Automated Installer for VPNMarket Project ===
# === Project: VPNMarket (Laravel + NodeJS + MySQL + Redis + Nginx)              ===
# === Author: Arvin Vahed (modified by ENYX DEV)                                 ===
# === Repo: https://github.com/arvinvahed/VPNMarket                              ===
# === Compatible with: Ubuntu 22.04 (64-bit)                                     ===
# ================================================================================

set -e  # Stop the script if any command fails

# --- COLORS ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'
PHP_VERSION="8.3"
PROJECT_PATH="/var/www/vpnmarket"
GITHUB_REPO="https://github.com/arvinvahed/VPNMarket.git"

echo -e "${CYAN}--- Welcome to the VPNMarket Smart Installer by ENYX DEV ---${NC}"
echo

# --- USER INPUT ---
read -p "🌐 Enter your domain (example: market.example.com): " DOMAIN
DOMAIN=$(echo "$DOMAIN" | sed 's|http[s]*://||g' | sed 's|/.*||g')

read -p "🗃 Enter your database name (example: vpnmarket): " DB_NAME
read -p "👤 Enter your database username (example: vpnuser): " DB_USER
while true; do
    read -s -p "🔑 Enter a strong database password: " DB_PASS
    echo
    if [ -z "$DB_PASS" ]; then
        echo -e "${RED}Password cannot be empty. Please try again.${NC}"
    else
        break
    fi
done

read -p "✉️ Enter your admin email for SSL and notifications: " ADMIN_EMAIL
echo

# --- STEP 1: UPDATE SYSTEM ---
echo -e "${YELLOW}📦 Step 1/10: Updating system and installing dependencies...${NC}"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get install -y git curl composer unzip software-properties-common gpg nginx certbot python3-certbot-nginx mysql-server redis-server supervisor ufw

# --- STEP 2: INSTALL LATEST NODE.JS (LTS) ---
echo -e "${YELLOW}📦 Step 2/10: Installing latest Node.js (LTS)...${NC}"
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs
echo -e "${GREEN}✅ Node.js $(node -v) and npm $(npm -v) installed successfully.${NC}"

# --- STEP 3: INSTALL PHP ---
echo -e "${YELLOW}☕ Step 3/10: Installing PHP ${PHP_VERSION} and extensions...${NC}"
sudo add-apt-repository -y ppa:ondrej/php
sudo apt-get update -y
sudo apt-get install -y php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-curl php${PHP_VERSION}-zip php${PHP_VERSION}-bcmath php${PHP_VERSION}-intl php${PHP_VERSION}-gd php${PHP_VERSION}-dom php${PHP_VERSION}-redis
sudo update-alternatives --set php /usr/bin/php${PHP_VERSION}

# --- STEP 4: ENABLE SERVICES ---
echo -e "${YELLOW}🚀 Step 4/10: Enabling required services...${NC}"
sudo systemctl enable --now php${PHP_VERSION}-fpm nginx mysql redis-server supervisor

# --- STEP 5: FIREWALL CONFIGURATION ---
echo -e "${YELLOW}🛡️ Step 5/10: Configuring firewall...${NC}"
sudo ufw allow 'OpenSSH'
sudo ufw allow 'Nginx Full'
echo "y" | sudo ufw enable
sudo ufw status
echo -e "${GREEN}✅ Firewall configured successfully.${NC}"

# --- STEP 6: CLONE PROJECT ---
echo -e "${YELLOW}⬇️ Step 6/10: Cloning VPNMarket project...${NC}"
if [ -d "$PROJECT_PATH" ]; then
    sudo rm -rf "$PROJECT_PATH"
fi
sudo git clone $GITHUB_REPO $PROJECT_PATH
cd $PROJECT_PATH
sudo chown -R www-data:www-data $PROJECT_PATH

# --- STEP 7: DATABASE SETUP ---
echo -e "${YELLOW}🧩 Step 7/10: Creating database and user...${NC}"
sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
sudo mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# --- STEP 8: CONFIGURE .ENV FILE ---
echo -e "${YELLOW}⚙️ Step 8/10: Setting up environment configuration...${NC}"
sudo -u www-data cp .env.example .env
sudo sed -i "s|DB_DATABASE=.*|DB_DATABASE=$DB_NAME|" .env
sudo sed -i "s|DB_USERNAME=.*|DB_USERNAME=$DB_USER|" .env
sudo sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=$DB_PASS|" .env
sudo sed -i "s|APP_URL=.*|APP_URL=https://$DOMAIN|" .env
sudo sed -i "s|APP_ENV=.*|APP_ENV=production|" .env
sudo sed -i "s|QUEUE_CONNECTION=.*|QUEUE_CONNECTION=redis|" .env

# --- STEP 9: INSTALL DEPENDENCIES ---
echo -e "${YELLOW}🧰 Step 9/10: Installing project dependencies...${NC}"
sudo -u www-data composer install --no-dev --optimize-autoloader
sudo -u www-data npm install --cache $PROJECT_PATH/.npm --prefer-offline
sudo -u www-data npm run build
sudo rm -rf $PROJECT_PATH/.npm

echo -e "${CYAN}Running Laravel setup...${NC}"
sudo -u www-data php artisan key:generate
sudo -u www-data php artisan migrate --seed --force
sudo -u www-data php artisan storage:link

# --- STEP 10: NGINX + SUPERVISOR CONFIG ---
echo -e "${YELLOW}🌍 Step 10/10: Configuring Nginx and Supervisor...${NC}"
PHP_FPM_SOCK_PATH=$(grep -oP 'listen\s*=\s*\K.*' /etc/php/${PHP_VERSION}/fpm/pool.d/www.conf | head -n 1 | sed 's/;//g' | xargs)

sudo tee /etc/nginx/sites-available/vpnmarket >/dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root $PROJECT_PATH/public;
    index index.php;
    charset utf-8;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:$PHP_FPM_SOCK_PATH;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/vpnmarket /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx

# --- SUPERVISOR WORKER ---
sudo tee /etc/supervisor/conf.d/vpnmarket-worker.conf >/dev/null <<EOF
[program:vpnmarket-worker]
process_name=%(program_name)s_%(process_num)02d
command=php $PROJECT_PATH/artisan queue:work redis --sleep=3 --tries=3
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=www-data
numprocs=2
redirect_stderr=true
stdout_logfile=/var/log/supervisor/vpnmarket-worker.log
stopwaitsecs=3600
EOF

sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start vpnmarket-worker:*

# --- OPTIMIZE APP ---
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache

# --- SSL INSTALLATION ---
echo
read -p "🔒 Enable free HTTPS with Certbot (recommended)? (y/n): " ENABLE_SSL
if [[ "$ENABLE_SSL" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Installing SSL certificate for $DOMAIN ...${NC}"
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL
fi

# --- SUCCESS MESSAGE ---
echo
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}✅ VPNMarket installation completed successfully!${NC}"
echo -e "--------------------------------------------------"
echo -e "🌐 Website: ${CYAN}https://$DOMAIN${NC}"
echo -e "🔑 Admin Panel: ${CYAN}https://$DOMAIN/admin${NC}"
echo
echo -e "   - Default Admin Email: ${YELLOW}admin@example.com${NC}"
echo -e "   - Default Password: ${YELLOW}password${NC}"
echo
echo -e "${RED}⚠️ Please change the admin password immediately after login!${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo -e "${CYAN}🧠 Script by ENYX DEV | https://github.com/enyxdev${NC}"
