#!/bin/bash

# ==========================================================================
# TimePulse AI + OptiRota - Instalador Combinado (Debian/Ubuntu)
# Versao: 3.1 (FIX: Memory Swap + Node Heap Limit + Canvas)
# ==========================================================================

set -e
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Cores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configurações
TIMEPULSE_DIR="/opt/timepulse"
OPTIROTA_DIR="/opt/optirota"
TIMEPULSE_DOMAIN="timepulseai.com.br"
OPTIROTA_DOMAIN="optirota.timepulseai.com.br"

# ==========================================================================
# PASSO 1: Configurar SWAP (Evita o erro "Out of Memory")
# ==========================================================================
echo -e "${BLUE}[1/12] Verificando Memória Swap...${NC}"
if [ $(free | grep -i swap | awk '{print $2}') -lt 1000000 ]; then
    echo -e "${YELLOW}Pouca memória detectada. Criando arquivo Swap de 2GB...${NC}"
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo -e "${GREEN}Swap de 2GB criado com sucesso!${NC}"
else
    echo -e "${GREEN}Memória Swap já existente.${NC}"
fi

# ==========================================================================
# PASSO 2: Dependencias do Sistema
# ==========================================================================
echo -e "${BLUE}[2/12] Instalando Dependências...${NC}"
apt-get update -qq
apt-get install -y curl wget git nginx psmisc openssl ca-certificates gnupg lsb-release lsof

if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker && systemctl start docker
fi
apt-get install -y docker-compose-plugin

# ==========================================================================
# PASSO 3: Instalar Cloudflared
# ==========================================================================
ARCH=$(uname -m)
CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
if [[ "$ARCH" != "x86_64" ]]; then CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"; fi
wget -q -O /tmp/cloudflared.deb "$CF_URL"
dpkg -i /tmp/cloudflared.deb || apt-get install -f -y

# ==========================================================================
# PASSO 4: Download e Limpeza
# ==========================================================================
echo -e "${BLUE}[4/12] Baixando Códigos...${NC}"
docker stop timepulse-app optirota-app 2>/dev/null || true
docker rm timepulse-app optirota-app 2>/dev/null || true

mkdir -p $TIMEPULSE_DIR $OPTIROTA_DIR
git clone --depth 1 "https://github.com/luishplleite/aisisten.git" "$TIMEPULSE_DIR" || (cd $TIMEPULSE_DIR && git pull)
git clone --depth 1 "https://github.com/luishplleite/rota-certa.git" "$OPTIROTA_DIR" || (cd $OPTIROTA_DIR && git pull)

# ==========================================================================
# PASSO 5: Credenciais (Apenas para garantir a criação dos arquivos)
# ==========================================================================
# (Execute os prompts aqui ou preencha manualmente após o script rodar)
echo -e "${YELLOW}Certifique-se de configurar os arquivos .env em $TIMEPULSE_DIR e $OPTIROTA_DIR antes de usar.${NC}"

# ==========================================================================
# PASSO 7: Dockerfiles (COM LIMITE DE MEMÓRIA E DEPENDÊNCIAS CANVAS)
# ==========================================================================

# --- Dockerfile TimePulse AI ---
cat << 'DOCKERFILE' > $TIMEPULSE_DIR/Dockerfile
FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache python3 make g++ pkgconfig pixman-dev cairo-dev pango-dev jpeg-dev giflib-dev librsvg-dev
COPY package*.json ./
# Definir limite de memoria para instalacao de pacotes
ENV NODE_OPTIONS="--max-old-space-size=1536"
RUN npm install --omit=dev
COPY . .
EXPOSE 5000
CMD ["npm", "start"]
DOCKERFILE

# --- Dockerfile OptiRota (O PONTO QUE FALHOU ANTES) ---
cat << 'DOCKERFILE' > $OPTIROTA_DIR/Dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
RUN apk add --no-cache python3 make g++ pkgconfig pixman-dev cairo-dev pango-dev jpeg-dev giflib-dev librsvg-dev
COPY package*.json ./
# AUMENTO DE MEMORIA PARA O BUILD DO VITE
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
DOCKERFILE

# --- docker-compose files ---
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
# PASSO 8: Build e Start
# ==========================================================================
echo -e "${YELLOW}Iniciando builds (Com Swap e Limite de 1.5GB RAM)...${NC}"

cd $TIMEPULSE_DIR && docker compose build --no-cache && docker compose up -d
cd $OPTIROTA_DIR && docker compose build --no-cache && docker compose up -d

# ==========================================================================
# PASSO 9: Nginx Gateway
# ==========================================================================
cat << EOF > /etc/nginx/sites-available/combined_apps
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
ln -sf /etc/nginx/sites-available/combined_apps /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default || true
systemctl restart nginx

# ==========================================================================
# PASSO 10: Cloudflare Tunnel
# ==========================================================================
echo -e "${YELLOW}Faça login no Cloudflare agora:${NC}"
cloudflared tunnel login

TUNNEL_NAME="timepulse-combined-vps"
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

echo -e "${GREEN}🚀 Instalação Concluída com Sucesso e Prevenção de Memória!${NC}"
