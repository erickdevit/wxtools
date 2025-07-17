#!/bin/bash

# --- Cores e Variáveis Globais ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # Sem Cor
ENV_FILE=".env"
COMPOSE_DIR="compose"
SERVICES=("traefik" "portainer" "postgres" "redis" "minio" "chatwoot" "n8n")
declare -A SERVICE_DEPENDENCIES=(
    ["chatwoot"]="postgres redis"
    ["n8n"]="postgres"
)

# --- Funções de Utilidade ---
error_exit() {
    echo -e "${RED}ERRO: $1${NC}" >&2
    exit 1
}

# --- Função para checar comandos essenciais ---
check_command() {
    command -v "$1" &>/dev/null || error_exit "Comando '$1' não encontrado. Instale antes de continuar."
}

# Checa comandos essenciais no início do script
for cmd in docker docker-compose openssl htpasswd; do
    check_command "$cmd"
done

# --- Funções de Detecção e Instalação de Pacotes (Agnósticas de OS) ---
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        ID_LIKE=${ID_LIKE:-$ID}
    else
        error_exit "Não foi possível detectar o sistema operacional."
    fi
    case "$ID_LIKE" in
        debian|ubuntu) PKG_MANAGER="apt-get"; UPDATE_CMD="apt-get update -y"; INSTALL_CMD="apt-get install -y"; DEPS_PACKAGES=("apache2-utils" "openssl" "ca-certificates" "curl" "gnupg"); ;;
        fedora|rhel|centos) if command -v dnf &>/dev/null; then PKG_MANAGER="dnf"; else PKG_MANAGER="yum"; fi; UPDATE_CMD="$PKG_MANAGER check-update"; INSTALL_CMD="$PKG_MANAGER install -y"; DEPS_PACKAGES=("httpd-tools" "openssl" "ca-certificates" "curl" "gnupg"); ;;
        arch) PKG_MANAGER="pacman"; UPDATE_CMD="pacman -Syu --noconfirm"; INSTALL_CMD="pacman -S --noconfirm"; DEPS_PACKAGES=("apache" "openssl" "ca-certificates" "curl" "gnupg"); ;;
        *) error_exit "Distribuição Linux não suportada: '$OS'." ;;
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
        sudo $UPDATE_CMD && sudo $INSTALL_CMD "${NEEDS_INSTALL[@]}" || error_exit "Falha ao instalar dependências!"
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
    if [ -f "compose/redis.yaml" ]; then return; fi
    cat <<EOT > compose/redis.yaml
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
    if [ -f "compose/postgres.yaml" ]; then return; fi
    cat <<EOT > compose/postgres.yaml
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
    if [ -f "compose/minio.yaml" ]; then return; fi
    cat <<EOT > compose/minio.yaml
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
    if [ -f "compose/traefik.yaml" ]; then return; fi
    cat <<EOT > compose/traefik.yaml
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
    if [ -f "compose/portainer.yaml" ]; then return; fi
    cat <<EOT > compose/portainer.yaml
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
    if [ -f "compose/chatwoot.yaml" ]; then return; fi
    cat <<EOT > compose/chatwoot.yaml
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
    if [ -f "compose/n8n.yaml" ]; then return; fi
    cat <<EOT > compose/n8n.yaml
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
start_service() {
    local svc="$1"

    # Inicia as dependências primeiro
    if [ -n "${SERVICE_DEPENDENCIES[$svc]}" ]; then
        for dep in ${SERVICE_DEPENDENCIES[$svc]}; do
            echo -e "${BLUE}Iniciando dependência '$dep' para '$svc'...${NC}"
            start_service "$dep"
        done
    fi

    local setup_func="setup_${svc}_compose"
    local compose_file="$COMPOSE_DIR/$svc.yaml"

    if [ ! -f "$compose_file" ]; then
        $setup_func
    fi

    # Verifica se o serviço já está rodando
    if sudo docker-compose -f "$compose_file" ps | grep -q "Up"; then
        echo -e "${GREEN}✅ Serviço ${svc} já está em execução.${NC}"
        return
    fi

    echo -e "${BLUE}Iniciando o serviço ${svc}...${NC}"
    sudo docker-compose -f "$compose_file" up -d || {
        sudo docker-compose -f "$compose_file" logs
        error_exit "Falha ao iniciar o serviço ${svc}!"
    }
    echo -e "${GREEN}✅ Serviço ${svc} ativado e iniciado!${NC}"
}

stop_service() {
    local svc="$1"
    local compose_file="compose/${svc}.yaml"
    if [ ! -f "$compose_file" ]; then
        echo -e "${YELLOW}O compose de ${svc} ainda não existe.${NC}"
        return
    fi
    sudo docker-compose -f "$compose_file" down
    echo -e "${GREEN}Serviço ${svc} parado.${NC}"
}

show_status() {
    echo -e "${BLUE}--- Status Atual dos Serviços ---${NC}"
    for svc in "${SERVICES[@]}"; do
        echo -e "\n${YELLOW}Status de $svc:${NC}"
        local compose_file="$COMPOSE_DIR/$svc.yaml"
        if [ -f "$compose_file" ]; then
            sudo docker-compose -f "$compose_file" ps
        else
            echo "Serviço não configurado."
        fi
    done
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
                    1) start_service traefik ;;
                    2) stop_service traefik ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            3)
                echo -e "${YELLOW}1) Ativar Portainer\n2) Parar Portainer${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) start_service portainer ;;
                    2) stop_service portainer ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            4)
                echo -e "${YELLOW}1) Ativar PostgreSQL\n2) Parar PostgreSQL${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) start_service postgres ;;
                    2) stop_service postgres ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            5)
                echo -e "${YELLOW}1) Ativar Redis\n2) Parar Redis${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) start_service redis ;;
                    2) stop_service redis ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            6)
                echo -e "${YELLOW}1) Ativar MinIO\n2) Parar MinIO${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) start_service minio ;;
                    2) stop_service minio ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            7)
                echo -e "${YELLOW}1) Ativar Chatwoot\n2) Parar Chatwoot${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) start_service chatwoot ;;
                    2) stop_service chatwoot ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            8)
                echo -e "${YELLOW}1) Ativar n8n\n2) Parar n8n${NC}"
                read -p "Escolha: " opt
                case "$opt" in
                    1) start_service n8n ;;
                    2) stop_service n8n ;;
                    *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
                esac
                ;;
            9)
                show_status
                ;;
            0|q|Q) exit 0 ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
        read -p "Pressione [Enter] para voltar ao menu..."
    done
}

# --- Ponto de Entrada do Script ---
# 1. Detecta o OS
detect_os
# 2. Instala dependências do host
install_packages "${DEPS_PACKAGES[@]}"
# 3. Cria os arquivos de template se não existirem
initial_setup
# 4. Mostra o menu principal
main_menu