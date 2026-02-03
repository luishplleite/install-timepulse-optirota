#!/bin/bash

# ==========================================================================
# TimePulse AI + OptiRota - Instalador Combinado (Debian/Ubuntu)
# Versao: 2.0 (Fix: npm install + Build corrigido)
# Desenvolvido para: Luis - Santos/SP
# ==========================================================================
# 
# Este script instala DUAS aplicacoes em containers Docker separados:
#
# 1. TimePulse AI (Sistema de Gestao para Delivery)
#    - Repositorio: https://github.com/luishplleite/aisisten.git
#    - URL: https://timepulseai.com.br/
#    - Porta: 5000
#
# 2. OptiRota (Sistema de Otimizacao de Rotas)
#    - Repositorio: https://github.com/luishplleite/rota-certa.git
#    - URL: https://optirota.timepulseai.com.br/
#    - Porta: 5001
#
# ==========================================================================

set -e

# GARANTIR PATH DO SISTEMA
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Cores para saida
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Diretorios de instalacao
TIMEPULSE_DIR="/opt/timepulse"
OPTIROTA_DIR="/opt/optirota"

# Repositorios
TIMEPULSE_REPO="https://github.com/luishplleite/aisisten.git"
OPTIROTA_REPO="https://github.com/luishplleite/rota-certa.git"

# Dominios (pre-definidos)
TIMEPULSE_DOMAIN="timepulseai.com.br"
OPTIROTA_DOMAIN="optirota.timepulseai.com.br"

print_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     TIMEPULSE AI + OPTIROTA - INSTALADOR COMBINADO v2.0 (PRODUCAO)       ║${NC}"
    echo -e "${BLUE}║              Cloudflare Tunnel + Docker + Nginx                          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Aplicacoes a serem instaladas:${NC}"
    echo -e "  ${MAGENTA}1. TimePulse AI${NC} → https://$TIMEPULSE_DOMAIN"
    echo -e "  ${MAGENTA}2. OptiRota${NC}     → https://$OPTIROTA_DOMAIN"
    echo ""
}

print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}[$1/$2]${NC} $3"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_section() {
    echo -e "\n${CYAN}▶ $1${NC}"
}

print_app_header() {
    echo -e "\n${MAGENTA}╔══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║  $1${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════════╝${NC}"
}

# Verificar se e root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Erro: Execute como root (sudo ./install-timepulse-optirota.sh)${NC}"
    exit 1
fi

print_header
TOTAL_STEPS=12

# ==========================================================================
# PASSO 1: Dependencias do Sistema
# ==========================================================================
print_step 1 $TOTAL_STEPS "Instalando dependencias do sistema..."
apt-get update -qq
apt-get install -y curl wget git nginx psmisc openssl ca-certificates gnupg lsb-release lsof

# Instalar Docker se nao existir
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Instalando Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# Instalar docker-compose plugin se nao existir
if ! docker compose version &> /dev/null; then
    apt-get install -y docker-compose-plugin
fi

echo -e "${GREEN}Dependencias instaladas com sucesso!${NC}"

# ==========================================================================
# PASSO 2: Instalar Cloudflared
# ==========================================================================
print_step 2 $TOTAL_STEPS "Instalando Cloudflared..."
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then 
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb"
elif [[ "$ARCH" == "aarch64" ]]; then 
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb"
else 
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm.deb"
fi

wget -q -O /tmp/cloudflared.deb "$CF_URL"
dpkg -i /tmp/cloudflared.deb || apt-get install -f -y
rm -f /tmp/cloudflared.deb
echo -e "${GREEN}Cloudflared instalado: $(cloudflared --version)${NC}"

# ==========================================================================
# PASSO 3: Limpeza de processos anteriores
# ==========================================================================
print_step 3 $TOTAL_STEPS "Limpando processos e instalacoes anteriores..."

# Parar servicos
systemctl stop cloudflared 2>/dev/null || true

# Limpar portas
lsof -t -i:5000 | xargs -r kill -9 2>/dev/null || true
lsof -t -i:5001 | xargs -r kill -9 2>/dev/null || true

# Parar e remover containers
docker stop timepulse-app 2>/dev/null || true
docker stop optirota-app 2>/dev/null || true
docker rm timepulse-app 2>/dev/null || true
docker rm optirota-app 2>/dev/null || true

# Limpar imagens antigas (opcional)
docker image prune -f 2>/dev/null || true

# Limpar configuracao cloudflared anterior
rm -rf /etc/cloudflared 2>/dev/null || true

echo -e "${GREEN}Limpeza concluida!${NC}"

# ==========================================================================
# PASSO 4: Download dos Codigos
# ==========================================================================
print_step 4 $TOTAL_STEPS "Baixando codigo das aplicacoes..."

# TimePulse AI
echo -e "${YELLOW}Baixando TimePulse AI...${NC}"
if [ -d "$TIMEPULSE_DIR" ]; then 
    BACKUP_DIR="${TIMEPULSE_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Backup: $BACKUP_DIR${NC}"
    mv "$TIMEPULSE_DIR" "$BACKUP_DIR"
fi
git clone --depth 1 "$TIMEPULSE_REPO" "$TIMEPULSE_DIR"
echo -e "${GREEN}TimePulse AI baixado em: $TIMEPULSE_DIR${NC}"

# OptiRota
echo -e "${YELLOW}Baixando OptiRota...${NC}"
if [ -d "$OPTIROTA_DIR" ]; then 
    BACKUP_DIR="${OPTIROTA_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}Backup: $BACKUP_DIR${NC}"
    mv "$OPTIROTA_DIR" "$BACKUP_DIR"
fi
git clone --depth 1 "$OPTIROTA_REPO" "$OPTIROTA_DIR"
echo -e "${GREEN}OptiRota baixado em: $OPTIROTA_DIR${NC}"

# ==========================================================================
# PASSO 5: Configuracao TimePulse AI
# ==========================================================================
print_step 5 $TOTAL_STEPS "Configurando variaveis de ambiente - TimePulse AI..."

print_app_header "TIMEPULSE AI - CONFIGURACAO DE CREDENCIAIS"

echo -e "${YELLOW}"
echo "Sistema de Gestao para Delivery com IA"
echo "URL: https://$TIMEPULSE_DOMAIN"
echo -e "${NC}"

# --- SUPABASE TIMEPULSE ---
print_section "SUPABASE (TimePulse AI)"
echo -e "Obtenha em: https://supabase.com → Seu Projeto → Settings → API"

read -p "SUPABASE_URL: " tp_supabase_url
while [ -z "$tp_supabase_url" ]; do
    echo -e "${RED}SUPABASE_URL e obrigatorio!${NC}"
    read -p "SUPABASE_URL: " tp_supabase_url
done

read -p "SUPABASE_ANON_KEY: " tp_supabase_anon_key
while [ -z "$tp_supabase_anon_key" ]; do
    echo -e "${RED}SUPABASE_ANON_KEY e obrigatorio!${NC}"
    read -p "SUPABASE_ANON_KEY: " tp_supabase_anon_key
done

read -p "SUPABASE_SERVICE_ROLE_KEY: " tp_supabase_service_key
while [ -z "$tp_supabase_service_key" ]; do
    echo -e "${RED}SUPABASE_SERVICE_ROLE_KEY e obrigatorio!${NC}"
    read -p "SUPABASE_SERVICE_ROLE_KEY: " tp_supabase_service_key
done

# --- OPENAI TIMEPULSE ---
print_section "OPENAI (Assistente Ana - TimePulse AI)"
echo -e "Obtenha em: https://platform.openai.com/api-keys"

read -p "OPENAI_API_KEY: " tp_openai_key
while [ -z "$tp_openai_key" ]; do
    echo -e "${RED}OPENAI_API_KEY e obrigatorio!${NC}"
    read -p "OPENAI_API_KEY: " tp_openai_key
done

# --- MAPBOX TIMEPULSE ---
print_section "MAPBOX (Mapas - TimePulse AI)"
echo -e "Obtenha em: https://account.mapbox.com/access-tokens/"

read -p "MAPBOX_TOKEN: " tp_mapbox_token
while [ -z "$tp_mapbox_token" ]; do
    echo -e "${RED}MAPBOX_TOKEN e obrigatorio!${NC}"
    read -p "MAPBOX_TOKEN: " tp_mapbox_token
done

# --- EVOLUTION API TIMEPULSE ---
print_section "EVOLUTION API (WhatsApp - TimePulse AI)"
echo -e "Servidor Evolution API para integracao WhatsApp"

read -p "EVOLUTION_API_BASE_URL (ex: https://evolution.seudominio.com): " tp_evolution_url
while [ -z "$tp_evolution_url" ]; do
    echo -e "${RED}EVOLUTION_API_BASE_URL e obrigatorio!${NC}"
    read -p "EVOLUTION_API_BASE_URL: " tp_evolution_url
done

read -p "EVOLUTION_API_KEY: " tp_evolution_key
while [ -z "$tp_evolution_key" ]; do
    echo -e "${RED}EVOLUTION_API_KEY e obrigatorio!${NC}"
    read -p "EVOLUTION_API_KEY: " tp_evolution_key
done

# --- Criar .env TimePulse AI ---
cat << EOF > $TIMEPULSE_DIR/.env
# =================================================
# TimePulse AI - Variaveis de Ambiente (Producao)
# Gerado automaticamente em: $(date)
# =================================================

# Aplicacao
NODE_ENV=production
PORT=5000
DOMAIN=$TIMEPULSE_DOMAIN

# Supabase
SUPABASE_URL=$tp_supabase_url
SUPABASE_ANON_KEY=$tp_supabase_anon_key
SUPABASE_SERVICE_ROLE_KEY=$tp_supabase_service_key

# OpenAI (Assistente Ana)
OPENAI_API_KEY=$tp_openai_key

# Mapbox (Mapas)
MAPBOX_TOKEN=$tp_mapbox_token

# Evolution API (WhatsApp)
EVOLUTION_API_BASE_URL=$tp_evolution_url
EVOLUTION_API_KEY=$tp_evolution_key
EOF

echo -e "${GREEN}Arquivo .env do TimePulse AI criado!${NC}"

# ==========================================================================
# PASSO 6: Configuracao OptiRota
# ==========================================================================
print_step 6 $TOTAL_STEPS "Configurando variaveis de ambiente - OptiRota..."

print_app_header "OPTIROTA - CONFIGURACAO DE CREDENCIAIS"

echo -e "${YELLOW}"
echo "Sistema de Otimizacao de Rotas para Entregas"
echo "URL: https://$OPTIROTA_DOMAIN"
echo -e "${NC}"

# --- SUPABASE OPTIROTA ---
print_section "SUPABASE (OptiRota)"
echo -e "Obtenha em: https://supabase.com → Seu Projeto → Settings → API"
echo -e "${YELLOW}Nota: Pode ser o mesmo Supabase do TimePulse ou outro projeto${NC}"

read -p "SUPABASE_URL: " or_supabase_url
while [ -z "$or_supabase_url" ]; do
    echo -e "${RED}SUPABASE_URL e obrigatorio!${NC}"
    read -p "SUPABASE_URL: " or_supabase_url
done

read -p "SUPABASE_SERVICE_ROLE_KEY: " or_supabase_key
while [ -z "$or_supabase_key" ]; do
    echo -e "${RED}SUPABASE_SERVICE_ROLE_KEY e obrigatorio!${NC}"
    read -p "SUPABASE_SERVICE_ROLE_KEY: " or_supabase_key
done

# --- STRIPE OPTIROTA ---
print_section "STRIPE (Pagamentos PIX - OptiRota)"
echo -e "Obtenha em: https://dashboard.stripe.com/apikeys"

read -p "STRIPE_PUBLISHABLE_KEY (pk_live_... ou pk_test_...): " or_stripe_pub_key
while [ -z "$or_stripe_pub_key" ]; do
    echo -e "${RED}STRIPE_PUBLISHABLE_KEY e obrigatorio!${NC}"
    read -p "STRIPE_PUBLISHABLE_KEY: " or_stripe_pub_key
done

read -p "STRIPE_SECRET_KEY (sk_live_... ou sk_test_...): " or_stripe_secret_key
while [ -z "$or_stripe_secret_key" ]; do
    echo -e "${RED}STRIPE_SECRET_KEY e obrigatorio!${NC}"
    read -p "STRIPE_SECRET_KEY: " or_stripe_secret_key
done

echo -e "${YELLOW}Para webhooks, configure em: https://dashboard.stripe.com/webhooks${NC}"
echo -e "Endpoint: https://$OPTIROTA_DOMAIN/api/stripe/webhook"
echo -e "Eventos: checkout.session.completed, customer.subscription.updated, customer.subscription.deleted"

read -p "STRIPE_WEBHOOK_SECRET (whsec_...): " or_stripe_webhook_secret
while [ -z "$or_stripe_webhook_secret" ]; do
    echo -e "${RED}STRIPE_WEBHOOK_SECRET e obrigatorio!${NC}"
    read -p "STRIPE_WEBHOOK_SECRET: " or_stripe_webhook_secret
done

# --- GOOGLE MAPS OPTIROTA ---
print_section "GOOGLE MAPS API (Mapas e Rotas - OptiRota)"
echo -e "Obtenha em: https://console.cloud.google.com/apis/credentials"
echo -e "APIs necessarias: Maps JavaScript API, Geocoding API, Directions API"

read -p "GOOGLE_MAPS_API_KEY: " or_google_maps_key
while [ -z "$or_google_maps_key" ]; do
    echo -e "${RED}GOOGLE_MAPS_API_KEY e obrigatoria!${NC}"
    read -p "GOOGLE_MAPS_API_KEY: " or_google_maps_key
done

# --- Gerar SESSION_SECRET ---
OR_SESSION_SECRET=$(openssl rand -base64 32)

# --- Criar .env OptiRota ---
cat << EOF > $OPTIROTA_DIR/.env
# =================================================
# OptiRota - Variaveis de Ambiente (Producao)
# Gerado automaticamente em: $(date)
# =================================================

# Aplicacao
NODE_ENV=production
PORT=5000
DOMAIN=$OPTIROTA_DOMAIN
SESSION_SECRET=$OR_SESSION_SECRET

# Supabase
SUPABASE_URL=$or_supabase_url
SUPABASE_SERVICE_ROLE_KEY=$or_supabase_key

# Stripe (Pagamentos PIX)
STRIPE_PUBLISHABLE_KEY=$or_stripe_pub_key
STRIPE_SECRET_KEY=$or_stripe_secret_key
STRIPE_WEBHOOK_SECRET=$or_stripe_webhook_secret

# Google Maps API
GOOGLE_MAPS_API_KEY=$or_google_maps_key
VITE_GOOGLE_MAPS_API_KEY=$or_google_maps_key
EOF

echo -e "${GREEN}Arquivo .env do OptiRota criado!${NC}"

# ==========================================================================
# PASSO 7: Criar Dockerfiles (FIX: usar npm install em vez de npm ci)
# ==========================================================================
print_step 7 $TOTAL_STEPS "Criando arquivos Docker..."

# --- Dockerfile TimePulse AI (FIX: canvas dependencies) ---
cat << 'DOCKERFILE' > $TIMEPULSE_DIR/Dockerfile
# =================================================
# TimePulse AI - Dockerfile de Producao
# =================================================
FROM node:20-alpine

WORKDIR /app

# Instalar dependencias de compilacao para canvas e outros pacotes nativos
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    pkgconfig \
    cairo-dev \
    pango-dev \
    jpeg-dev \
    giflib-dev \
    librsvg-dev \
    pixman-dev

# Copiar package files
COPY package*.json ./

# Instalar dependencias (npm install em vez de npm ci)
RUN npm install --omit=dev

# Copiar codigo fonte
COPY . .

# Expor porta
EXPOSE 5000

# Iniciar aplicacao
CMD ["npm", "start"]
DOCKERFILE

# --- docker-compose.yml TimePulse AI ---
cat << 'COMPOSE' > $TIMEPULSE_DIR/docker-compose.yml
# =================================================
# TimePulse AI - Docker Compose (Producao)
# =================================================
services:
  timepulse:
    build: .
    container_name: timepulse-app
    restart: unless-stopped
    ports:
      - "127.0.0.1:5000:5000"
    env_file: .env
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:5000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
COMPOSE

# --- Dockerfile OptiRota (FIX: canvas dependencies + build) ---
cat << 'DOCKERFILE' > $OPTIROTA_DIR/Dockerfile
# =================================================
# OptiRota - Dockerfile de Producao
# Multi-stage build para otimizacao
# =================================================
FROM node:20-alpine AS builder

WORKDIR /app

# Instalar dependencias de compilacao para canvas e outros pacotes nativos
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    pkgconfig \
    cairo-dev \
    pango-dev \
    jpeg-dev \
    giflib-dev \
    librsvg-dev \
    pixman-dev

# Copiar package files
COPY package*.json ./

# Instalar TODAS as dependencias (incluindo dev para build)
RUN npm install

# Copiar codigo fonte
COPY . .

# Build da aplicacao
RUN npm run build

# =================================================
# Imagem de Producao (menor)
# =================================================
FROM node:20-alpine

WORKDIR /app

# Instalar dependencias de runtime para canvas e outros pacotes nativos
RUN apk add --no-cache \
    python3 \
    make \
    g++ \
    pkgconfig \
    cairo-dev \
    pango-dev \
    jpeg-dev \
    giflib-dev \
    librsvg-dev \
    pixman-dev

# Copiar package files
COPY package*.json ./

# Instalar apenas dependencias de producao
RUN npm install --omit=dev

# Copiar build
COPY --from=builder /app/dist ./dist

# Expor porta
EXPOSE 5000

# Iniciar aplicacao
CMD ["node", "dist/index.cjs"]
DOCKERFILE

# --- docker-compose.yml OptiRota (porta 5001 no host) ---
cat << 'COMPOSE' > $OPTIROTA_DIR/docker-compose.yml
# =================================================
# OptiRota - Docker Compose (Producao)
# =================================================
services:
  optirota:
    build: .
    container_name: optirota-app
    restart: unless-stopped
    ports:
      - "127.0.0.1:5001:5000"
    env_file: .env
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:5000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
COMPOSE

echo -e "${GREEN}Arquivos Docker criados para ambas aplicacoes!${NC}"

# ==========================================================================
# PASSO 8: Build e Iniciar Containers
# ==========================================================================
print_step 8 $TOTAL_STEPS "Construindo e iniciando containers Docker..."

echo -e "${YELLOW}Construindo TimePulse AI (pode levar alguns minutos)...${NC}"
cd $TIMEPULSE_DIR
docker compose build --no-cache
docker compose up -d

echo -e "${YELLOW}Construindo OptiRota (pode levar alguns minutos)...${NC}"
cd $OPTIROTA_DIR
docker compose build --no-cache
docker compose up -d

# Aguardar containers iniciarem
echo -e "${YELLOW}Aguardando aplicacoes iniciarem...${NC}"
sleep 20

# Verificar se containers estao rodando
echo -e "\n${BOLD}Status dos Containers:${NC}"
if docker ps | grep -q timepulse-app; then
    echo -e "  TimePulse AI: ${GREEN}OK${NC}"
else
    echo -e "  TimePulse AI: ${RED}FALHOU - Verificando logs...${NC}"
    docker logs timepulse-app --tail 20 2>/dev/null || echo "Container nao iniciou"
fi

if docker ps | grep -q optirota-app; then
    echo -e "  OptiRota: ${GREEN}OK${NC}"
else
    echo -e "  OptiRota: ${RED}FALHOU - Verificando logs...${NC}"
    docker logs optirota-app --tail 20 2>/dev/null || echo "Container nao iniciou"
fi

# ==========================================================================
# PASSO 9: Configurar Nginx como Reverse Proxy
# ==========================================================================
print_step 9 $TOTAL_STEPS "Configurando Nginx como Gateway..."

# Configuracao TimePulse AI
cat << EOF > /etc/nginx/sites-available/timepulse
# =================================================
# TimePulse AI - Nginx Reverse Proxy
# =================================================
server {
    listen 80;
    server_name $TIMEPULSE_DOMAIN www.$TIMEPULSE_DOMAIN;

    # Logs
    access_log /var/log/nginx/timepulse_access.log;
    error_log /var/log/nginx/timepulse_error.log;

    # Proxy para aplicacao
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        
        # Headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Body size
        client_max_body_size 50M;
    }
}
EOF

# Configuracao OptiRota
cat << EOF > /etc/nginx/sites-available/optirota
# =================================================
# OptiRota - Nginx Reverse Proxy
# =================================================
server {
    listen 80;
    server_name $OPTIROTA_DOMAIN www.$OPTIROTA_DOMAIN;

    # Logs
    access_log /var/log/nginx/optirota_access.log;
    error_log /var/log/nginx/optirota_error.log;

    # Proxy para aplicacao
    location / {
        proxy_pass http://127.0.0.1:5001;
        proxy_http_version 1.1;
        
        # Headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Body size
        client_max_body_size 50M;
    }

    # Stripe Webhook
    location /api/stripe/webhook {
        proxy_pass http://127.0.0.1:5001;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        client_max_body_size 10M;
    }
}
EOF

# Ativar sites
ln -sf /etc/nginx/sites-available/timepulse /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/optirota /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Testar e reiniciar Nginx
nginx -t
systemctl restart nginx
systemctl enable nginx

echo -e "${GREEN}Nginx configurado para ambas aplicacoes!${NC}"

# ==========================================================================
# PASSO 10: Configurar Cloudflare Tunnel
# ==========================================================================
print_step 10 $TOTAL_STEPS "Configurando Cloudflare Tunnel..."

echo -e "${YELLOW}"
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║              AUTENTICACAO CLOUDFLARE TUNNEL                               ║"
echo "║                                                                           ║"
echo "║  1. Sera aberto um link de autenticacao                                  ║"
echo "║  2. Acesse o link e autorize o acesso                                    ║"
echo "║  3. Aguarde a confirmacao no terminal                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Pressione ENTER para iniciar a autenticacao Cloudflare..."

# Login no Cloudflare
cloudflared tunnel login

# Nome do tunnel (unico para ambas aplicacoes)
TUNNEL_NAME="timepulse-optirota-$(hostname)"

# Remover tunnel existente se houver
echo -e "${YELLOW}Removendo tunnel anterior se existir...${NC}"
cloudflared tunnel delete -f "$TUNNEL_NAME" 2>/dev/null || true

# Criar novo tunnel
echo -e "${YELLOW}Criando novo tunnel: $TUNNEL_NAME${NC}"
TUNNEL_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
echo "$TUNNEL_OUTPUT"

# Extrair ID do tunnel
TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep -oE "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" | head -1)

if [ -z "$TUNNEL_ID" ]; then
    echo -e "${RED}Erro ao obter ID do tunnel. Configure manualmente depois.${NC}"
else
    echo -e "${GREEN}Tunnel criado com ID: $TUNNEL_ID${NC}"
    
    # Criar configuracao do tunnel com AMBOS dominios
    mkdir -p /etc/cloudflared
    
    cat << EOF > /etc/cloudflared/config.yml
# =================================================
# TimePulse AI + OptiRota - Cloudflare Tunnel Config
# =================================================
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  # TimePulse AI
  - hostname: $TIMEPULSE_DOMAIN
    service: http://localhost:80
    originRequest:
      noTLSVerify: true
  
  - hostname: www.$TIMEPULSE_DOMAIN
    service: http://localhost:80
    originRequest:
      noTLSVerify: true
  
  # OptiRota
  - hostname: $OPTIROTA_DOMAIN
    service: http://localhost:80
    originRequest:
      noTLSVerify: true
  
  - hostname: www.$OPTIROTA_DOMAIN
    service: http://localhost:80
    originRequest:
      noTLSVerify: true
  
  # Catch-all (obrigatorio)
  - service: http_status:404
EOF

    # Configurar rotas DNS
    echo -e "${YELLOW}Configurando rotas DNS...${NC}"
    cloudflared tunnel route dns "$TUNNEL_NAME" "$TIMEPULSE_DOMAIN" 2>/dev/null || echo -e "${YELLOW}DNS $TIMEPULSE_DOMAIN: configurar manualmente${NC}"
    cloudflared tunnel route dns "$TUNNEL_NAME" "www.$TIMEPULSE_DOMAIN" 2>/dev/null || true
    cloudflared tunnel route dns "$TUNNEL_NAME" "$OPTIROTA_DOMAIN" 2>/dev/null || echo -e "${YELLOW}DNS $OPTIROTA_DOMAIN: configurar manualmente${NC}"
    cloudflared tunnel route dns "$TUNNEL_NAME" "www.$OPTIROTA_DOMAIN" 2>/dev/null || true
    
    # Instalar como servico
    cloudflared service install 2>/dev/null || true
    systemctl enable cloudflared
    systemctl restart cloudflared
    
    sleep 3
    if systemctl is-active --quiet cloudflared; then
        echo -e "${GREEN}Cloudflare Tunnel ativo e funcionando!${NC}"
    else
        echo -e "${YELLOW}Tunnel instalado. Verifique: systemctl status cloudflared${NC}"
    fi
fi

# ==========================================================================
# PASSO 11: Criar Scripts de Gerenciamento
# ==========================================================================
print_step 11 $TOTAL_STEPS "Criando scripts de gerenciamento..."

# Script de status
cat << 'SCRIPT' > /usr/local/bin/timepulse-status
#!/bin/bash
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                    STATUS DAS APLICACOES                          ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "TIMEPULSE AI:"
docker ps --filter "name=timepulse-app" --format "  Container: {{.Names}} | Status: {{.Status}}"
echo ""
echo "OPTIROTA:"
docker ps --filter "name=optirota-app" --format "  Container: {{.Names}} | Status: {{.Status}}"
echo ""
echo "NGINX:"
systemctl is-active --quiet nginx && echo "  Status: Ativo" || echo "  Status: Inativo"
echo ""
echo "CLOUDFLARE TUNNEL:"
systemctl is-active --quiet cloudflared && echo "  Status: Ativo" || echo "  Status: Inativo"
SCRIPT
chmod +x /usr/local/bin/timepulse-status

# Script de restart
cat << 'SCRIPT' > /usr/local/bin/timepulse-restart
#!/bin/bash
echo "Reiniciando todas as aplicacoes..."
cd /opt/timepulse && docker compose restart
cd /opt/optirota && docker compose restart
systemctl restart nginx
systemctl restart cloudflared
echo "Pronto!"
SCRIPT
chmod +x /usr/local/bin/timepulse-restart

# Script de logs
cat << 'SCRIPT' > /usr/local/bin/timepulse-logs
#!/bin/bash
case "$1" in
    timepulse)
        docker logs -f timepulse-app
        ;;
    optirota)
        docker logs -f optirota-app
        ;;
    tunnel)
        journalctl -u cloudflared -f
        ;;
    *)
        echo "Uso: timepulse-logs [timepulse|optirota|tunnel]"
        ;;
esac
SCRIPT
chmod +x /usr/local/bin/timepulse-logs

# Script de rebuild
cat << 'SCRIPT' > /usr/local/bin/timepulse-rebuild
#!/bin/bash
case "$1" in
    timepulse)
        echo "Rebuild TimePulse AI..."
        cd /opt/timepulse && docker compose down && docker compose build --no-cache && docker compose up -d
        ;;
    optirota)
        echo "Rebuild OptiRota..."
        cd /opt/optirota && docker compose down && docker compose build --no-cache && docker compose up -d
        ;;
    all)
        echo "Rebuild ambas aplicacoes..."
        cd /opt/timepulse && docker compose down && docker compose build --no-cache && docker compose up -d
        cd /opt/optirota && docker compose down && docker compose build --no-cache && docker compose up -d
        ;;
    *)
        echo "Uso: timepulse-rebuild [timepulse|optirota|all]"
        ;;
esac
SCRIPT
chmod +x /usr/local/bin/timepulse-rebuild

echo -e "${GREEN}Scripts de gerenciamento criados!${NC}"

# ==========================================================================
# PASSO 12: Finalizacao e Resumo
# ==========================================================================
print_step 12 $TOTAL_STEPS "Instalacao Finalizada!"

echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════════════════╗"
echo "║                      INSTALACAO CONCLUIDA!                                ║"
echo "╚══════════════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${BOLD}APLICACOES INSTALADAS:${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e ""
echo -e "  ${MAGENTA}1. TIMEPULSE AI${NC}"
echo -e "     URL:        ${CYAN}https://$TIMEPULSE_DOMAIN${NC}"
echo -e "     Container:  ${CYAN}timepulse-app${NC}"
echo -e "     Porta:      ${CYAN}5000${NC}"
echo -e "     Diretorio:  ${CYAN}$TIMEPULSE_DIR${NC}"
echo -e ""
echo -e "  ${MAGENTA}2. OPTIROTA${NC}"
echo -e "     URL:        ${CYAN}https://$OPTIROTA_DOMAIN${NC}"
echo -e "     Container:  ${CYAN}optirota-app${NC}"
echo -e "     Porta:      ${CYAN}5001${NC}"
echo -e "     Diretorio:  ${CYAN}$OPTIROTA_DIR${NC}"
echo ""

echo -e "${BOLD}COMANDOS DE GERENCIAMENTO:${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Ver status geral:     ${YELLOW}timepulse-status${NC}"
echo -e "  Reiniciar tudo:       ${YELLOW}timepulse-restart${NC}"
echo -e "  Logs TimePulse:       ${YELLOW}timepulse-logs timepulse${NC}"
echo -e "  Logs OptiRota:        ${YELLOW}timepulse-logs optirota${NC}"
echo -e "  Logs Tunnel:          ${YELLOW}timepulse-logs tunnel${NC}"
echo -e "  Rebuild TimePulse:    ${YELLOW}timepulse-rebuild timepulse${NC}"
echo -e "  Rebuild OptiRota:     ${YELLOW}timepulse-rebuild optirota${NC}"
echo -e "  Rebuild Ambas:        ${YELLOW}timepulse-rebuild all${NC}"
echo ""

echo -e "${BOLD}COMANDOS DOCKER INDIVIDUAIS:${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Logs TimePulse:       ${YELLOW}docker logs -f timepulse-app${NC}"
echo -e "  Logs OptiRota:        ${YELLOW}docker logs -f optirota-app${NC}"
echo -e "  Reiniciar TimePulse:  ${YELLOW}cd $TIMEPULSE_DIR && docker compose restart${NC}"
echo -e "  Reiniciar OptiRota:   ${YELLOW}cd $OPTIROTA_DIR && docker compose restart${NC}"
echo ""

echo -e "${BOLD}CONFIGURACOES STRIPE (OptiRota):${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  Configure o webhook no Stripe Dashboard:"
echo -e "  URL: ${CYAN}https://$OPTIROTA_DOMAIN/api/stripe/webhook${NC}"
echo -e "  Eventos: checkout.session.completed, customer.subscription.*"
echo ""

echo -e "${BOLD}EDITAR VARIAVEIS DE AMBIENTE:${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  TimePulse:  ${YELLOW}nano $TIMEPULSE_DIR/.env${NC}"
echo -e "  OptiRota:   ${YELLOW}nano $OPTIROTA_DIR/.env${NC}"
echo ""

# Verificacoes finais
echo -e "${BOLD}VERIFICACOES FINAIS:${NC}"
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if docker ps | grep -q timepulse-app; then
    echo -e "  TimePulse Docker:  ${GREEN}OK${NC}"
else
    echo -e "  TimePulse Docker:  ${RED}FALHOU - docker logs timepulse-app${NC}"
fi

if docker ps | grep -q optirota-app; then
    echo -e "  OptiRota Docker:   ${GREEN}OK${NC}"
else
    echo -e "  OptiRota Docker:   ${RED}FALHOU - docker logs optirota-app${NC}"
fi

if systemctl is-active --quiet nginx; then
    echo -e "  Nginx:             ${GREEN}OK${NC}"
else
    echo -e "  Nginx:             ${RED}FALHOU - systemctl status nginx${NC}"
fi

if systemctl is-active --quiet cloudflared; then
    echo -e "  Cloudflare:        ${GREEN}OK${NC}"
else
    echo -e "  Cloudflare:        ${YELLOW}VERIFICAR - systemctl status cloudflared${NC}"
fi

echo ""
echo -e "${GREEN}Sistemas prontos para uso:${NC}"
echo -e "  ${BOLD}https://$TIMEPULSE_DOMAIN${NC}"
echo -e "  ${BOLD}https://$OPTIROTA_DOMAIN${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Obrigado por usar TimePulse AI + OptiRota! Suporte: Luis - Santos/SP"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
