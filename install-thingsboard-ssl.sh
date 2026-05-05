#!/bin/bash
# =============================================================================
# ThingsBoard CE Auto-Installer with Let's Encrypt SSL
# Target: Ubuntu 24.04 LTS on Azure VM
# Database: PostgreSQL
# =============================================================================
set -euo pipefail

# ----------------------------- CONFIGURATION ---------------------------------
# Defaults (can be overridden via command-line arguments)
DOMAIN=""
EMAIL=""
DB_PASSWORD=""
TB_VERSION=""

# Parse command-line arguments (override defaults if provided)
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)      DOMAIN="$2"; shift 2 ;;
        --email)       EMAIL="$2"; shift 2 ;;
        --db-password) DB_PASSWORD="$2"; shift 2 ;;
        --tb-version)  TB_VERSION="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: sudo $0 [OPTIONS]"
            echo ""
            echo "Options (all optional, defaults are pre-configured):"
            echo "  --domain       Domain name (default: $DOMAIN)"
            echo "  --email        Email for SSL cert (default: $EMAIL)"
            echo "  --db-password  PostgreSQL password (default: uses pre-configured value)"
            echo "  --tb-version   ThingsBoard version (default: latest)"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ----------------------------- VALIDATION ------------------------------------
if [[ -z "$DOMAIN" || -z "$EMAIL" || -z "$DB_PASSWORD" ]]; then
    echo "ERROR: DOMAIN, EMAIL, and DB_PASSWORD are required."
    echo "Either edit the script or pass them as arguments: sudo $0 --domain <DOMAIN> --email <EMAIL> --db-password <PASSWORD>"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
fi

LOG_FILE="/var/log/thingsboard-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "============================================="
echo " ThingsBoard CE Full Installer with SSL"
echo " Domain : $DOMAIN"
echo " Email  : $EMAIL"
echo " Started: $(date)"
echo "============================================="

# ----------------------------- STEP 1: System Update -------------------------
echo "[1/8] Updating system packages..."
apt-get update -y
apt-get upgrade -y
apt-get install -y curl wget gnupg2 software-properties-common apt-transport-https ca-certificates
apt-get install -y libharfbuzz0b fontconfig fonts-dejavu-core

# ----------------------------- STEP 2: Install Java --------------------------
echo "[2/8] Installing Java 17..."
apt-get install -y openjdk-17-jdk-headless

java -version
echo "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" >> /etc/environment
source /etc/environment

# ----------------------------- STEP 3: Install PostgreSQL --------------------
echo "[3/8] Installing PostgreSQL..."
apt-get install -y postgresql postgresql-contrib

systemctl start postgresql
systemctl enable postgresql

sudo -u postgres psql -c "CREATE DATABASE thingsboard;"
sudo -u postgres psql -c "CREATE USER thingsboard WITH PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE thingsboard TO thingsboard;"
sudo -u postgres psql -c "ALTER DATABASE thingsboard OWNER TO thingsboard;"

echo "PostgreSQL configured successfully."

# ----------------------------- STEP 4: Install ThingsBoard -------------------
echo "[4/8] Installing ThingsBoard CE..."

# Detect latest version or use specified version
if [[ -n "$TB_VERSION" ]]; then
    TB_FULL_VERSION="$TB_VERSION"
else
    TB_FULL_VERSION=$(curl -s https://api.github.com/repos/thingsboard/thingsboard/releases/latest | \
        grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [[ -z "$TB_FULL_VERSION" ]]; then
        echo "WARNING: Could not detect latest version. Falling back to 4.3.1.1"
        TB_FULL_VERSION="4.3.1.1"
    fi
fi

echo "Downloading ThingsBoard CE v${TB_FULL_VERSION}..."
wget -O /tmp/thingsboard-${TB_FULL_VERSION}.deb \
    "https://github.com/thingsboard/thingsboard/releases/download/v${TB_FULL_VERSION}/thingsboard-${TB_FULL_VERSION}.deb"
dpkg -i /tmp/thingsboard-${TB_FULL_VERSION}.deb

# Configure ThingsBoard to use PostgreSQL
TB_CONF="/etc/thingsboard/conf/thingsboard.conf"
cat >> "$TB_CONF" <<EOF

# PostgreSQL Configuration
export DATABASE_TS_TYPE=sql
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/thingsboard
export SPRING_DATASOURCE_USERNAME=thingsboard
export SPRING_DATASOURCE_PASSWORD=$DB_PASSWORD
export SQL_POSTGRES_TS_KV_PARTITIONING=MONTHS
EOF

echo "ThingsBoard installed. Running database setup..."

# Run install from home directory to avoid path issues
cd /home
/usr/share/thingsboard/bin/install/install.sh --loadDemo

echo "ThingsBoard database initialized."

# ----------------------------- STEP 5: Start ThingsBoard ---------------------
echo "[5/8] Starting ThingsBoard service..."
systemctl start thingsboard
systemctl enable thingsboard

echo "Waiting for ThingsBoard to start (this may take up to 90 seconds)..."
RETRIES=0
MAX_RETRIES=36
while ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/login 2>/dev/null | grep -q "200"; do
    RETRIES=$((RETRIES + 1))
    if [[ $RETRIES -ge $MAX_RETRIES ]]; then
        echo "WARNING: ThingsBoard did not respond within 180 seconds."
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
echo " Version         : $TB_FULL_VERSION"
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
