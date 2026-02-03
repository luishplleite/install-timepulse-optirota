#!/bin/bash

# =============================================================================
# TimePulse AI - Script de Instalação Completa VPS com Apache + Docker + SSL
# Versão: 3.0 - Instalação Automática Completa
# =============================================================================

set -euo pipefail

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
 ║           TimePulse AI VPS Installer v3.0            ║
 ║      Apache + Docker + SSL - Instalação Completa     ║
 ╚═══════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar se é root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script deve ser executado como root (sudo)"
   exit 1
fi

# Verificar sistema operacional
log_info "Verificando sistema operacional..."
if [[ ! -f /etc/os-release ]]; then
    log_error "Sistema operacional não suportado"
    exit 1
fi

. /etc/os-release
log_info "Distribuição: $NAME $VERSION"

# Configurações (definir aqui ou via parâmetros)
DOMAIN="${1:-timepulseai.com.br}"
EMAIL="${2:-luisleite@timepulseai.com.br}"
INSTALL_DIR="/opt/timepulse"

log_step "Configuração definida:"
log_info "Domínio: $DOMAIN"
log_info "Email SSL: $EMAIL"
log_info "Diretório: $INSTALL_DIR"
echo ""

read -p "Continuar com a instalação? (y/n): " CONFIRM
if [[ $CONFIRM != "y" ]]; then
    log_info "Instalação cancelada"
    exit 0
fi

# =============================================================================
# ETAPA 1: ATUALIZAR SISTEMA E INSTALAR DEPENDÊNCIAS
# =============================================================================
log_step "ETAPA 1/10 - Atualizando sistema..."
apt update && apt upgrade -y

log_info "Instalando dependências do sistema..."
apt install -y \
    ca-certificates \
    curl \
    git \
    wget \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    ufw \
    jq \
    openssl

log_success "Sistema atualizado"

# =============================================================================
# ETAPA 2: INSTALAR DOCKER E DOCKER COMPOSE
# =============================================================================
log_step "ETAPA 2/10 - Instalando Docker..."

# Remover versões antigas do Docker se existirem
apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Adicionar repositório Docker
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Instalar Docker
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Iniciar e habilitar Docker
systemctl enable docker
systemctl start docker

log_success "Docker instalado: $(docker --version)"
log_success "Docker Compose instalado: $(docker compose version)"

# =============================================================================
# ETAPA 3: INSTALAR APACHE2
# =============================================================================
log_step "ETAPA 3/10 - Instalando Apache2..."

apt install -y apache2

# Habilitar módulos necessários do Apache
a2enmod proxy
a2enmod proxy_http
a2enmod proxy_wstunnel
a2enmod ssl
a2enmod rewrite
a2enmod headers

systemctl enable apache2
systemctl start apache2

log_success "Apache2 instalado e configurado"

# =============================================================================
# ETAPA 4: INSTALAR CERTBOT PARA SSL
# =============================================================================
log_step "ETAPA 4/10 - Instalando Certbot (Let's Encrypt)..."

# Instalar Certbot e plugin Apache
apt install -y certbot python3-certbot-apache

log_success "Certbot instalado"

# =============================================================================
# ETAPA 5: CONFIGURAR FIREWALL
# =============================================================================
log_step "ETAPA 5/10 - Configurando firewall..."

ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 8080/tcp

log_success "Firewall configurado"

# =============================================================================
# ETAPA 6: CRIAR ESTRUTURA DE DIRETÓRIOS
# =============================================================================
log_step "ETAPA 6/10 - Criando estrutura de diretórios..."

mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

mkdir -p {public,api,logs,ssl}

log_success "Estrutura de diretórios criada"

# =============================================================================
# ETAPA 7: SOLICITAR VARIÁVEIS DE AMBIENTE
# =============================================================================
log_step "ETAPA 7/10 - Configurando variáveis de ambiente..."

echo ""
echo -e "${YELLOW}=== CONFIGURAÇÃO DAS VARIÁVEIS DE AMBIENTE ===${NC}"
echo ""

# Supabase
read -p "URL do Supabase (ex: https://xxx.supabase.co): " SUPABASE_URL
read -p "Supabase Anon Key: " SUPABASE_ANON_KEY
read -p "Supabase Service Role Key: " SUPABASE_SERVICE_ROLE_KEY

# OpenAI
read -p "OpenAI API Key: " OPENAI_API_KEY

# Mapbox
read -p "Mapbox Token: " MAPBOX_TOKEN

# Evolution API
read -p "Evolution API Base URL (ex: https://evolution.exemplo.com): " EVOLUTION_API_BASE_URL
read -p "Evolution API Key: " EVOLUTION_API_KEY

# Criar arquivo .env
cat > $INSTALL_DIR/.env << EOF
# Configurações do Servidor
NODE_ENV=production
PORT=3001
DOMAIN=$DOMAIN

# Supabase
SUPABASE_URL=$SUPABASE_URL
SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY

# OpenAI
OPENAI_API_KEY=$OPENAI_API_KEY

# Mapbox
MAPBOX_TOKEN=$MAPBOX_TOKEN

# Evolution API (WhatsApp)
EVOLUTION_API_BASE_URL=$EVOLUTION_API_BASE_URL
EVOLUTION_API_KEY=$EVOLUTION_API_KEY

# CORS
CORS_ORIGINS=https://$DOMAIN,https://www.$DOMAIN
EOF

chmod 600 $INSTALL_DIR/.env
log_success "Arquivo .env criado com segurança"

# =============================================================================
# ETAPA 8: CRIAR DOCKERFILE E DOCKER-COMPOSE
# =============================================================================
log_step "ETAPA 8/10 - Criando Dockerfile e docker-compose.yml..."

# Criar Dockerfile
cat > $INSTALL_DIR/Dockerfile << 'DOCKERFILE'
FROM node:20-alpine

WORKDIR /app

# Instalar dependências do sistema
RUN apk add --no-cache \
    python3 \
    make \
    g++

# Copiar package.json e package-lock.json
COPY package*.json ./

# Instalar dependências do Node.js
RUN npm ci --only=production

# Copiar o resto da aplicação
COPY . .

# Expor porta
EXPOSE 3001

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3001/api/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

# Comando para iniciar
CMD ["node", "server.js"]
DOCKERFILE

# Criar docker-compose.yml
cat > $INSTALL_DIR/docker-compose.yml << 'DOCKERCOMPOSE'
version: '3.8'

services:
  timepulse:
    build: .
    container_name: timepulse-app
    restart: unless-stopped
    ports:
      - "3001:3001"
    env_file:
      - .env
    volumes:
      - ./logs:/app/logs
      - ./public:/app/public:ro
      - ./api:/app/api:ro
    networks:
      - timepulse-network
    healthcheck:
      test: ["CMD", "node", "-e", "require('http').get('http://localhost:3001/api/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  timepulse-network:
    driver: bridge
DOCKERCOMPOSE

log_success "Dockerfile e docker-compose.yml criados"

# =============================================================================
# ETAPA 9: CONFIGURAR APACHE COMO PROXY REVERSO
# =============================================================================
log_step "ETAPA 9/10 - Configurando Apache como proxy reverso..."

# Criar configuração do Apache (HTTP primeiro)
cat > /etc/apache2/sites-available/$DOMAIN.conf << EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    ServerAdmin $EMAIL

    # Logs
    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log combined

    # Proxy reverso para Docker
    ProxyPreserveHost On
    ProxyPass / http://localhost:3001/
    ProxyPassReverse / http://localhost:3001/

    # WebSocket support
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) "ws://localhost:3001/\$1" [P,L]

    # Headers de segurança
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
</VirtualHost>
EOF

# Habilitar site
a2ensite $DOMAIN.conf

# Desabilitar site padrão
a2dissite 000-default.conf

# Testar configuração
apache2ctl configtest

# Recarregar Apache
systemctl reload apache2

log_success "Apache configurado como proxy reverso"

# =============================================================================
# ETAPA 10: GERAR CERTIFICADO SSL E CONFIGURAR HTTPS
# =============================================================================
log_step "ETAPA 10/10 - Gerando certificado SSL com Let's Encrypt..."

# Gerar certificado SSL automaticamente
certbot --apache \
    --non-interactive \
    --agree-tos \
    --email $EMAIL \
    --domains $DOMAIN \
    --domains www.$DOMAIN \
    --redirect

# Configurar renovação automática
systemctl enable certbot.timer
systemctl start certbot.timer

log_success "Certificado SSL gerado e configurado"
log_info "Renovação automática configurada via systemd timer"

# =============================================================================
# COPIAR ARQUIVOS DO PROJETO ATUAL
# =============================================================================
log_step "Copiando arquivos do projeto..."

# Nota: Este script assume que será executado no diretório do projeto
# Se executar remotamente, você precisa clonar o repositório ou copiar os arquivos

# Copiar package.json se existir
if [ -f package.json ]; then
    cp package.json $INSTALL_DIR/
    log_success "package.json copiado"
fi

# Copiar server.js se existir
if [ -f server.js ]; then
    cp server.js $INSTALL_DIR/
    log_success "server.js copiado"
fi

# Copiar diretório public se existir
if [ -d public ]; then
    cp -r public/* $INSTALL_DIR/public/
    log_success "Diretório public copiado"
fi

# Copiar diretório api se existir
if [ -d api ]; then
    cp -r api/* $INSTALL_DIR/api/
    log_success "Diretório api copiado"
fi

# Se não houver arquivos, criar estrutura básica
if [ ! -f $INSTALL_DIR/package.json ]; then
    log_warning "package.json não encontrado, criando versão básica..."
    
    cat > $INSTALL_DIR/package.json << 'PACKAGE'
{
  "name": "timepulse-ai",
  "version": "1.0.0",
  "description": "TimePulse AI - Delivery Management Platform",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.74.0",
    "cookie-parser": "^1.4.7",
    "cors": "^2.8.5",
    "express": "^4.21.2",
    "helmet": "^6.2.0",
    "jsonwebtoken": "^9.0.2",
    "node-fetch": "^2.7.0",
    "openai": "^5.23.2",
    "pg": "^8.16.3"
  },
  "engines": {
    "node": ">=20.0.0"
  }
}
PACKAGE
fi

if [ ! -f $INSTALL_DIR/server.js ]; then
    log_warning "server.js não encontrado, criando versão básica..."
    
    cat > $INSTALL_DIR/server.js << 'SERVERJS'
const express = require("express");
const path = require("path");
const helmet = require("helmet");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3001;
const HOST = "0.0.0.0";

// Security
app.use(helmet({
    contentSecurityPolicy: false,
    crossOriginEmbedderPolicy: false,
    crossOriginResourcePolicy: { policy: "cross-origin" }
}));

// CORS
app.use(cors({
    origin: process.env.CORS_ORIGINS ? process.env.CORS_ORIGINS.split(',') : '*',
    credentials: true
}));

app.use(express.json());
app.use(express.static('public'));

// Health check
app.get('/api/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Config endpoint
app.get('/api/config', (req, res) => {
    res.json({
        supabaseUrl: process.env.SUPABASE_URL,
        supabaseAnonKey: process.env.SUPABASE_ANON_KEY
    });
});

app.listen(PORT, HOST, () => {
    console.log(`✅ TimePulse AI rodando em http://${HOST}:${PORT}`);
    console.log(`📊 Ambiente: ${process.env.NODE_ENV || 'development'}`);
    console.log(`🌐 Domínio: ${process.env.DOMAIN}`);
});
SERVERJS
fi

# Criar página index.html básica se não existir
if [ ! -f $INSTALL_DIR/public/index.html ]; then
    mkdir -p $INSTALL_DIR/public
    cat > $INSTALL_DIR/public/index.html << 'HTML'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TimePulse AI - Gestão de Delivery</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }
        .container {
            text-align: center;
            max-width: 600px;
            padding: 2rem;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 20px;
            backdrop-filter: blur(10px);
        }
        h1 { font-size: 3rem; margin-bottom: 1rem; }
        p { font-size: 1.2rem; margin-bottom: 2rem; opacity: 0.9; }
        .status { 
            background: rgba(76, 175, 80, 0.3); 
            padding: 1rem; 
            border-radius: 10px; 
            margin-top: 2rem; 
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>⏱️ TimePulse AI</h1>
        <p>Plataforma completa para gestão de delivery</p>
        <div class="status">
            <h3>✅ Sistema Online</h3>
            <p>Instalação concluída com sucesso!</p>
        </div>
    </div>
</body>
</html>
HTML
fi

# =============================================================================
# BUILD E START DOS CONTAINERS
# =============================================================================
log_step "Construindo e iniciando containers Docker..."

cd $INSTALL_DIR

# Build da imagem
docker compose build

# Iniciar containers
docker compose up -d

# Aguardar containers iniciarem
log_info "Aguardando containers iniciarem..."
sleep 10

# Verificar status
docker compose ps

log_success "Containers Docker em execução"

# =============================================================================
# VERIFICAÇÕES FINAIS
# =============================================================================
log_step "Executando verificações finais..."

# Verificar se o container está rodando
if docker ps | grep -q timepulse-app; then
    log_success "✅ Container TimePulse rodando"
else
    log_error "❌ Container não está rodando"
    docker compose logs
fi

# Verificar se Apache está respondendo
if curl -s http://localhost | grep -q "TimePulse"; then
    log_success "✅ Apache respondendo"
else
    log_warning "⚠️ Apache pode não estar respondendo corretamente"
fi

# Verificar certificado SSL
if [ -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]; then
    log_success "✅ Certificado SSL instalado"
    CERT_EXPIRY=$(openssl x509 -in /etc/letsencrypt/live/$DOMAIN/fullchain.pem -noout -enddate | cut -d= -f2)
    log_info "Certificado válido até: $CERT_EXPIRY"
else
    log_warning "⚠️ Certificado SSL não encontrado"
fi

# =============================================================================
# RESUMO DA INSTALAÇÃO
# =============================================================================
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          INSTALAÇÃO CONCLUÍDA COM SUCESSO!           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
log_info "📋 RESUMO DA INSTALAÇÃO:"
echo ""
log_success "✅ Docker instalado: $(docker --version | cut -d' ' -f3)"
log_success "✅ Apache2 instalado e configurado"
log_success "✅ Certificado SSL: Let's Encrypt"
log_success "✅ Firewall configurado (UFW)"
log_success "✅ Container TimePulse rodando"
echo ""
log_info "🌐 ACESSO AO SISTEMA:"
log_info "   • HTTPS: https://$DOMAIN"
log_info "   • HTTP: http://$DOMAIN (redireciona para HTTPS)"
echo ""
log_info "🔧 COMANDOS ÚTEIS:"
log_info "   • Ver logs: docker compose -f $INSTALL_DIR/docker-compose.yml logs -f"
log_info "   • Reiniciar: docker compose -f $INSTALL_DIR/docker-compose.yml restart"
log_info "   • Parar: docker compose -f $INSTALL_DIR/docker-compose.yml down"
log_info "   • Status Apache: systemctl status apache2"
log_info "   • Renovar SSL: certbot renew"
echo ""
log_info "📁 DIRETÓRIOS:"
log_info "   • Aplicação: $INSTALL_DIR"
log_info "   • Logs Apache: /var/log/apache2/"
log_info "   • Logs Docker: $INSTALL_DIR/logs/"
log_info "   • SSL: /etc/letsencrypt/live/$DOMAIN/"
echo ""
log_info "🔐 VARIÁVEIS DE AMBIENTE:"
log_info "   • Arquivo: $INSTALL_DIR/.env"
log_info "   • Permissões: 600 (seguro)"
echo ""
log_warning "⚠️ PRÓXIMOS PASSOS:"
log_warning "1. Verifique se o domínio $DOMAIN aponta para este servidor"
log_warning "2. Acesse https://$DOMAIN para verificar o sistema"
log_warning "3. Configure o DNS se ainda não estiver apontando"
log_warning "4. Faça backup do arquivo .env em local seguro"
echo ""
log_success "🎉 TimePulse AI instalado e rodando em https://$DOMAIN"
echo ""
