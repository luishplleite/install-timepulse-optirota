#!/bin/bash

# ==========================================================================
# TimePulse AI + OptiRota - Instalador Combinado (Debian/Ubuntu)
# Versao: 3.5 (FIX: Auto .env Generation + Swap + Memory Fix)
# ==========================================================================

set -e
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configurações
TIMEPULSE_DIR="/opt/timepulse"
OPTIROTA_DIR="/opt/optirota"
TIMEPULSE_DOMAIN="timepulseai.com.br"
OPTIROTA_DOMAIN="optirota.timepulseai.com.br"

# ==========================================================================
# PASSO 1: Configurar SWAP e Dependências
# ==========================================================================
echo -e "${BLUE}[1/12] Preparando o Sistema (Swap + Deps)...${NC}"
if [ $(free | grep -i swap | awk '{print $2}') -lt 1000000 ]; then
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

apt-get update -qq
apt-get install -y curl wget git nginx psmisc openssl ca-certificates gnupg lsb-release lsof

if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker && systemctl start docker
fi
apt-get install -y docker-compose-plugin

# ==========================================================================
# PASSO 2: Instalar Cloudflared
# ==========================================================================
ARCH=$(uname -m)
CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
if [[ "$ARCH" != "x86_64" ]]; then CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"; fi
wget -q -O /tmp/cloudflared.deb "$CF_URL"
dpkg -i /tmp/cloudflared.deb || apt-get install -f -y

# ==========================================================================
# PASSO 3: Limpeza e Download
# ==========================================================================
echo -e "${BLUE}[3/12] Baixando Códigos e Limpando ambiente...${NC}"
docker stop timepulse-app optirota-app 2>/dev/null || true
docker rm timepulse-app optirota-app 2>/dev/null || true
rm -rf $TIMEPULSE_DIR $OPTIROTA_DIR

mkdir -p $TIMEPULSE_DIR $OPTIROTA_DIR
git clone --depth 1 "https://github.com/luishplleite/aisisten.git" "$TIMEPULSE_DIR"
git clone --depth 1 "https://github.com/luishplleite/rota-certa.git" "$OPTIROTA_DIR"

# ==========================================================================
# PASSO 4: Coleta de Dados para .env (TimePulse AI)
# ==========================================================================
echo -e "\n${MAGENTA}=== CONFIGURAÇÃO TIMEPULSE AI ($TIMEPULSE_DOMAIN) ===${NC}"
read -p "SUPABASE_URL: " tp_sub_url
read -p "SUPABASE_ANON_KEY: " tp_sub_anon
read -p "SUPABASE_SERVICE_ROLE_KEY: " tp_sub_serv
read -p "OPENAI_API_KEY: " tp_openai
read -p "MAPBOX_TOKEN: " tp_mapbox
read -p "EVOLUTION_API_BASE_URL: " tp_evo_url
read -p "EVOLUTION_API_KEY: " tp_evo_key

cat << EOF > $TIMEPULSE_DIR/.env
NODE_ENV=production
PORT=5000
DOMAIN=$TIMEPULSE_DOMAIN
SUPABASE_URL=$tp_sub_url
SUPABASE_ANON_KEY=$tp_sub_anon
SUPABASE_SERVICE_ROLE_KEY=$tp_sub_serv
OPENAI_API_KEY=$tp_openai
MAPBOX_TOKEN=$tp_mapbox
EVOLUTION_API_BASE_URL=$tp_evo_url
EVOLUTION_API_KEY=$tp_evo_key
EOF

# ==========================================================================
# PASSO 5: Coleta de Dados para .env (OptiRota)
# ==========================================================================
echo -e "\n${MAGENTA}=== CONFIGURAÇÃO OPTIROTA ($OPTIROTA_DOMAIN) ===${NC}"
read -p "SUPABASE_URL: " or_sub_url
read -p "SUPABASE_SERVICE_ROLE_KEY: " or_sub_serv
read -p "STRIPE_PUBLISHABLE_KEY: " or_stri_pub
read -p "STRIPE_SECRET_KEY: " or_stri_sec
read -p "STRIPE_WEBHOOK_SECRET: " or_stri_wh
read -p "GOOGLE_MAPS_API_KEY: " or_gmaps

OR_SESSION=$(openssl rand -base64 32)

cat << EOF > $OPTIROTA_DIR/.env
NODE_ENV=production
PORT=5000
DOMAIN=$OPTIROTA_DOMAIN
SESSION_SECRET=$OR_SESSION
SUPABASE_URL=$or_sub_url
SUPABASE_SERVICE_ROLE_KEY=$or_sub_serv
STRIPE_PUBLISHABLE_KEY=$or_stri_pub
STRIPE_SECRET_KEY=$or_stri_sec
STRIPE_WEBHOOK_SECRET=$or_stri_wh
GOOGLE_MAPS_API_KEY=$or_gmaps
VITE_GOOGLE_MAPS_API_KEY=$or_gmaps
EOF

# ==========================================================================
# PASSO 6: Dockerfiles e Compose
# ==========================================================================
# TimePulse Dockerfile
cat << 'EOF' > $TIMEPULSE_DIR/Dockerfile
FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache python3 make g++ pkgconfig pixman-dev cairo-dev pango-dev jpeg-dev giflib-dev librsvg-dev
COPY package*.json ./
ENV NODE_OPTIONS="--max-old-space-size=1536"
RUN npm install --omit=dev
COPY . .
EXPOSE 5000
CMD ["npm", "start"]
EOF

# OptiRota Dockerfile
cat << 'EOF' > $OPTIROTA_DIR/Dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
RUN apk add --no-cache python3 make g++ pkgconfig pixman-dev cairo-dev pango-dev jpeg-dev giflib-dev librsvg-dev
COPY package*.json ./
ENV NODE_OPTIONS="--max-old-space-size=1536"
RUN npm install
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache pixman cairo pango jpeg giflib librsvg
COPY package*.json ./
RUN npm install --omit=dev
COPY --from=builder /app/dist ./dist
EXPOSE 5000
CMD ["node", "dist/index.cjs"]
EOF

# Compose files
cat << EOF > $TIMEPULSE_DIR/docker-compose.yml
services:
  timepulse:
    build: .
    container_name: timepulse-app
    restart: unless-stopped
    ports: ["127.0.0.1:5000:5000"]
    env_file: .env
EOF

cat << EOF > $OPTIROTA_DIR/docker-compose.yml
services:
  optirota:
    build: .
    container_name: optirota-app
    restart: unless-stopped
    ports: ["127.0.0.1:5001:5000"]
    env_file: .env
EOF

# ==========================================================================
# PASSO 7: Build e Start
# ==========================================================================
echo -e "${YELLOW}Iniciando Builds...${NC}"
cd $TIMEPULSE_DIR && docker compose build --no-cache && docker compose up -d
cd $OPTIROTA_DIR && docker compose build --no-cache && docker compose up -d

# ==========================================================================
# PASSO 8: Nginx e Tunnel
# ==========================================================================
cat << EOF > /etc/nginx/sites-available/combined
server {
    listen 80;
    server_name $TIMEPULSE_DOMAIN;
    location / { proxy_pass http://127.0.0.1:5000; proxy_set_header Host \$host; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; }
}
server {
    listen 80;
    server_name $OPTIROTA_DOMAIN;
    location / { proxy_pass http://127.0.0.1:5001; proxy_set_header Host \$host; proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade"; }
}
EOF
ln -sf /etc/nginx/sites-available/combined /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default || true
systemctl restart nginx

echo -e "${YELLOW}Autentique o Cloudflare Tunnel:${NC}"
cloudflared tunnel login

TUNNEL_NAME="timepulse-combined-final"
cloudflared tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true
TUNNEL_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)

mkdir -p /etc/cloudflared
cat << EOF > /etc/cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json
ingress:
  - hostname: $TIMEPULSE_DOMAIN
    service: http://localhost:80
  - hostname: $OPTIROTA_DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

cloudflared tunnel route dns "$TUNNEL_NAME" "$TIMEPULSE_DOMAIN" || true
cloudflared tunnel route dns "$TUNNEL_NAME" "$OPTIROTA_DOMAIN" || true
cloudflared service install || true
systemctl restart cloudflared

echo -e "${GREEN}🚀 TUDO PRONTO! Acesse seus domínios.${NC}"
