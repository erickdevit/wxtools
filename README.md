# Instalador de Ferramentas - Chatwoot

Este projeto tem como objetivo facilitar a instalação e configuração do Chatwoot utilizando um script automatizado e interativo. O instalador foi pensado para ser simples, seguro e adaptável, permitindo que qualquer pessoa consiga subir uma instância do Chatwoot rapidamente, mesmo sem experiência prévia com Docker ou configurações avançadas.

## O que é Chatwoot?
O Chatwoot é uma plataforma de atendimento multicanal open source, que permite centralizar conversas de diferentes canais (WhatsApp, Facebook, e-mail, etc) em um só lugar.

## Sobre o Instalador
Este repositório contém um script chamado `chatwoot.sh` que automatiza:
- Criação dos arquivos de configuração necessários (`.env` e `docker-compose.yaml`)
- Geração de chaves de segurança
- Configuração de variáveis essenciais
- Inicialização dos containers Docker

O script pode ser facilmente adaptado para servir de base para instaladores de outras ferramentas que utilizem Docker.

## Requisitos
- Docker e Docker Compose instalados
- Bash (Linux, macOS ou WSL no Windows)

## Como usar
1. Clone este repositório:
   ```bash
   git clone <url-do-repositorio>
   cd Projetos
   ```
2. Dê permissão de execução ao script:
   ```bash
   chmod +x chatwoot.sh
   ```
3. Execute o instalador:
   ```bash
   ./chatwoot.sh
   ```
4. Siga as instruções interativas na tela para configurar domínio, imagem Docker, SMTP e outras opções.

## O que o script faz?
- Cria um arquivo `docker-compose.yaml` pronto para uso, com as imagens corretas do Chatwoot, Postgres e Redis
- Gera um arquivo `.env` com as variáveis de ambiente necessárias
- Permite customizar a imagem Docker utilizada
- (Opcional) Configura o envio de e-mails via SMTP
- Sobe todos os serviços automaticamente com Docker Compose

## Personalização
Você pode adaptar o script para instalar outras ferramentas, bastando alterar o bloco de criação do `docker-compose.yaml` e as variáveis de ambiente conforme a necessidade do seu projeto.

## Segurança
O script não sobrescreve arquivos `.env` ou `docker-compose.yaml` já existentes, evitando perda de configurações anteriores.

## Suporte
Para dúvidas ou sugestões, abra uma issue ou envie um pull request.

---

**Desenvolvido para facilitar a vida de quem precisa instalar ferramentas rapidamente!** 