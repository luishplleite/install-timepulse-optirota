#!/bin/bash

# ==========================================================================
# TimePulse AI + OptiRota - INSTALADOR MESTRE (Debian/Ubuntu)
# Versão: 4.0 (Consolidada e Estável)
# ==========================================================================

set -e

# 1. CONFIGURAÇÃO DE AMBIENTE
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Cores para saída
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Variáveis Fixas
TIMEPULSE_DIR="/opt/timepulse"
OPTIROTA_DIR="/opt/optirota"
TIMEPULSE_DOMAIN="timepulseai.com.br"
OPTIROTA_DOMAIN="optirota.timepulseai.com.br"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          SISTEMA DE INSTALAÇÃO AUTOMATIZADA - SANTOS/SP            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════╝${NC}"

# Verificar root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Erro: Por favor, execute como root (sudo).${NC}"
    exit 1
fi

# ==========================================================================
# ETAPA 1: OPTIMIZAÇÃO DE MEMÓRIA (SWAP)
# ==========================================================================
echo -e "\n${YELLOW}[1/10] Verificando Memória Virtual (Swap)...${NC}"
if [ $(free | grep -i swap | awk '{print $2}') -lt 1000000 ]; then
    echo -e "Criando arquivo Swap de 2GB para evitar falhas no build..."
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo -e "${GREEN}Swap activado!${NC}"
else
    echo -e "${GREEN}Swap já configurado.${NC}"
fi

# ==========================================================================
# ETAPA 2: INSTALAÇÃO DE DEPENDÊNCIAS DO SISTEMA
# ==========================================================================
echo -e "\n${YELLOW}[2/10] Instalando dependências globais...${NC}"
apt-get update -qq
apt-get install -y curl wget git nginx psmisc openssl ca-certificates gnupg lsb-release lsof procps

# Docker & Compose
if ! command -v docker &> /dev/null; then
    echo "Instalando Docker Engine..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker && systemctl start docker
fi
apt-get install -y docker-compose-plugin

# Cloudflared
echo "Instalando binário Cloudflared..."
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
else CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"; fi
wget -q -O /tmp/cloudflared.deb "$CF_URL"
dpkg -i /tmp/cloudflared.deb || apt-get install -f -y

# ==========================================================================
# ETAPA 3: LIMPEZA DE AMBIENTE ANTERIOR
# ==========================================================================
echo -e "\n${YELLOW}[3/10] Limpando processos e containers antigos...${NC}"
systemctl stop cloudflared 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true
systemctl disable apache2 2>/dev/null || true
docker stop timepulse-app optirota-app 2>/dev/null || true
docker rm timepulse-app optirota-app 2>/dev/null || true
lsof -t -i:80,5000,5001 | xargs -r kill -9 2>/dev/null || true
rm -rf $TIMEPULSE_DIR $OPTIROTA_DIR

# ==========================================================================
# ETAPA 4: DOWNLOAD DOS REPOSITÓRIOS
# ==========================================================================
echo -e "\n${YELLOW}[4/10] Descarregando códigos-fonte...${NC}"
mkdir -p $TIMEPULSE_DIR $OPTIROTA_DIR
git clone --depth 1 "https://github.com/luishplleite/aisisten.git" "$TIMEPULSE_DIR"
git clone --depth 1 "https://github.com/luishplleite/rota-certa.git" "$OPTIROTA_DIR"

# ==========================================================================
# ETAPA 5: CONFIGURAÇÃO TIMEPULSE AI (.env)
# ==========================================================================
echo -e "\n${MAGENTA}>>> CONFIGURAÇÃO TIMEPULSE AI ($TIMEPULSE_DOMAIN)${NC}"
read -p "SUPABASE_URL: " tp_url
read -p "SUPABASE_ANON_KEY: " tp_anon
read -p "SUPABASE_SERVICE_ROLE_KEY: " tp_serv
read -p "OPENAI_API_KEY: " tp_openai
read -p "MAPBOX_TOKEN: " tp_mapbox
read -p "EVOLUTION_API_BASE_URL: " tp_evo_url
read -p "EVOLUTION_API_KEY: " tp_evo_key

cat << EOF > $TIMEPULSE_DIR/.env
NODE_ENV=production
PORT=5000
DOMAIN=$TIMEPULSE_DOMAIN
SUPABASE_URL=$tp_url
SUPABASE_ANON_KEY=$tp_anon
SUPABASE_SERVICE_ROLE_KEY=$tp_serv
OPENAI_API_KEY=$tp_openai
MAPBOX_TOKEN=$tp_mapbox
EVOLUTION_API_BASE_URL=$tp_evo_url
EVOLUTION_API_KEY=$tp_evo_key
EOF

# ==========================================================================
# ETAPA 6: CONFIGURAÇÃO OPTIROTA (.env)
# ==========================================================================
echo -e "\n${MAGENTA}>>> CONFIGURAÇÃO OPTIROTA ($OPTIROTA_DOMAIN)${NC}"
read -p "SUPABASE_URL: " or_url
read -p "SUPABASE_SERVICE_ROLE_KEY: " or_serv
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
SUPABASE_URL=$or_url
SUPABASE_SERVICE_ROLE_KEY=$or_serv
STRIPE_PUBLISHABLE_KEY=$or_stri_pub
STRIPE_SECRET_KEY=$or_stri_sec
STRIPE_WEBHOOK_SECRET=$or_stri_wh
GOOGLE_MAPS_API_KEY=$or_gmaps
VITE_GOOGLE_MAPS_API_KEY=$or_gmaps
EOF

# ==========================================================================
# ETAPA 7: CRIAÇÃO DOS DOCKERFILES (FIX: Canvas + Memory)
# ==========================================================================
echo -e "\n${YELLOW}[7/10] Gerando configurações Docker optimizadas...${NC}"

# Dockerfile TimePulse
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

# Dockerfile OptiRota
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

# docker-compose TimePulse
cat << EOF > $TIMEPULSE_DIR/docker-compose.yml
services:
  timepulse:
    build: .
    container_name: timepulse-app
    restart: unless-stopped
    ports: ["127.0.0.1:5000:5000"]
    env_file: .env
EOF

# docker-compose OptiRota
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
# ETAPA 8: COMPILAÇÃO E EXECUÇÃO DOCKER
# ==========================================================================
echo -e "\n${YELLOW}[8/10] Iniciando compilação dos containers...${NC}"
cd $TIMEPULSE_DIR && docker compose build --no-cache && docker compose up -d
cd $OPTIROTA_DIR && docker compose build --no-cache && docker compose up -d

# ==========================================================================
# ETAPA 9: CONFIGURAÇÃO DO NGINX (GATEWAY)
# ==========================================================================
echo -e "\n${YELLOW}[9/10] Configurando Proxy Reverso Nginx...${NC}"
cat << EOF > /etc/nginx/sites-available/combined
server {
    listen 80;
    server_name $TIMEPULSE_DOMAIN www.$TIMEPULSE_DOMAIN;
    location / { 
        proxy_pass http://127.0.0.1:5000; 
        proxy_set_header Host \$host; 
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade; 
        proxy_set_header Connection "upgrade"; 
    }
}
server {
    listen 80;
    server_name $OPTIROTA_DOMAIN;
    location / { 
        proxy_pass http://127.0.0.1:5001; 
        proxy_set_header Host \$host; 
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade; 
        proxy_set_header Connection "upgrade"; 
    }
}
EOF
ln -sf /etc/nginx/sites-available/combined /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default || true
nginx -t && systemctl restart nginx

# ==========================================================================
# ETAPA 10: CONFIGURAÇÃO DO CLOUDFLARE TUNNEL
# ==========================================================================
echo -e "\n${YELLOW}[10/10] Configurando Túnel Externo Cloudflare...${NC}"
cloudflared tunnel login

TUNNEL_NAME="timepulse-unified-vps"
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
  - hostname: www.$TIMEPULSE_DOMAIN
    service: http://localhost:80
  - hostname: $OPTIROTA_DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

# Rotas DNS
cloudflared tunnel route dns "$TUNNEL_NAME" "$TIMEPULSE_DOMAIN" || true
cloudflared tunnel route dns "$TUNNEL_NAME" "www.$TIMEPULSE_DOMAIN" || true
cloudflared tunnel route dns "$TUNNEL_NAME" "$OPTIROTA_DOMAIN" || true

# Instalar serviço
cloudflared service install || true
systemctl restart cloudflared

echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          INSTALAÇÃO COMPLETA COM SUCESSO!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════╝${NC}"
echo -e "Acesse:"
echo -e "1. ${BOLD}https://$TIMEPULSE_DOMAIN${NC}"
echo -e "2. ${BOLD}https://$OPTIROTA_DOMAIN${NC}"
