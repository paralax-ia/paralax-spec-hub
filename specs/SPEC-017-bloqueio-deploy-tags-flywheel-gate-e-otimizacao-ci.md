---
spec_id: SPEC-017
title: "Bloqueio de Deploy em Produção por Reprovação do Flywheel em Novas Tags e Otimização de CI/CD"
product:
  - paralax-platform
  - customer-support-vehicles
  - duo-dermato-support
  - anero-cafe-support
  - paralax-support
capability: ci-cd-orchestration
scope: platform
bounded_context: "Orquestração de CI/CD, Gate de Release Federado e Política de Deploy em Produção sob Governança do Flywheel"
origin_module: actions-workflows
target_repositories:
  - repo: paralax-ia/actions-workflows
    wave: 1
    role: ci-cd
  - repo: paralax-ia/paralax-spec-hub
    wave: 1
    role: hub
  - repo: paralax-ia/customer-support-vehicles
    wave: 2
    role: agent
  - repo: paralax-ia/anero-cafe-support
    wave: 2
    role: agent
  - repo: paralax-ia/duo-dermato-support
    wave: 2
    role: agent
  - repo: paralax-ia/google-calendar-agent
    wave: 2
    role: agent
  - repo: paralax-ia/paralax-support
    wave: 2
    role: agent
  - repo: paralax-ia/paralax-agents-common
    wave: 2
    role: sdk
  - repo: paralax-ia/paralax-evo-crm
    wave: 2
    role: sdk
  - repo: paralax-ia/evo-bot-runtime
    wave: 2
    role: service
prompts: []
status: DRAFT
spec_version: "1.0.0"
revisions:
  - version: "1.0.0"
    date: "2026-11-21"
    author: "@antigravity"
    type: "INITIAL"
    summary: "Especificação do gate de deploy bloqueante para novas tags com o agentic-flywheel, migração para autenticação via BOT_APP_ID, eliminação de retestes pós-merge e procedimentos de atualização de harness."
---

# SPEC-017: Bloqueio de Deploy em Produção por Reprovação do Flywheel em Novas Tags e Otimização de CI/CD

> **Product:** [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`ci-cd-orchestration`](../capabilities/ci-cd-orchestration/capability.yaml)  
> **Scope:** Platform (Transversal a todos os repositórios e serviços do ecossistema Paralax IA)  
> **Bounded Context:** Orquestração de CI/CD, Gate de Release Federado e Política de Deploy em Produção sob Governança do Flywheel  
> **Status:** DRAFT  
> **Autor:** Antigravity / Eduardo F. Santos  
> **Data de Criação:** 2026-11-21  

---

## 1. Contexto e Motivação

No ecossistema corporativo da **Paralax IA**, agentes de inteligência artificial geram e evoluem código de forma autônoma através do **Agentic Flywheel** (localizado no repositório `eduardosan/agentic-flywheel`). No entanto, a esteira de entrega contínua nos repositórios consumidores (`paralax-ia`) apresentava brechas operacionais:

1. **Deploy Incondicional em Novas Tags:** Sempre que uma tag `v*` é criada (seja via release automatizado ou intervenção do mantenedor), os workflows `deploy.yml` dos agentes acionavam imediatamente o Google Cloud Build para compilar e subir imagens no Artifact Registry de produção e atualizavam o repositório `argocd`. Se o código na tag contivesse desvios arquiteturais, regressões ou degradações de conformidade não detectados, o deploy em produção ocorria sem qualquer bloqueio prévio.
2. **Descontinuação de Tokens Estáticos e Adoção do `BOT_APP_ID`:** O token pessoal `FLYWHEEL_DISPATCH_TOKEN` foi formalmente descontinuado no ecossistema. Todo o tráfego cross-repo deve utilizar a autenticação segura do GitHub App corporativo (`BOT_APP_ID` e `BOT_PRIVATE_KEY`), que gera tokens de instalação temporários com isolamento estrito.
3. **Redundância de Testes após Merge na Branch `main`:** Os workflows dos repositórios frequentemente escutam tanto `pull_request` quanto `push: branches: [main]`. Como a branch `main` é estritamente protegida e só aceita Pull Requests previamente aprovados, a execução repetida de suítes de testes idênticas no merge da `main` causa atrasos de esteira e desperdício de runners.
4. **Governança de Atualização do Harness e Spec Hubs:** Padronização dos comandos canônicos para atualizar a instrumentação do harness nos spokes e sincronizar sub-specs com o `paralax-spec-hub`.

---

## 2. Escopo e Repositórios Afetados

A entrega organiza-se em **duas ondas topológicas estritas**:

### Onda 1 (Infraestrutura Central de CI/CD e Governança)
- [ ] **Sub-tarefa 1 (`paralax-ia/paralax-spec-hub`):** [Onda 1] [hub] Registro da SPEC-017 no catálogo de especificações e atualização da capability `ci-cd-orchestration`.
- [ ] **Sub-tarefa 2 (`paralax-ia/actions-workflows`):** [Onda 1] [ci-cd] Criação do workflow reutilizável `flywheel-tag-gate.yml` autenticado via `BOT_APP_ID` e injeção do pré-requisito de aprovação no `agent-deploy.yml` e `python-package-pipeline.yml`.

### Onda 2 (Consumidores, Agentes e Microsserviços)
- [ ] **Sub-tarefa 3 (`paralax-ia/customer-support-vehicles`, `anero-cafe-support`, `duo-dermato-support`, `google-calendar-agent`, `paralax-support`):** [Onda 2] [agents] Atualização de `deploy.yml` para encadear `needs: flywheel-gate`, propagando `secrets: inherit` para o gate.
- [ ] **Sub-tarefa 4 (`paralax-ia/paralax-agents-common`, `paralax-evo-crm`):** [Onda 2] [sdks] Inclusão do gate do flywheel antes da publicação formal de assets e releases de pacotes wheel.
- [ ] **Sub-tarefa 5 (`paralax-ia/evo-bot-runtime`, `evo-ai-crm-community`, `evo-ai-frontend-community`):** [Onda 2] [services] Remoção da execução redundante de testes unitários no trigger `push: branches: [main]`.

---

## 3. Contratos de Interface e Arquitetura

### 3.1. Workflow Reutilizável `flywheel-tag-gate.yml` (`actions-workflows`)

Novo workflow centralizado responsável por interrogar o pipeline do Flywheel no repositório `eduardosan/agentic-flywheel`:

```yaml
# actions-workflows/.github/workflows/flywheel-tag-gate.yml
name: Flywheel Tag Gate

on:
  workflow_call:
    inputs:
      tag:
        description: "Tag da release a ser avaliada (ex: v0.3.2)"
        required: true
        type: string
      target_repo:
        description: "Repositório do spoke (padrão: github.repository)"
        required: false
        type: string
        default: ""
    secrets:
      BOT_APP_ID:
        description: "ID do GitHub App corporativo"
        required: true
      BOT_PRIVATE_KEY:
        description: "Chave privada do GitHub App corporativo"
        required: true

jobs:
  evaluate-tag:
    name: "Validar Release no Flywheel"
    runs-on: ubuntu-latest
    steps:
      - name: Gerar Token de GitHub App para o Flywheel
        id: app-token
        uses: actions/create-github-app-token@v1
        with:
          app-id: ${{ secrets.BOT_APP_ID }}
          private-key: ${{ secrets.BOT_PRIVATE_KEY }}
          owner: eduardosan
          repositories: agentic-flywheel

      - name: Acionar Avaliação no Flywheel e Aguardar Veredito
        env:
          GH_TOKEN: ${{ steps.app-token.outputs.token }}
          REPO: ${{ inputs.target_repo || github.repository }}
          TAG: ${{ inputs.tag }}
          COMMIT_SHA: ${{ github.sha }}
        run: |
          set -eo pipefail
          echo "🚀 Solicitando avaliação da tag ${TAG} (${COMMIT_SHA}) para ${REPO} no agentic-flywheel..."
          
          # Dispara o workflow no repositório central do flywheel
          gh workflow run tag-code-evaluation.yml \
            -R eduardosan/agentic-flywheel \
            -f target_repo="${REPO}" \
            -f tag="${TAG}" \
            -f commit_sha="${COMMIT_SHA}"

          # Aguarda o registro e obtenção do Run ID
          sleep 8
          RUN_ID=$(gh run list -R eduardosan/agentic-flywheel \
            --workflow=tag-code-evaluation.yml \
            --json databaseId -q '.[0].databaseId')

          echo "Acompanhando execução do Flywheel Gate (Run ID: ${RUN_ID})..."
          gh run watch "${RUN_ID}" -R eduardosan/agentic-flywheel --exit-status
```

---

### 3.2. Bloqueio Seletivo: Condição Estrita para Novas Tags

O gate do Flywheel **NÃO** deve ser acionado em Pull Requests comuns ou em deploys manuais de staging, atuando cirurgicamente no corte de novas tags:

Nos workflows dos agentes (`.github/workflows/deploy.yml`):

```yaml
jobs:
  # Executa testes rápidos apenas em PR
  test-pr:
    if: github.event_name == 'pull_request'
    uses: paralax-ia/actions-workflows/.github/workflows/agent-deploy.yml@main
    secrets: inherit
    with:
      agent_version: 'pr-${{ github.event.pull_request.number }}'
      deploy_target: 'none'

  # Gate do Flywheel: Ativado SOMENTE no caso de novas tags
  flywheel-gate:
    name: Flywheel Quality Gate
    if: startsWith(github.ref, 'refs/tags/')
    uses: paralax-ia/actions-workflows/.github/workflows/flywheel-tag-gate.yml@main
    secrets: inherit
    with:
      tag: ${{ github.ref_name }}

  # Deploy em Produção: Condicionado à aprovação do Flywheel
  deploy-production:
    name: Deploy to Production from Tag
    needs: [ flywheel-gate ]  # 👈 BLOQUEANTE
    if: startsWith(github.ref, 'refs/tags/')
    uses: paralax-ia/actions-workflows/.github/workflows/agent-deploy.yml@main
    secrets: inherit
    with:
      agent_version: ${{ github.ref_name }}
      deploy_target: 'production'
      agent_service_name: 'prod-anero-cafe-support'
```

---

### 3.3. Eliminação de Testes Redundantes no Merge da Main

1. **Repositórios de Microsserviços e Go/Rails (`evo-bot-runtime`, `evo-ai-frontend-community`):**
   - No workflow `ci.yml`, o gatilho `push: branches: [main]` deve ser restrito. Testes unitários completos rodam exclusivamente em `pull_request`.
   - Se o commit entrar na `main` sem passar por PR (o que já é vetado por política), a esteira pode auditar via API ou checar o status prévio do commit.
2. **Workflows de Build de Imagens (`docker-publish.yml`):**
   - Na branch `main`, a imagem é construída diretamente aproveitando o cache de build sem reexecutar suítes de testes unitários que foram validadas no PR correspondente.

---

### 3.4. Comandos Canônicos para Atualização de Repositórios e Spec Hub

Para garantir reprodutibilidade operacional, qualquer operador ou agente deve utilizar os seguintes comandos da CLI `harness`:

#### A. Atualizar o Harness de um Repositório Spoke:
1. **Instalar / Atualizar templates, sensores e o justfile no Spoke:**
   ```bash
   harness install --path /home/eduardo/srv/paralax-ia/<nome-do-spoke>
   ```
2. **Atualizar dependências do Flywheel Engine no Spoke:**
   ```bash
   harness flywheel update /home/eduardo/srv/paralax-ia/<nome-do-spoke>
   ```
3. **Validar conformidade local com sensores e testes:**
   ```bash
   harness verify --path /home/eduardo/srv/paralax-ia/<nome-do-spoke>
   ```

#### B. Atualizar e Sincronizar o Spec Hub (`paralax-spec-hub`):
1. **Sincronizar Sub-spec de um Spoke para a Spec Mestre do Hub:**
   ```bash
   harness spec sync-hub \
     --repo-spec /home/eduardo/srv/paralax-ia/<spoke>/specs/SPEC-017.md \
     --hub-spec /home/eduardo/srv/paralax-ia/paralax-spec-hub/specs/SPEC-017-bloqueio-deploy-tags-flywheel-gate-e-otimizacao-ci.md \
     --workspace-root /home/eduardo/srv/paralax-ia
   ```
2. **Evoluir uma Especificação Preservando Tarefas Anteriores (Living Specs):**
   ```bash
   harness spec update SPEC-017 \
     --prompt "Expandir o gate para validar imagens do docker-publish nos microsserviços" \
     --author "@eduardo"
   ```
3. **Mapear e Regenerar Catálogo de Produtos e Capacidades no Hub:**
   ```bash
   harness map-all
   ```

---

## 4. Critérios de Aceitação (Gherkin)

### Cenário 1: Nova tag aprovada pelo Flywheel é implantada em produção
- **Dado** que uma nova tag `v0.4.0` é enviada para o repositório de um agente
- **Quando** o job `flywheel-gate` consultar o `agentic-flywheel` via `BOT_APP_ID`
- **E** o Flywheel aprovar o diff com score de conformidade 100/100
- **Então** o job `flywheel-gate` deve concluir com sucesso
- **E** o job `deploy-production` deve compilar a imagem no Cloud Build e disparar a atualização no ArgoCD.

### Cenário 2: Nova tag reprovada pelo Flywheel bloqueia o deploy
- **Dado** que uma nova tag `v0.4.0` contém código reprovado pelo juiz do Flywheel
- **Quando** o `flywheel-gate` executar no `actions-workflows`
- **Então** o Flywheel deve emitir veredito `REJECTED`
- **E** o job `flywheel-gate` deve falhar imediatamente com exit code 1
- **E** o job `deploy-production` NÃO deve ser iniciado, impedindo qualquer alteração no Artifact Registry ou no cluster GKE.

### Cenário 3: Pull Request executa apenas testes rápidos
- **Dado** um novo Pull Request aberto contra a branch `main`
- **Quando** o workflow for acionado
- **Então** o job `test-pr` deve ser executado
- **E** o job `flywheel-gate` NÃO deve ser disparado.

### Cenário 4: Merge na main não repete testes de PR
- **Dado** um PR aprovado com checks de teste verdes
- **Quando** o PR for mesclado na branch `main`
- **Então** a suíte de testes unitários não deve ser reexecutada desnecessariamente.

---

## 5. Plano de Rollout e Compatibilidade

1. **Onda 1:** Mesclar esta SPEC-017 no `paralax-spec-hub` e implementar o workflow `flywheel-tag-gate.yml` em `actions-workflows`.
2. **Onda 2:** Atualizar os orquestradores `deploy.yml` dos agentes conversacionais para incluir a dependência `needs: [flywheel-gate]`.
3. **Segurança:** Assegurar que os secrets de organização `BOT_APP_ID` e `BOT_PRIVATE_KEY` estejam com herança ativa (`secrets: inherit`).
