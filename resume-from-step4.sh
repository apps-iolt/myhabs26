#!/bin/bash
# =============================================================================
# ThingsBoard CE Resume Installer (Steps 4-8)
# Use this if steps 1-3 (system update, Java, PostgreSQL) already completed.
# =============================================================================
set -euo pipefail

# ----------------------------- CONFIGURATION ---------------------------------
DOMAIN="myhabs26.malaysiawest.cloudapp.azure.com"              # e.g. mythingsboard.eastus.cloudapp.azure.com
EMAIL="iolayerz.technology@gmail.com"               # e.g. admin@yourdomain.com
DB_PASSWORD="myhabs@IOT26"         # Same password you used in the first run

# Optional
TB_VERSION=""

# ----------------------------- VALIDATION ------------------------------------
if [[ -z "$DOMAIN" || -z "$EMAIL" || -z "$DB_PASSWORD" ]]; then
    echo "ERROR: Edit this script and fill in DOMAIN, EMAIL, and DB_PASSWORD first."
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
fi

LOG_FILE="/var/log/thingsboard-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================="
echo " ThingsBoard CE Resume Installer (Steps 4-8)"
echo " Domain : $DOMAIN"
echo " Started: $(date)"
echo "============================================="

# ----------------------------- STEP 4: Install ThingsBoard -------------------
echo "[4/8] Installing ThingsBoard CE..."

# Download latest ThingsBoard .deb directly from GitHub (official method)
if [[ -n "$TB_VERSION" ]]; then
    TB_FULL_VERSION="$TB_VERSION"
else
    TB_FULL_VERSION=$(curl -s https://api.github.com/repos/thingsboard/thingsboard/releases/latest | \
        grep '"tag_name"' | sed -E 's/.*"v(.*)"/\1/')
    if [[ -z "$TB_FULL_VERSION" ]]; then
        echo "WARNING: Could not detect latest version. Falling back to 4.3.1.1"
        TB_FULL_VERSION="4.3.1.1"
    fi
fi

echo "Installing ThingsBoard CE v${TB_FULL_VERSION}..."
wget -O /tmp/thingsboard-${TB_FULL_VERSION}.deb \
    "https://github.com/thingsboard/thingsboard/releases/download/v${TB_FULL_VERSION}/thingsboard-${TB_FULL_VERSION}.deb"
sudo dpkg -i /tmp/thingsboard-${TB_FULL_VERSION}.deb

# Configure ThingsBoard to use PostgreSQL
TB_CONF="/etc/thingsboard/conf/thingsboard.conf"
cat >> "$TB_CONF" <<EOF

# PostgreSQL Configuration
export DATABASE_TS_TYPE=sql
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/thingsboard
export SPRING_DATASOURCE_USERNAME=thingsboard
export SPRING_DATASOURCE_PASSWORD=$DB_PASSWORD
EOF

echo "ThingsBoard installed. Running database setup..."
/usr/share/thingsboard/bin/install/install.sh --loadDemo
echo "ThingsBoard database initialized."

# ----------------------------- STEP 5: Start ThingsBoard ---------------------
echo "[5/8] Starting ThingsBoard service..."
systemctl start thingsboard
systemctl enable thingsboard

echo "Waiting for ThingsBoard to start (this may take a minute)..."
RETRIES=0
MAX_RETRIES=24
while ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login 2>/dev/null | grep -q "200"; do
    RETRIES=$((RETRIES + 1))
    if [[ $RETRIES -ge $MAX_RETRIES ]]; then
        echo "WARNING: ThingsBoard did not respond within 120 seconds."
        echo "Check logs: journalctl -u thingsboard -f"
        break
    fi
    sleep 5
done

if [[ $RETRIES -lt $MAX_RETRIES ]]; then
    echo "ThingsBoard is running on port 8080."
fi

# ----------------------------- STEP 6: Install Nginx -------------------------
echo "[6/8] Installing and configuring Nginx..."
apt-get install -y nginx

cat > /etc/nginx/sites-available/thingsboard <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support (required for ThingsBoard)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 600s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/thingsboard /etc/nginx/sites-enabled/thingsboard
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl restart nginx
systemctl enable nginx

echo "Nginx configured (HTTP)."

# ----------------------------- STEP 7: Let's Encrypt SSL ---------------------
echo "[7/8] Obtaining Let's Encrypt SSL certificate..."
apt-get install -y certbot python3-certbot-nginx

certbot --nginx \
    -d "$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --redirect

echo "SSL certificate obtained and Nginx configured for HTTPS."

# ----------------------------- STEP 8: Auto-Renewal --------------------------
echo "[8/8] Setting up SSL certificate auto-renewal..."
systemctl enable certbot.timer
systemctl start certbot.timer
certbot renew --dry-run

echo "Auto-renewal configured via systemd timer."

# ----------------------------- FIREWALL (UFW) --------------------------------
echo "Configuring firewall..."
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 22/tcp
ufw --force enable

# ----------------------------- SUMMARY ---------------------------------------
PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || echo "unknown")

echo ""
echo "============================================="
echo " INSTALLATION COMPLETE"
echo "============================================="
echo ""
echo " ThingsBoard URL : https://$DOMAIN"
echo " Server Public IP: $PUBLIC_IP"
echo ""
echo " Default Login Credentials:"
echo "   System Admin : sysadmin@thingsboard.org / sysadmin"
echo "   Tenant Admin : tenant@thingsboard.org / tenant"
echo ""
echo " SSL Certificate : Let's Encrypt (auto-renews)"
echo " Logs            : $LOG_FILE"
echo " TB Service Logs : journalctl -u thingsboard -f"
echo ""
echo " IMPORTANT: Change default passwords immediately!"
echo "============================================="
