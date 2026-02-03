#!/bin/bash

# =============================================================================
# TimePulse AI - Script de Instalação Completa VPS (Cloudflare Tunnel Edition)
# Versão: 4.0 - Docker + Apache Local + Cloudflare Tunnel
# =============================================================================

set -euo pipefail

# Correção de PATH para garantir comandos de sistema
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Funções de log
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

# Banner
echo -e "${BLUE}"
cat << "EOF"
 ╔═══════════════════════════════════════════════════════╗
 ║           TimePulse AI VPS Installer v4.0             ║
 ║      Docker + Apache + Cloudflare Tunnel (SSL)        ║
 ╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script deve ser executado como root (sudo)"
   exit 1
fi

# Configurações iniciais
DOMAIN="${1:-timepulseai.com.br}"
EMAIL="${2:-luisleite@timepulseai.com.br}"
INSTALL_DIR="/opt/timepulse"

log_step "Configuração definida:"
log_info "Domínio: $DOMAIN"
log_info "Diretório: $INSTALL_DIR"
echo ""

read -p "Continuar com a instalação via Cloudflare Tunnel? (y/n): " CONFIRM
if [[ $CONFIRM != "y" ]]; then
    log_info "Instalação cancelada"
    exit 0
fi

# =============================================================================
# ETAPA 1: ATUALIZAR SISTEMA E INSTALAR CLOUDFLARED
# =============================================================================
log_step "ETAPA 1/10 - Atualizando sistema e instalando dependências..."
apt update && apt upgrade -y
apt install -y curl git wget gnupg lsb-release software-properties-common ufw jq openssl procps lsof nginx apache2

# Instalar Cloudflared (Binário direto para evitar erros de repositório)
log_info "Instalando Cloudflared..."
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
else
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"
fi
wget -q -O cloudflared.deb "$CF_URL"
dpkg -i cloudflared.deb || apt install -f -y
rm cloudflared.deb

log_success "Sistema e Cloudflared preparados"

# =============================================================================
# ETAPA 2: INSTALAR DOCKER
# =============================================================================
log_step "ETAPA 2/10 - Instalando Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
fi
apt install -y docker-compose-plugin
systemctl enable docker && systemctl start docker
log_success "Docker instalado: $(docker --version)"

# =============================================================================
# ETAPA 3: CONFIGURAR APACHE (GATEWAY LOCAL)
# =============================================================================
log_step "ETAPA 3/10 - Configurando Apache (Local Proxy)..."
# Habilitar módulos
a2enmod proxy proxy_http proxy_wstunnel rewrite headers
systemctl enable apache2 && systemctl start apache2

# =============================================================================
# ETAPA 4: FIREWALL
# =============================================================================
log_step "ETAPA 4/10 - Configurando Firewall..."
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
log_success "Firewall ativo (Portas 22, 80 e 443 abertas)"

# =============================================================================
# ETAPA 5: CRIAR ESTRUTURA
# =============================================================================
log_step "ETAPA 5/10 - Criando diretórios..."
mkdir -p $INSTALL_DIR/{public,api,logs}
cd $INSTALL_DIR

# =============================================================================
# ETAPA 6: VARIÁVEIS DE AMBIENTE
# =============================================================================
log_step "ETAPA 6/10 - Configurando .env..."
echo -e "${YELLOW}=== INSIRA AS CHAVES DA API ===${NC}"
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
CORS_ORIGINS=https://$DOMAIN,https://www.$DOMAIN
EOF
chmod 600 .env

# =============================================================================
# ETAPA 7: DOCKER FILES
# =============================================================================
log_step "ETAPA 7/10 - Gerando Dockerfile e Compose..."

cat > Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache python3 make g++
COPY package*.json ./
RUN npm ci --only=production
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
# ETAPA 8: CONFIGURAR APACHE VHOST
# =============================================================================
log_step "ETAPA 8/10 - Configurando VHost Apache..."
cat > /etc/apache2/sites-available/$DOMAIN.conf << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN

    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:3001/
    ProxyPassReverse / http://127.0.0.1:3001/

    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) "ws://127.0.0.1:3001/\$1" [P,L]
</VirtualHost>
EOF

a2ensite $DOMAIN.conf
a2dissite 000-default.conf
systemctl reload apache2

# =============================================================================
# ETAPA 9: SUBIR CONTAINERS
# =============================================================================
log_step "ETAPA 9/10 - Subindo aplicação..."
# Limpar porta se necessário
PID_5000=$(lsof -t -i:5000 || true)
if [ ! -z "$PID_5000" ]; then kill -9 $PID_5000; fi

docker compose build
docker compose up -d
log_success "Aplicação rodando localmente na porta 3001"

# =============================================================================
# ETAPA 10: CLOUDFLARE TUNNEL
# =============================================================================
log_step "ETAPA 10/10 - Configurando Cloudflare Tunnel..."

log_warning "1. Um link de login aparecerá agora. Copie-o, abra no navegador e autorize seu domínio."
sleep 3
cloudflared tunnel login

TUNNEL_NAME="timepulse-tunnel"
cloudflared tunnel delete -f $TUNNEL_NAME >/dev/null 2>&1 || true

log_info "Criando túnel..."
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

log_info "Roteando DNS via Cloudflare..."
cloudflared tunnel route dns $TUNNEL_NAME $DOMAIN
cloudflared tunnel route dns $TUNNEL_NAME www.$DOMAIN

log_info "Instalando serviço do túnel..."
cloudflared service install || true
systemctl enable cloudflared
systemctl restart cloudflared

# =============================================================================
# RESUMO
# =============================================================================
echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          INSTALAÇÃO CONCLUÍDA COM SUCESSO!            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
log_info "Acesse: https://$DOMAIN"
log_info "O SSL agora é gerenciado pela Cloudflare Edge."
log_info "Use 'optirota-logs' ou 'docker compose logs -f' para monitorar."

# Script de logs rápido
echo "docker compose -f $INSTALL_DIR/docker-compose.yml logs -f" > /usr/local/bin/optirota-logs
chmod +x /usr/local/bin/optirota-logs
