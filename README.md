# WXTOOLS - Instalador Modular de Infraestrutura e Aplicações

Este projeto tem como objetivo facilitar a instalação e configuração de serviços e aplicações Docker de forma **modular** e interativa. Cada serviço possui seu próprio arquivo compose, criado sob demanda, tornando o gerenciamento mais limpo, flexível e escalável.

## O que é WXTOOLS?
WXTOOLS é uma suíte de automação para infraestrutura Docker, que permite instalar, ativar, parar e gerenciar serviços como Redis, PostgreSQL, MinIO, Traefik, Portainer, Chatwoot, n8n e outros, tudo via menu interativo.

## Como funciona a modularidade?
- **Cada serviço/aplicação tem seu próprio arquivo compose** (ex: `redis.yaml`, `postgres.yaml`, etc).
- **Os arquivos só são criados quando o serviço é ativado pela primeira vez** pelo menu.
- O arquivo `.env` é criado no setup inicial e compartilhado entre todos os serviços.
- Não existe mais um `docker-compose.yaml` único.
- O status, ativação e parada são feitos individualmente para cada serviço.

## Requisitos
- Docker e Docker Compose instalados (Linux, macOS, WSL ou ambiente compatível)
- Bash (Linux, macOS ou WSL no Windows)

## Como usar
1. Clone este repositório:
   ```bash
   git clone <url-do-repositorio>
   cd Projetos
   ```
2. Dê permissão de execução ao script:
   ```bash
   chmod +x wxtools.sh
   ```
3. Execute o instalador:
   ```bash
   ./wxtools.sh
   ```
   O script solicitará a senha de superusuário (sudo) apenas quando for necessário para instalar pacotes ou gerenciar o Docker.
4. Siga o menu interativo para ativar/parar serviços conforme sua necessidade.
   - Ao ativar um serviço pela primeira vez, o compose correspondente será criado automaticamente no diretório `compose/`.
   - O arquivo `.env` será criado no primeiro uso.

## O que o script faz?
- **Gerenciamento de Dependências:** Instala automaticamente as dependências do sistema (como `htpasswd`, `openssl`, etc.) e gerencia as dependências entre os serviços (por exemplo, inicia o PostgreSQL e o Redis antes de iniciar o Chatwoot).
- **Criação de Arquivos de Configuração:** Cria um arquivo `.env` com variáveis e senhas seguras e gera arquivos compose separados para cada serviço/aplicação no diretório `compose/`.
- **Gerenciamento de Serviços:** Permite ativar/parar cada serviço individualmente pelo menu e exibe o status de todos os serviços de forma modular.
- **Flexibilidade:** Facilita a expansão para adicionar novos serviços.
- **Segurança:** Não requer a execução do script inteiro como root e não sobrescreve arquivos `.env` ou compose já existentes sem confirmação.

## Serviços e Imagens
- **Chatwoot:** Utiliza a imagem customizada `erickwornex/chatwoot_custom`.

## Exemplo de fluxo
- Ativar Redis: cria `redis.yaml` (se não existir) e sobe o serviço.
- Ativar PostgreSQL: cria `postgres.yaml` (se não existir) e sobe o serviço.
- Parar Redis: derruba apenas o container Redis.
- Ver status: mostra o status de cada serviço individualmente.

## Segurança
- O script não sobrescreve arquivos `.env` ou compose já existentes sem confirmação.
- Senhas e variáveis sensíveis são geradas automaticamente.

## Personalização
- Para adicionar novos serviços, siga o padrão das funções de setup no script.
- Os arquivos compose são simples e podem ser editados conforme sua necessidade.

## Suporte
Para dúvidas ou sugestões, abra uma issue ou envie um pull request.

---

**WXTOOLS: Modularidade, praticidade e automação para sua infraestrutura Docker!** 