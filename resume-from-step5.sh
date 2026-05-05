#!/bin/bash
# =============================================================================
# ThingsBoard CE Resume Installer (Steps 5-8)
# Use this AFTER ThingsBoard is already installed and DB is initialized.
# =============================================================================
set -euo pipefail

# ----------------------------- CONFIGURATION ---------------------------------
DOMAIN="myhabs26.malaysiawest.cloudapp.azure.com"
EMAIL="iolayerz.technology@gmail.com"

# ----------------------------- VALIDATION ------------------------------------
if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
    echo "ERROR: Edit this script and fill in DOMAIN and EMAIL first."
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
fi

LOG_FILE="/var/log/thingsboard-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================="
echo " ThingsBoard CE Resume Installer (Steps 5-8)"
echo " Domain : $DOMAIN"
echo " Started: $(date)"
echo "============================================="

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
