#!/bin/bash
set -euo pipefail

# init-ssl.sh — Bootstrap SSL certificates for first-time nginx setup
# Run this ONCE on the VPS after configuring DNS and cloudflare.ini
#
# Prerequisites:
#   1. docker network create bot-proxy-net
#   2. DNS: *.dashboard.example.com → VPS IP
#   3. nginx/ssl/cloudflare.ini with Cloudflare API token

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NGINX_DIR="$(dirname "$SCRIPT_DIR")"

# Read domain from nginx/.env
NGINX_ENV="$NGINX_DIR/.env"
if [ -f "$NGINX_ENV" ]; then
    DOMAIN=$(grep '^DOMAIN=' "$NGINX_ENV" | cut -d'=' -f2-)
    CERTBOT_EMAIL=$(grep '^CERTBOT_EMAIL=' "$NGINX_ENV" | cut -d'=' -f2-)
fi
DOMAIN="${DOMAIN:-dashboard.example.com}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-admin@${DOMAIN}}"

echo "🔐 Bootstrapping SSL certificates for *.${DOMAIN}..."
echo ""

# --- Validate prerequisites ---
if ! docker network inspect bot-proxy-net &>/dev/null; then
    echo "❌ Docker network 'bot-proxy-net' not found."
    echo "   Run: docker network create bot-proxy-net"
    exit 1
fi

if [ ! -f "$NGINX_DIR/ssl/cloudflare.ini" ]; then
    echo "❌ Missing ssl/cloudflare.ini"
    echo "   Create it with your Cloudflare API token:"
    echo ""
    echo "   dns_cloudflare_api_token = your-token-here"
    echo ""
    echo "   Then: chmod 600 ssl/cloudflare.ini"
    exit 1
fi

# --- Create directory structure ---
mkdir -p "$NGINX_DIR/ssl/certbot/conf"
mkdir -p "$NGINX_DIR/ssl/certbot/www"
mkdir -p "$NGINX_DIR/conf.d"

# --- Create temporary self-signed cert so nginx can start ---
CERT_DIR="$NGINX_DIR/ssl/certbot/conf/live/${DOMAIN}"
if [ ! -f "$CERT_DIR/fullchain.pem" ]; then
    echo "📝 Creating temporary self-signed certificate..."
    mkdir -p "$CERT_DIR"
    openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
        -keyout "$CERT_DIR/privkey.pem" \
        -out "$CERT_DIR/fullchain.pem" \
        -subj "/CN=${DOMAIN}" 2>/dev/null
    echo "✅ Temporary certificate created"
else
    echo "ℹ️  Certificate already exists, skipping self-signed generation"
fi

# --- Start nginx with temporary cert ---
echo ""
echo "🚀 Starting nginx with temporary certificate..."
docker compose -f "$NGINX_DIR/docker-compose.yml" up -d nginx

# Wait for nginx to be ready
sleep 3
if ! docker ps --format '{{.Names}}' | grep -q '^bot-nginx$'; then
    echo "❌ Nginx failed to start. Check logs:"
    echo "   docker logs bot-nginx"
    exit 1
fi
echo "✅ Nginx is running"

# --- Obtain real wildcard certificate ---
echo ""
echo "🔐 Requesting Let's Encrypt wildcard certificate..."
echo "   This may take 30-60 seconds for DNS propagation..."
echo ""

docker compose -f "$NGINX_DIR/docker-compose.yml" run --rm certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /etc/cloudflare/cloudflare.ini \
    --dns-cloudflare-propagation-seconds 30 \
    -d "${DOMAIN}" \
    -d "*.${DOMAIN}" \
    --email "${CERTBOT_EMAIL}" \
    --agree-tos \
    --no-eff-email

# --- Reload nginx with real cert ---
echo ""
echo "🔄 Reloading nginx with real certificate..."
docker exec bot-nginx nginx -s reload

echo ""
echo "✅ SSL setup complete!"
echo "   Domain:       *.${DOMAIN}"
echo "   Certificate:  Let's Encrypt wildcard"
echo "   Auto-renewal: enabled (certbot checks every 12h)"
echo ""
echo "📋 Next steps:"
echo "   1. Deploy bots with: cd ../openclaw_docker && ./deploy-bot.sh <name> <token> <chat_ids>"
echo "   2. Access dashboard at: https://<botname>.${DOMAIN}"
