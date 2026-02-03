#!/bin/bash

# =============================================================================
# TimePulse AI - Script de Instalação Completa VPS (Cloudflare Tunnel Edition)
# Versão: 4.2 - Fix: Docker Build & LSOF Dependency
# =============================================================================

set -euo pipefail

# 1. Instalação imediata de dependências críticas para o script
apt update && apt install -y lsof curl wget

# Correção de PATH
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

# Banner
echo -e "${BLUE}"
cat << "EOF"
 ╔═══════════════════════════════════════════════════════╗
 ║           TimePulse AI VPS Installer v4.2             ║
 ║        FIX: DOCKER BUILD & CLEAN INSTALL              ║
 ╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script deve ser executado como root (sudo)"
   exit 1
fi

# Configurações
DOMAIN="${1:-timepulseai.com.br}"
INSTALL_DIR="/opt/timepulse"

# =============================================================================
# ETAPA DE LIMPEZA (RESET TOTAL)
# =============================================================================
log_step "Limpando instalação anterior..."

systemctl stop cloudflared 2>/dev/null || true
docker stop timepulse-app 2>/dev/null || true
docker rm timepulse-app 2>/dev/null || true
rm -rf $INSTALL_DIR
rm -rf /etc/cloudflared
rm -f /usr/local/bin/optirota-logs

# Limpar processos na porta 3001
PID_3001=$(lsof -t -i:3001 || true)
if [ ! -z "$PID_3001" ]; then kill -9 $PID_3001; fi

log_success "Ambiente limpo!"

# =============================================================================
# ETAPA 1: DEPENDÊNCIAS
# =============================================================================
log_step "ETAPA 1/10 - Instalando dependências do sistema..."
apt update && apt upgrade -y
apt install -y git gnupg lsb-release software-properties-common ufw jq openssl procps nginx apache2

# Instalação do Cloudflared
ARCH=$(uname -m)
CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
if [[ "$ARCH" != "x86_64" ]]; then
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"
fi
wget -q -O cloudflared.deb "$CF_URL"
dpkg -i cloudflared.deb || apt install -f -y
rm cloudflared.deb

# =============================================================================
# ETAPA 2: DOCKER
# =============================================================================
log_step "ETAPA 2/10 - Configurando Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi
apt install -y docker-compose-plugin
systemctl enable docker && systemctl start docker

# =============================================================================
# ETAPA 3: APACHE GATEWAY
# =============================================================================
log_step "ETAPA 3/10 - Configurando Apache..."
a2enmod proxy proxy_http proxy_wstunnel rewrite headers 2>/dev/null || true
systemctl restart apache2

# =============================================================================
# ETAPA 4: FIREWALL
# =============================================================================
log_step "ETAPA 4/10 - Configurando Firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# =============================================================================
# ETAPA 5: ESTRUTURA E ARQUIVOS
# =============================================================================
log_step "ETAPA 5/10 - Criando diretórios..."
mkdir -p $INSTALL_DIR/{public,api,logs}
cd $INSTALL_DIR

# Criar arquivos básicos para o Build não falhar
log_info "Gerando arquivos base da aplicação..."
cat > package.json << 'EOF'
{
  "name": "timepulse-ai",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "helmet": "^7.0.0"
  }
}
EOF

cat > server.js << 'EOF'
const express = require('express');
const app = express();
app.get('/', (req, res) => res.send('TimePulse AI Online'));
app.listen(3001, '0.0.0.0', () => console.log('Server on 3001'));
EOF

# =============================================================================
# ETAPA 6: VARIÁVEIS .ENV
# =============================================================================
log_step "ETAPA 6/10 - Configurando variáveis .env..."
echo -e "${YELLOW}=== CONFIGURAÇÃO DO AMBIENTE ===${NC}"
read -p "URL do Supabase: " SUPABASE_URL
read -p "Supabase Anon Key: " SUPABASE_ANON_KEY
read -p "Supabase Service Role Key: " SUPABASE_SERVICE_ROLE_KEY
read -p "OpenAI API Key: " OPENAI_API_KEY
read -p "Mapbox Token: " MAPBOX_TOKEN
read -p "Evolution API Base URL: " EVOLUTION_API_BASE_URL
read -p "Evolution API Key: " EVOLUTION_API_KEY

cat > .env << EOF
NODE_ENV=production
PORT=3001
DOMAIN=$DOMAIN
SUPABASE_URL=$SUPABASE_URL
SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY
OPENAI_API_KEY=$OPENAI_API_KEY
MAPBOX_TOKEN=$MAPBOX_TOKEN
EVOLUTION_API_BASE_URL=$EVOLUTION_API_BASE_URL
EVOLUTION_API_KEY=$EVOLUTION_API_KEY
EOF

# =============================================================================
# ETAPA 7: DOCKER CONFIG (FIX: npm install)
# =============================================================================
log_step "ETAPA 7/10 - Criando Dockerfile..."
cat > Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache python3 make g++
COPY package*.json ./
# Trocado 'npm ci' por 'npm install' para evitar erro de package-lock ausente
RUN npm install --only=production
COPY . .
EXPOSE 3001
CMD ["node", "server.js"]
EOF

cat > docker-compose.yml << EOF
services:
  timepulse:
    build: .
    container_name: timepulse-app
    restart: unless-stopped
    ports:
      - "127.0.0.1:3001:3001"
    env_file: .env
    volumes:
      - ./logs:/app/logs
EOF

# =============================================================================
# ETAPA 8: APACHE VHOST
# =============================================================================
log_step "ETAPA 8/10 - Configurando Gateway Apache..."
cat > /etc/apache2/sites-available/$DOMAIN.conf << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:3001/
    ProxyPassReverse / http://127.0.0.1:3001/
</VirtualHost>
EOF
a2ensite $DOMAIN.conf >/dev/null 2>&1 || true
systemctl reload apache2

# =============================================================================
# ETAPA 9: BUILD
# =============================================================================
log_step "ETAPA 9/10 - Iniciando containers..."
docker compose build
docker compose up -d

# =============================================================================
# ETAPA 10: CLOUDFLARE
# =============================================================================
log_step "ETAPA 10/10 - Configurando Túnel Cloudflare..."
log_warning "AUTORIZE O TÚNEL NO LINK QUE APARECERÁ ABAIXO"
sleep 2
cloudflared tunnel login

TUNNEL_NAME="timepulse-vps-tunnel"
cloudflared tunnel delete -f $TUNNEL_NAME 2>/dev/null || true
TUNNEL_INFO=$(cloudflared tunnel create $TUNNEL_NAME)
TUNNEL_ID=$(echo "$TUNNEL_INFO" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")

mkdir -p /etc/cloudflared
cat << EOF > /etc/cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json
ingress:
  - hostname: $DOMAIN
    service: http://localhost:80
  - hostname: www.$DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

cloudflared tunnel route dns $TUNNEL_NAME $DOMAIN
cloudflared tunnel route dns $TUNNEL_NAME www.$DOMAIN
cloudflared service install || true
systemctl restart cloudflared

echo "docker compose -f $INSTALL_DIR/docker-compose.yml logs -f" > /usr/local/bin/optirota-logs
chmod +x /usr/local/bin/optirota-logs

log_success "🎉 Instalação concluída! HTTPS gerenciado pela Cloudflare."
