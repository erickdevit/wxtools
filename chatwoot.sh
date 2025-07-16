#!/bin/bash

# --- Cores para uma melhor visualização ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # Sem Cor

ENV_FILE=".env"
COMPOSE_FILE="docker-compose.yaml"

# --- Passo 1: Verificar se os arquivos já existem ---
if [ -f "$ENV_FILE" ] || [ -f "$COMPOSE_FILE" ]; then
  echo -e "${YELLOW}⚠️  Arquivos de configuração (.env ou docker-compose.yaml) já existem.${NC}"
  echo "Para proteger sua instalação, o script será encerrado. Se deseja reinstalar, apague estes arquivos primeiro."
  exit 0
fi

# --- Passo 2: Criar o arquivo docker-compose.yaml ---
echo -e "${BLUE}🔧 Criando o arquivo de estrutura 'docker-compose.yaml'...${NC}"
cat <<EOT > $COMPOSE_FILE
# Arquivo gerado automaticamente pelo script de setup
version: '3.8'
services:
  postgres:
    # CORREÇÃO: Usando a imagem com a extensão pg_vector incluída
    image: ankane/pgvector:latest
    restart: always
    volumes:
      - pg_data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: \${POSTGRES_DATABASE}
      POSTGRES_USER: \${POSTGRES_USERNAME}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    networks:
      - chatwoot_network
  redis:
    image: redis:7-alpine
    restart: always
    volumes:
      - redis_data:/data
    networks:
      - chatwoot_network
  chatwoot_init:
    image: erickwornex/chatwoot_custom:latest
    command: sh -c "bundle exec rails db:chatwoot_prepare; bundle exec rails db:seed"
    depends_on:
      - postgres
      - redis
    env_file: .env
    networks:
      - chatwoot_network
    restart: "no"
  app:
    image: erickwornex/chatwoot_custom:latest
    command: bundle exec rails s -p 3000 -b 0.0.0.0
    restart: always
    depends_on:
      - chatwoot_init
    ports:
      - "3000:3000"
    env_file: .env
    volumes:
      - chatwoot_data:/app/storage
    networks:
      - chatwoot_network
  sidekiq:
    image: erickwornex/chatwoot_custom:latest
    command: bundle exec sidekiq -C config/sidekiq.yml
    restart: always
    depends_on:
      - chatwoot_init
    env_file: .env
    volumes:
      - chatwoot_data:/app/storage
    networks:
      - chatwoot_network
volumes:
  pg_data:
  redis_data:
  chatwoot_data:
networks:
  chatwoot_network:
    driver: bridge
EOT
echo -e "${GREEN}✅ Arquivo 'docker-compose.yaml' criado com a imagem correta do PostgreSQL.${NC}"

# --- Início do Questionário Interativo ---
clear
echo -e "${GREEN}🚀 Bem-vindo ao Instalador 'Tudo em Um' do Chatwoot!${NC}"
echo "Este script irá configurar e iniciar sua aplicação."
echo "------------------------------------------------------------------"

# --- Coletando Dados da Imagem Docker ---
echo -e "\n${BLUE}--- Parte 0: Imagem Docker ---${NC}"
DEFAULT_IMAGE_NAME="erickwornex/chatwoot_custom:latest"
read -p "Qual o nome da sua imagem Docker? (Padrão: ${DEFAULT_IMAGE_NAME}): " CUSTOM_IMAGE_NAME
if [ -z "$CUSTOM_IMAGE_NAME" ]; then
    CUSTOM_IMAGE_NAME="$DEFAULT_IMAGE_NAME"
    echo -e "${YELLOW}Usando a imagem padrão: ${CUSTOM_IMAGE_NAME}${NC}"
fi

# --- Atualiza a imagem no docker-compose.yaml ---
# O sed no macOS requer um argumento extra para o -i. Esta sintaxe é mais portável.
sed -i.bak "s|image: erickwornex/chatwoot_custom:latest|image: ${CUSTOM_IMAGE_NAME}|g" "$COMPOSE_FILE" && rm "${COMPOSE_FILE}.bak"

# --- Coletando Dados Gerais ---
echo -e "\n${BLUE}--- Parte 1: Configuração Geral do Servidor ---${NC}"
read -p "Qual o seu domínio ou IP público? (Deixe em branco para usar 'localhost'): " CHATWOOT_DOMAIN
if [ -z "$CHATWOOT_DOMAIN" ]; then
    CHATWOOT_DOMAIN="localhost"
    echo -e "${YELLOW}Usando 'localhost' como endereço de acesso.${NC}"
fi
read -p "Você usará HTTPS (SSL) para acessar o Chatwoot? (s/n): " WANTS_SSL
if [[ "$WANTS_SSL" =~ ^[Ss]$ ]]; then
  FRONTEND_URL="https://""$CHATWOOT_DOMAIN"
  FORCE_SSL="true"
else
  FRONTEND_URL="http://""$CHATWOOT_DOMAIN"":3000"
  FORCE_SSL="false"
fi

# --- Passo 3: Geração da Chave e Criação do Arquivo .env ---
echo -e "\n${BLUE}--- Parte 2: Finalizando a Configuração ---${NC}"
echo -e "${YELLOW}🔑 Gerando chave de segurança (SECRET_KEY_BASE) usando a imagem ${CUSTOM_IMAGE_NAME}...${NC}"
SECRET_KEY=$(docker run --rm ${CUSTOM_IMAGE_NAME} bundle exec rails secret)

if [ -z "$SECRET_KEY" ]; then
    echo -e "${RED}❌ Erro: Falha ao gerar a SECRET_KEY_BASE. Verifique se o Docker está em execução e se o nome da imagem '${CUSTOM_IMAGE_NAME}' está correto.${NC}"
    exit 1
fi

echo "📝 Criando o arquivo .env final com suas configurações..."

# Cria o arquivo .env com a base da configuração
cat <<EOT > $ENV_FILE
# Arquivo de ambiente gerado automaticamente pelo script de setup
# Data da Geração: $(date)

# --- Configuração Geral ---
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker
SECRET_KEY_BASE=${SECRET_KEY}
FRONTEND_URL=${FRONTEND_URL}
FORCE_SSL=${FORCE_SSL}
ENABLE_ACCOUNT_SIGNUP=true
DEFAULT_LOCALE=pt_BR
DISABLE_VERSION_CHECK=true

# --- Conexões Internas (Padrão) ---
POSTGRES_HOST=postgres
POSTGRES_DATABASE=chatwoot
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=postgres_password
REDIS_URL=redis://redis:6379
EOT

# --- Coletando Dados de E-mail (SMTP) ---
echo -e "\n${BLUE}--- Parte 3: Configuração de E-mail (Opcional) ---${NC}"
read -p "Deseja configurar o envio de e-mails (SMTP) agora? (s/n): " WANTS_SMTP

if [[ "$WANTS_SMTP" =~ ^[Ss]$ ]]; then
    echo "Ok, vamos configurar o SMTP."
    read -p "Nome do Remetente (ex: Atendimento Acme Corp): " SMTP_FROM_NAME
    read -p "E-mail do Remetente (ex: contato@acme.com): " SMTP_FROM_EMAIL
    read -p "Servidor SMTP (ex: smtp.gmail.com): " SMTP_ADDRESS
    read -p "Porta SMTP (padrão: 587): " SMTP_PORT
    [ -z "$SMTP_PORT" ] && SMTP_PORT=587
    read -p "Usuário SMTP (geralmente o mesmo e-mail do remetente): " SMTP_USERNAME
    read -sp "Senha SMTP (não será visível na tela): " SMTP_PASSWORD
    echo
    read -p "Domínio SMTP (ex: gmail.com): " SMTP_DOMAIN

    # Anexa a configuração SMTP ao arquivo .env
    cat <<EOT >> $ENV_FILE

# --- Configuração de E-mail (SMTP) ---
MAILER_SENDER_EMAIL='${SMTP_FROM_NAME} <${SMTP_FROM_EMAIL}>'
SMTP_ADDRESS=${SMTP_ADDRESS}
SMTP_PORT=${SMTP_PORT}
SMTP_USERNAME=${SMTP_USERNAME}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_DOMAIN=${SMTP_DOMAIN}
SMTP_AUTHENTICATION=login
SMTP_ENABLE_STARTTLS_AUTO=true
EOT
else
    echo -e "${YELLOW}Ok, pulando a configuração de SMTP. Os e-mails não funcionarão até que você configure as variáveis no arquivo .env manualmente.${NC}"
    # Anexa as variáveis SMTP comentadas para referência futura
    cat <<EOT >> $ENV_FILE

# --- Configuração de E-mail (SMTP) - PENDENTE ---
# Para habilitar o envio de e-mails, descomente e preencha as linhas abaixo.
# MAILER_SENDER_EMAIL='Chatwoot <contato@seudominio.com>'
# SMTP_ADDRESS=smtp.seudominio.com
# SMTP_PORT=587
# SMTP_USERNAME=seu_usuario_smtp
# SMTP_PASSWORD=sua_senha_smtp
# SMTP_DOMAIN=seudominio.com
# SMTP_AUTHENTICATION=login
# SMTP_ENABLE_STARTTLS_AUTO=true
EOT
fi

# --- Passo 4: Iniciar a Aplicação Automaticamente ---
echo "------------------------------------------------------------------"
echo -e "${GREEN}✅ Configuração salva com sucesso!${NC}"
echo -e "${YELLOW}🚀 Iniciando os serviços do Chatwoot automaticamente...${NC}"
echo "Isso pode levar vários minutos na primeira vez, pois o Docker precisa baixar as imagens. Por favor, aguarde."
echo ""

docker-compose up -d

echo "------------------------------------------------------------------"
echo -e "${GREEN}🎉 Chatwoot em execução!${NC}"
echo ""
echo "O processo foi concluído. Os serviços estão iniciando em segundo plano."
echo "Aguarde cerca de 1-2 minutos para que a aplicação esteja totalmente pronta para uso."
echo ""
echo "Você já pode acessar sua instância do Chatwoot em:"
echo -e "${GREEN}   ${FRONTEND_URL}${NC}"
echo ""