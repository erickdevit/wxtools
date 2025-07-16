#!/bin/bash

# --- Cores e Variáveis Globais ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # Sem Cor
ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yaml"

# --- Função para checar comandos essenciais ---
check_command() {
    command -v "$1" &>/dev/null || { echo -e "${RED}Comando '$1' não encontrado. Instale antes de continuar.${NC}"; exit 1; }
}

# Checa comandos essenciais no início do script
for cmd in docker docker-compose openssl htpasswd; do
    check_command "$cmd"
done

# --- Funções de Detecção e Instalação de Pacotes (Agnósticas de OS) ---
detect_os() {
    if [ -f /etc/os-release ]; then . /etc/os-release; OS=$NAME; ID_LIKE=${ID_LIKE:-$ID}; else echo -e "${RED}Não foi possível detectar o sistema operacional.${NC}"; exit 1; fi
    case "$ID_LIKE" in
        debian|ubuntu) PKG_MANAGER="apt-get"; UPDATE_CMD="apt-get update -y"; INSTALL_CMD="apt-get install -y"; DEPS_PACKAGES=("apache2-utils" "openssl" "ca-certificates" "curl" "gnupg"); ;;
        fedora|rhel|centos) if command -v dnf &>/dev/null; then PKG_MANAGER="dnf"; else PKG_MANAGER="yum"; fi; UPDATE_CMD="$PKG_MANAGER check-update"; INSTALL_CMD="$PKG_MANAGER install -y"; DEPS_PACKAGES=("httpd-tools" "openssl" "ca-certificates" "curl" "gnupg"); ;;
        arch) PKG_MANAGER="pacman"; UPDATE_CMD="pacman -Syu --noconfirm"; INSTALL_CMD="pacman -S --noconfirm"; DEPS_PACKAGES=("apache" "openssl" "ca-certificates" "curl" "gnupg"); ;;
        *) echo -e "${RED}Distribuição Linux não suportada: '$OS'.${NC}"; exit 1; ;;
    esac
}

install_packages() {
    echo -e "\n${BLUE}--- Verificando Dependências do Sistema... ---${NC}"
    NEEDS_INSTALL=()
    for pkg_name in "$@"; do
        case $pkg_name in
            apache2-utils) cmd="htpasswd";;
            openssl) cmd="openssl";;
            curl) cmd="curl";;
            *) cmd=$pkg_name;;
        esac
        if ! command -v $cmd &>/dev/null; then
            NEEDS_INSTALL+=($pkg_name)
        fi
    done
    if [ ${#NEEDS_INSTALL[@]} -gt 0 ]; then
        echo -e "${YELLOW}Instalando dependências: ${NEEDS_INSTALL[*]}${NC}"
        $UPDATE_CMD && $INSTALL_CMD "${NEEDS_INSTALL[@]}" || { echo -e "${RED}Falha ao instalar dependências!${NC}"; exit 1; }
    else
        echo -e "${GREEN}✅ Todas as dependências já estão satisfeitas.${NC}"
    fi
}

# --- Função de Setup Inicial (Cria apenas o .env) ---
initial_setup() {
    if [ -f "$ENV_FILE" ]; then
        read -p "Arquivo de configuração .env já existe. Deseja sobrescrever? (s/N): " resp
        [[ ! "$resp" =~ ^[sS]$ ]] && return
        cp "$ENV_FILE" "${ENV_FILE}.bak.$(date +%s)"
    fi
    echo -e "${BLUE}--- Realizando Setup Inicial (criação do .env) ---${NC}"
    
    # Criação do .env com senhas seguras e aleatórias
    cat <<EOT > "$ENV_FILE"
# === ARQUIVO DE AMBIENTE PRINCIPAL - WXTOOLS ===
# Gerado em: $(date)

# --- CREDENCIAIS DA INFRAESTRUTURA (Geradas Automaticamente) ---
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(openssl rand -hex 16)
REDIS_PASSWORD=$(openssl rand -hex 16)
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
EOT
    chmod 600 "$ENV_FILE"
    echo -e "${GREEN}Arquivo .env criado com sucesso!${NC}"
}

# --- Funções de criação dos arquivos compose de cada serviço ---
setup_redis_compose() {
    if [ -f "redis.yaml" ]; then return; fi
    cat <<EOT > redis.yaml
services:
  redis:
    image: redis:7-alpine
    container_name: redis_shared
    restart: always
    command: ["redis-server", "--requirepass", "${REDIS_PASSWORD}"]
    volumes:
      - redis_data:/data
    networks:
      - rede_publica
volumes:
  redis_data:
networks:
  rede_publica:
EOT
}

setup_postgres_compose() {
    if [ -f "postgres.yaml" ]; then return; fi
    cat <<EOT > postgres.yaml
services:
  postgres:
    image: ankane/pgvector:latest
    container_name: postgres_shared
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: main_db
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - rede_publica
volumes:
  postgres_data:
networks:
  rede_publica:
EOT
}

setup_minio_compose() {
    if [ -f "minio.yaml" ]; then return; fi
    cat <<EOT > minio.yaml
services:
  minio:
    image: minio/minio:latest
    container_name: minio_storage
    restart: always
    command: ["server", "/data", "--console-address", ":9001"]
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    volumes:
      - minio_data:/data
    networks:
      - rede_publica
volumes:
  minio_data:
networks:
  rede_publica:
EOT
}

setup_traefik_compose() {
    if [ -f "traefik.yaml" ]; then return; fi
    cat <<EOT > traefik.yaml
services:
  traefik:
    image: traefik:v2.10
    container_name: traefik
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - /opt/traefik/data:/etc/traefik
    networks:
      - rede_publica
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.traefik-dashboard.rule=Host(${TRAEFIK_DOMAIN})"
      - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
      - "traefik.http.routers.traefik-dashboard.tls.certresolver=letsencrypt"
      - "traefik.http.routers.traefik-dashboard.service=api@internal"
      - "traefik.http.routers.traefik-dashboard.middlewares=auth"
      - "traefik.http.middlewares.auth.basicauth.users=${TRAEFIK_AUTH_HASH}"
networks:
  rede_publica:
EOT
}

setup_portainer_compose() {
    if [ -f "portainer.yaml" ]; then return; fi
    cat <<EOT > portainer.yaml
services:
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - rede_publica
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(${PORTAINER_DOMAIN})"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
volumes:
  portainer_data:
networks:
  rede_publica:
EOT
}

setup_chatwoot_compose() {
    if [ -f "chatwoot.yaml" ]; then return; fi
    cat <<EOT > chatwoot.yaml
services:
  chatwoot-init:
    image: chatwoot/chatwoot:latest
    command: ["sh", "-c", "bundle exec rails db:chatwoot_prepare; bundle exec rails db:seed"]
    depends_on:
      - postgres
      - redis
    env_file: .env
    networks:
      - rede_publica
    restart: "no"
  chatwoot-app:
    image: chatwoot/chatwoot:latest
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
    restart: always
    depends_on:
      - chatwoot-init
    env_file: .env
    volumes:
      - chatwoot_storage:/app/storage
    networks:
      - rede_publica
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.chatwoot.rule=Host(${CHATWOOT_DOMAIN})"
      - "traefik.http.routers.chatwoot.entrypoints=websecure"
      - "traefik.http.routers.chatwoot.tls.certresolver=letsencrypt"
      - "traefik.http.services.chatwoot.loadbalancer.server.port=3000"
  chatwoot-sidekiq:
    image: chatwoot/chatwoot:latest
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
    restart: always
    depends_on:
      - chatwoot-init
    env_file: .env
    volumes:
      - chatwoot_storage:/app/storage
    networks:
      - rede_publica
volumes:
  chatwoot_storage:
networks:
  rede_publica:
EOT
}

setup_n8n_compose() {
    if [ -f "n8n.yaml" ]; then return; fi
    cat <<EOT > n8n.yaml
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: n8n
    restart: always
    environment:
      - N8N_HOST=${N8N_DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${N8N_DOMAIN}/
      - GENERIC_TIMEZONE=${N8N_TIMEZONE}
      - POSTGRES_DATABASE=${POSTGRES_DB_N8N}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_HOST=postgres_shared
      - POSTGRES_PORT=5432
      - DB_TYPE=postgres
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - rede_publica
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(${N8N_DOMAIN})"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
volumes:
  n8n_data:
networks:
  rede_publica:
EOT
}

# --- Funções para ativar/parar cada serviço, criando compose se necessário ---
activate_service_compose() {
    local svc="$1"
    local setup_func="setup_${svc}_compose"
    if [ ! -f "${svc}.yaml" ]; then
        $setup_func
    fi
    # Remove rede_publica se existir para evitar conflitos de labels
    if docker network ls | grep -q 'rede_publica'; then
        docker network rm rede_publica >/dev/null 2>&1
    fi
    docker-compose -f "${svc}.yaml" up -d || { echo -e "${RED}Falha ao iniciar o serviço ${svc}!${NC}"; docker-compose -f "${svc}.yaml" logs; return 1; }
    echo -e "${GREEN}✅ Serviço ${svc} ativado e iniciado!${NC}"
}

stop_service_compose() {
    local svc="$1"
    if [ ! -f "${svc}.yaml" ]; then
        echo -e "${YELLOW}O compose de ${svc} ainda não existe.${NC}"
        return
    fi
    docker-compose -f "${svc}.yaml" down
    echo -e "${GREEN}Serviço ${svc} parado.${NC}"
}

# --- Menu Principal ---
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}==================== WXTOOLS v1.0 ====================${NC}"
        echo "Suite de Gerenciamento de Infraestrutura e Aplicações"
        echo "------------------------------------------------------"
        echo -e "${YELLOW}Serviços de Infraestrutura:${NC}"
        echo "  [1] Instalar/Gerenciar Docker"
        echo "  [2] Instalar/Gerenciar Traefik (Proxy Reverso)"
        echo "  [3] Instalar/Gerenciar Portainer (Gestão de Contêineres)"
        echo "  [4] Instalar/Gerenciar PostgreSQL (Banco de Dados)"
        echo "  [5] Instalar/Gerenciar Redis (Cache/Broker)"
        echo "  [6] Instalar/Gerenciar MinIO (S3 Storage)"
        echo ""
        echo -e "${YELLOW}Aplicações:${NC}"
        echo "  [7] Instalar/Gerenciar Chatwoot"
        echo "  [8] Instalar/Gerenciar n8n"
        echo ""
        echo -e "${YELLOW}Utilitários:${NC}"
        echo "  [9] Ver Status de todos os serviços"
        echo -e "${RED}  [0] Sair${NC}"
        echo "------------------------------------------------------"
        read -p "Escolha uma opção: " choice

        case "$choice" in
            1) install_docker ;;
            2)
                echo -e "${YELLOW}1) Ativar Traefik\n2) Parar Traefik${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) activate_service_compose traefik ;;
                    2) stop_service_compose traefik ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            3)
                echo -e "${YELLOW}1) Ativar Portainer\n2) Parar Portainer${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) activate_service_compose portainer ;;
                    2) stop_service_compose portainer ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            4)
                echo -e "${YELLOW}1) Ativar PostgreSQL\n2) Parar PostgreSQL${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) activate_service_compose postgres ;;
                    2) stop_service_compose postgres ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            5)
                echo -e "${YELLOW}1) Ativar Redis\n2) Parar Redis${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) activate_service_compose redis ;;
                    2) stop_service_compose redis ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            6)
                echo -e "${YELLOW}1) Ativar MinIO\n2) Parar MinIO${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) activate_service_compose minio ;;
                    2) stop_service_compose minio ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            7)
                echo -e "${YELLOW}1) Ativar Chatwoot\n2) Parar Chatwoot${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) activate_service_compose chatwoot ;;
                    2) stop_service_compose chatwoot ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            8)
                echo -e "${YELLOW}1) Ativar n8n\n2) Parar n8n${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) activate_service_compose n8n ;;
                    2) stop_service_compose n8n ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            9)
                echo -e "${BLUE}--- Status Atual dos Serviços ---${NC}"
                for svc in traefik portainer postgres redis minio chatwoot n8n; do
                    echo -e "\n${YELLOW}Status de $svc:${NC}"
                    docker-compose -f "$svc.yaml" ps
                done
                ;;
            0|q|Q) exit 0 ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
        read -p "Pressione [Enter] para voltar ao menu..."
    done
}

# --- Ponto de Entrada do Script ---
# 1. Verifica se é root
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}Este script precisa de privilégios de root. Use: sudo ./wxtools.sh${NC}" 1>&2
   exit 1
fi
# 2. Detecta o OS
detect_os
# 3. Instala dependências do host
install_packages "${DEPS_PACKAGES[@]}"
# 4. Cria os arquivos de template se não existirem
initial_setup
# 5. Mostra o menu principal
main_menu