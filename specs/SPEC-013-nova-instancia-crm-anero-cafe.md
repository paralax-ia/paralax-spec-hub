---
spec_id: SPEC-013
title: "Nova Instância Dedicada do CRM para Anero Café (anerocafe.paralax.ia.br) e Atualização Holística de Pipelines"
product:
  - anero-cafe-support
  - paralax-platform
capability: customer-relationship-management
scope: platform
bounded_context: "CRM (Supporting Subdomain) / Infraestrutura & Orquestração Multi-Tenant"
origin_module: paralax-platform
target_repositories:
  - repo: paralax-ia/terraform
    wave: 1
    role: infrastructure
  - repo: paralax-ia/argocd
    wave: 1
    role: gitops
  - repo: paralax-ia/actions-workflows
    wave: 1
    role: ci-cd-platform
  - repo: paralax-ia/evolution-crm
    wave: 2
    role: orchestrator
  - repo: paralax-ia/evo-ai-crm-community
    wave: 2
    role: crm-backend
  - repo: paralax-ia/evo-ai-frontend-community
    wave: 2
    role: crm-frontend
  - repo: paralax-ia/evo-bot-runtime
    wave: 3
    role: orchestrator
  - repo: paralax-ia/anero-cafe-support
    wave: 3
    role: ai-agent
status: DRAFT
---

# SPEC-013: Nova Instância Dedicada do CRM para Anero Café (`anerocafe.paralax.ia.br`) e Atualização Holística de Pipelines

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml) | [`ci-cd-orchestration`](../capabilities/ci-cd-orchestration/capability.yaml)  
> **Scope:** Platform / Multi-repo (Onda 1: IaC & GitOps; Onda 2: Orquestrador de Imagens CRM; Onda 3: Agentes & Runtime)  
> **Bounded Context:** CRM (Supporting Subdomain) / Infraestrutura & Orquestração Multi-Tenant  
> **Status:** DRAFT  
> **Autor:** Antigravity & Eduardo F. Santos  
> **Data de Criação:** 2026-11-12  
> **Repositórios Impactados:**  
> - `paralax-ia/terraform`  
> - `paralax-ia/argocd`  
> - `paralax-ia/actions-workflows`  
> - `paralax-ia/evolution-crm`  
> - `paralax-ia/evo-ai-crm-community`  
> - `paralax-ia/evo-ai-frontend-community`  
> - `paralax-ia/evo-bot-runtime`  
> - `paralax-ia/anero-cafe-support`  

---

## 1. Contexto e Motivação de Negócio

O cliente **Anero Café** é uma operação de cafeteria de cafés especiais que utiliza o ecossistema Paralax IA para atendimento automatizado, gestão de pedidos B2B/B2C e relacionamento com clientes. 

Atualmente, o CRM comunitário (`evo-ai-crm-community` e satélites) opera em uma única instância global no cluster GKE (`crm.paralax.ia.br`), compartilhada operacionalmente. Com o aumento do volume de atendimentos e a exigência de segregação estrita de dados corporativos (LGPD, sigilo de pedidos, listas de preços B2B e contratos), torna-se imperativo provisionar uma **instância dedicada e isolada do CRM** para o Anero Café, respondendo sob o endereço oficial:

$$\text{URL Canônica: } \mathbf{https://anerocafe.paralax.ia.br}$$

### 1.1. Motivações Primárias
1. **Isolamento Estrito de Dados (Multi-Tenancy por Instância Dedicada):** Base de dados PostgreSQL transacional separada, bucket de armazenamento Cloud Storage exclusivo para comprovantes e mídias, e isolamento de chaves de criptografia e tokens de autenticação.
2. **Independência Operacional e de Manutenção:** Manutenções programadas, migrações de schema Rails (`job-migrate`) e reinicializações de workers (Sidekiq) do Anero Café não impactam outros clientes da plataforma (como os agentes de concessionárias e clínicas).
3. **Atualização Abrangente de Todos os Pipelines:** Para que uma arquitetura multi-instância seja sustentável sem sobrecarga manual, **todas as esteiras de integração contínua (CI), build e GitOps** devem ser adaptadas para reconhecer, compilar e propagar imagens e configurações tanto para a instância global quanto para a instância dedicada do Anero Café em perfeita sincronia.

---

## 2. Topologia de Arquitetura e Infraestrutura

A nova instância do CRM para o Anero Café é implantada no namespace `crm` do cluster GKE (`prod-gke-cluster`), reaproveitando a infraestrutura de rede e segurança corporativa, porém com isolamento completo de workloads e persistência.

```
                                  Internet Pública
                                         │
                                         ▼
                     ┌──────────────────────────────────────┐
                     │    GKE Gateway API (paralax-gateway)  │
                     │    • Host: anerocafe.paralax.ia.br    │
                     │    • TLS via Let's Encrypt           │
                     └──────────────────┬───────────────────┘
                                        │
                                        ▼ (HTTPRoute: anero-crm-route)
        ┌───────────────────────────────┴───────────────────────────────┐
        │                                                               │
  Path: / (Default)                                           Path: /api/*, /cable, /rails/*, /webhooks
        │                                                               │
        ▼                                                               ▼
┌───────────────────────────────┐                             ┌───────────────────────────────┐
│     evo-frontend-anero        │                             │        evo-crm-anero          │
│   (React SPA / Nginx :80)     │                             │  (Rails Web Puma & Sidekiq)   │
│ VITE_API_URL: anerocafe...    │                             │ BACKEND_URL: anerocafe...     │
└───────────────┬───────────────┘                             └───────────────┬───────────────┘
                │                                                             │
                │                                                             │
                ▼                                                             ▼
┌───────────────────────────────┐                             ┌───────────────────────────────┐
│      Outbound Proxy :5000     │◄────────────────────────────┤      Outbound Proxy :5000     │
│  (S2S Envoy mTLS & Workload)  │                             │  (S2S Envoy mTLS & Workload)  │
└───────────────┬───────────────┘                             └───────────────┬───────────────┘
                │                                                             │
                ├─────────────────────────────────────────────────────────────┤
                ▼                                                             ▼
┌───────────────────────────────┐                             ┌───────────────────────────────┐
│     evo-auth-anero (:80)      │                             │      evo-core-anero (:80)     │
│   (Autenticação e Tokens)     │                             │  (Orquestração e Integração)  │
└───────────────────────────────┘                             └───────────────────────────────┘
                │                                                             │
                ▼                                                             ▼
┌───────────────────────────────┐                             ┌───────────────────────────────┐
│   evo-processor-anero (:80)   │                             │   evo-bot-runtime-anero (:80) │
│    (Processamento Assíncrono) │                             │   (Debounce & WhatsApp S2S)   │
└───────────────────────────────┘                             └───────────────┬───────────────┘
                                                                              │
                                                                              ▼
                                                              ┌───────────────────────────────┐
                                                              │      anero-cafe-support       │
                                                              │  (Agente de IA Google ADK)    │
                                                              │  CRM_URL: http://evo-crm-anero│
                                                              └───────────────────────────────┘
```

### 2.1. Camada de Borda, Ingress & Gateway API (`argocd` e `terraform`)
* **FQDN:** `anerocafe.paralax.ia.br`.
* **Cert-Manager:** Inclusão de recurso `Certificate` dedicado (`anero-crm-tls`) ou extensão dos SANs do emissor `letsencrypt-prod` para contemplar `anerocafe.paralax.ia.br`.
* **Gateway Listener:** O listener HTTPS (porta 443) do `paralax-gateway` referencia o secret TLS `anero-crm-tls`.
* **HTTPRoute (`anero-crm-route`):** Criado no namespace `crm` com correspondência estrita para o hostname `anerocafe.paralax.ia.br`:
  * `/auth/*` $\rightarrow$ Rewrite para `/` e backend `evo-auth-anero:80`
  * `/core/*` $\rightarrow$ Rewrite para `/` e backend `evo-core-anero:80`
  * `/processor/*` $\rightarrow$ Rewrite para `/` e backend `evo-processor-anero:80`
  * `/cable` $\rightarrow$ Backend `evo-crm-anero:80` (WebSocket habilitado com `GCPBackendPolicy` sticky/timeout)
  * `/api/*`, `/rails/*`, `/webhooks` $\rightarrow$ Backend `evo-crm-anero:80`
  * `/` (default) $\rightarrow$ Backend `evo-frontend-anero:80`

### 2.2. Microsserviços e Componentes da Instância Anero
Cada componente da stack Evolution CRM é instanciado com o sufixo/identificador `-anero`:
1. **`evo-crm-anero`:**
   * Deployment Web (Puma) e Deployment Worker (Sidekiq em spot nodes).
   * Job de migração (`job-migrate`) executado como hook `PreSync` do ArgoCD.
   * ServiceAccounts e Workload Identity User dedicados vinculados ao GCP IAM (`prod-crm-anero-evo-crm`).
2. **`evo-frontend-anero`:**
   * Deployment Nginx servindo o bundle compilado do SPA.
   * Variáveis de ambiente de runtime injetadas via `docker-entrypoint.sh`:
     * `VITE_API_URL=https://anerocafe.paralax.ia.br`
     * `VITE_AUTH_API_URL=https://anerocafe.paralax.ia.br/auth`
     * `VITE_WS_URL=https://anerocafe.paralax.ia.br`
     * `VITE_EVOAI_API_URL=https://anerocafe.paralax.ia.br/core`
     * `VITE_AGENT_PROCESSOR_URL=https://anerocafe.paralax.ia.br/processor`
3. **`evo-auth-anero`:** Microsserviço de autenticação e emissão de tokens para a instância.
4. **`evo-core-anero`:** Orquestração de regras e integrações específicas da Anero.
5. **`evo-processor-anero`:** Processamento assíncrono de eventos e filas.
6. **`evo-bot-runtime-anero`:** Orquestrador em Go com debouncing de mensagens do canal WhatsApp do Anero Café e repasse direto para o agente `anero-cafe-support`.

### 2.3. Persistência e Infraestrutura em Nuvem (`terraform`)
* **Banco de Dados (Cloud SQL PostgreSQL):**
  * Database dedicado: `anero_crm_prod` no cluster compartilhado `evolution_api_shared_db`.
  * Usuário dedicado: `anero_crm_user` com senha criptografada gerenciada no GCP Secret Manager.
  * Secret Manager: `prod-anero-crm-database-url` e `prod-anero-crm-db-password`.
* **Armazenamento de Objetos (Cloud Storage):**
  * Bucket dedicado: `gs://paralax-prod-anero-crm-storage` com lifecycle de retenção e encriptação via KMS corporativo.
* **Cache e Mensageria (Memorystore Redis):**
  * Isolamento lógico via database index separado (ex: DB `2`) ou prefixo dedicado para filas do Sidekiq e sessões do ActionCable.
* **Segredos Operacionais (GCP Secret Manager & CSI SecretStore):**
  * `anero-crm-secret-key-base`
  * `anero-crm-jwt-secret`
  * `anero-crm-encryption-key`
  * `anero-crm-api-token`
  * `anero-bot-runtime-secret`

---

## 3. Matriz Holística de Atualização de Pipelines (CI/CD)

A criação da nova instância exige a reestruturação e parametrização de **todas as esteiras de entrega contínua** do ecossistema. Nenhum deploy deve depender de intervenção manual ou atualizar apenas a instância legada.

### 3.1. Pipeline 1: Orquestrador de Build do CRM (`paralax-ia/evolution-crm`)
* **Arquivo:** `.github/workflows/main.yml`
* **Deficiência Atual:** A etapa `Generate Matrix` gera um vetor JSON estático apontando exclusivamente para os caminhos `prod/evo-*` no repositório `argocd`.
* **Modificação Mandatória:**
  1. Parametrizar a matriz de deploy do GitOps para suportar **múltiplas instâncias**.
  2. Quando uma imagem é compilada (ex: `evo-ai-crm-community`), o pipeline deve atualizar automaticamente:
     * O manifesto da instância padrão: `infra/prod/evo-crm`
     * O manifesto da instância Anero Café: `infra/prod/anero-crm/evo-crm`
  3. Estruturação da matriz dinâmica:
     ```bash
     INSTANCES=("global" "anero")
     # Para cada módulo buildado, injeta entradas para as instâncias cadastradas:
     # {"name":"evo-crm","repo_name":"evo-ai-crm-community","kustomize_path":"prod/evo-crm"}
     # {"name":"anero-evo-crm","repo_name":"evo-ai-crm-community","kustomize_path":"prod/anero-crm/evo-crm"}
     ```
  4. Garantir que a etapa `Commit and Push` no repositório `argocd` aplique as alterações atomicamente para todas as instâncias em um único commit rastreável.

### 3.2. Pipeline 2: Workflows Reutilizáveis Centralizados (`paralax-ia/actions-workflows`)
* **Arquivos:**
  * `.github/workflows/gitops-update.yml`
  * `.github/workflows/agent-deploy.yml`
* **Modificações Mandatórias:**
  1. **`gitops-update.yml`:**
     * Suporte a múltiplos alvos de Kustomize (`kustomize_target_paths` como string multilinha ou array delimitado).
     * Permitir atualização atômica de instâncias paralelas sem conflitos de concorrência (`git pull --rebase` determinístico).
  2. **`agent-deploy.yml`:**
     * Suporte para associar agentes às suas instâncias de CRM de destino.
     * Inclusão de etapa de validação pós-deploy (smoke test de conectividade contra o endpoint de CRM configurado para o agente em questão).

### 3.3. Pipeline 3: Esteiras dos Repositórios Componentes do CRM
* **Repositórios:**
  * `paralax-ia/evo-ai-crm-community` (`.github/workflows/docker-publish.yml`)
  * `paralax-ia/evo-ai-frontend-community` (`.github/workflows/docker-publish.yml`)
  * `paralax-ia/evo-bot-runtime` (`.github/workflows/docker-publish.yml`)
* **Modificações Mandatórias:**
  * Garantir que disparos avulsos ou publicações de release destes microsserviços utilizem o workflow reutilizável `gitops-update.yml` parametrizado com a lista completa de instâncias afetadas (`prod/evo-*` e `prod/anero-crm/*`).

### 3.4. Pipeline 4: Esteira de CI/CD do Agente Anero Café (`paralax-ia/anero-cafe-support`)
* **Arquivo:** `.github/workflows/deploy.yml` e manifestos em `argocd/prod/anero-cafe-support/`
* **Modificações Mandatórias:**
  1. Atualizar a variável de ambiente `CRM_URL` no manifesto de produção para apontar para o novo serviço do CRM:
     * `CRM_URL = "http://evo-crm-anero"` (ou `http://localhost:5000/crm` com target roteado para `evo-crm-anero`).
  2. Atualizar o sidecar Envoy (`outbound-proxy`) do agente com o target correto:
     * `TARGETS = "crm=http://evo-crm-anero"`
  3. Atualizar o secret referenciado para a chave de API da nova instância:
     * `CRM_TOKEN` vindo de `prod-anero-crm-crm-api-token`.
  4. Suíte de testes automatizados do agente (`tests/unit` e `tests/integration`):
     * Testes que simulam integração com CRM devem validar respostas contra o payload da nova instância.

### 3.5. Pipeline 5: Governança e Validação do Repositório GitOps (`paralax-ia/argocd`)
* **Arquivos:**
  * `apps/prod-anero-crm-*.yaml` (Descritores de Aplicações ArgoCD)
  * `prod/anero-crm/*` (Overlays Kustomize)
  * `tests/test_*.py`
* **Modificações Mandatórias:**
  1. Criação dos manifestos Application no diretório `apps/`:
     * `prod-anero-crm-evo-crm.yaml`
     * `prod-anero-crm-evo-frontend.yaml`
     * `prod-anero-crm-evo-auth.yaml`
     * `prod-anero-crm-evo-core.yaml`
     * `prod-anero-crm-evo-processor.yaml`
     * `prod-anero-crm-evo-bot-runtime.yaml`
  2. Implementação de teste automatizado de validação sintática (`pytest` no CI do `argocd`):
     * Executar `kustomize build` em todos os novos diretórios de `prod/anero-crm/` para garantir ausência de erros de indentação, imagens inexistentes ou referências quebradas de patches.

---

## 4. Contratos de Interface e Configurações Declarativas

### 4.1. Tabela Comparativa de Ambientes e URLs

| Parâmetro / Serviço | Instância Global (Padrão) | Nova Instância Anero Café |
|---|---|---|
| **Hostname Principal** | `crm.paralax.ia.br` | `anerocafe.paralax.ia.br` |
| **Backend Rails URL** | `https://crm.paralax.ia.br` | `https://anerocafe.paralax.ia.br` |
| **Frontend SPA URL** | `https://crm.paralax.ia.br` | `https://anerocafe.paralax.ia.br` |
| **Cookie & Session Domain** | `crm.paralax.ia.br` | `anerocafe.paralax.ia.br` |
| **Certificado TLS** | `crm-tls` (`cert-manager`) | `anero-crm-tls` (`cert-manager`) |
| **Database Cloud SQL** | `prod-crm` (`crm_user`) | `anero_crm_prod` (`anero_crm_user`) |
| **Bucket Cloud Storage** | `paralax-prod-prod-crm-storage` | `paralax-prod-anero-crm-storage` |
| **Redis Database Index** | DB `0` | DB `2` |
| **K8s Service Web** | `evo-crm.crm.svc.cluster.local` | `evo-crm-anero.crm.svc.cluster.local` |
| **K8s Service Frontend** | `evo-frontend.crm.svc.cluster.local` | `evo-frontend-anero.crm.svc.cluster.local` |
| **K8s Service Bot Runtime** | `evo-bot-runtime.crm.svc.cluster.local` | `evo-bot-runtime-anero.crm.svc.cluster.local` |
| **Agente Integrado** | Veículos / Geral | `anero-cafe-support` |

### 4.2. Contrato de Roteamento no Outbound Proxy S2S
Para preservar o princípio de privilégio mínimo e comunicação declarativa via Envoy sidecar (:5000):
* No pod `anero-cafe-support`:
  ```yaml
  - name: outbound-proxy
    env:
    - name: LISTEN_PORT
      value: "5000"
    - name: TARGETS
      value: "crm=http://evo-crm-anero"
  ```
* No pod `evo-crm-anero`:
  ```yaml
  - name: outbound-proxy
    env:
    - name: LISTEN_PORT
      value: "5000"
    - name: TARGETS
      value: "auth=http://evo-auth-anero,api=http://evo-auth-anero/api,core=http://evo-core-anero,bot=http://evo-bot-runtime-anero,anero_cafe_support=http://anero-cafe-support"
  ```

---

## 5. Critérios de Aceitação (Gherkin)

### Cenário 1: Resolução de Ingress HTTPS e Emissão de Certificado TLS
- **Dado** o cluster GKE com o Gateway API `paralax-gateway` e o Cert-Manager ativo
- **Quando** o cliente efetua uma requisição HTTPS para `https://anerocafe.paralax.ia.br`
- **Então** a requisição deve ser respondida com status 200 OK pelo `evo-frontend-anero`
- **E** o certificado SSL retornado deve ser válido, emitido pela Let's Encrypt para o domínio `anerocafe.paralax.ia.br`.

### Cenário 2: Isolamento de Dados Transacionais e Mídias
- **Dado** uma nova conversa iniciada no canal do Anero Café
- **Quando** o cliente envia um comprovante ou anexo durante o atendimento
- **Então** o registro da conversa deve ser persistido exclusivamente no banco `anero_crm_prod` (sem qualquer escrita ou visibilidade no banco `prod-crm`)
- **E** o arquivo deve ser armazenado exclusivamente no bucket `gs://paralax-prod-anero-crm-storage`.

### Cenário 3: Propagação Contínua no Pipeline do `evolution-crm`
- **Dado** uma nova versão ou tag liberada no orquestrador `evolution-crm`
- **Quando** a esteira do GitHub Actions `.github/workflows/main.yml` for executada
- **Então** as imagens compiladas no Cloud Build devem ter suas tags atualizadas tanto em `argocd/prod/evo-crm` quanto em `argocd/prod/anero-crm/evo-crm`
- **E** um único commit GitOps deve ser gerado contendo a matriz completa de atualizações para ambas as instâncias.

### Cenário 4: Comunicação S2S entre `anero-cafe-support` e a Nova Instância
- **Dado** uma mensagem de cliente recebida pelo webhook do Anero Café
- **Quando** o agente `anero-cafe-support` invoca o endpoint de sincronização de contato via SDK `paralax-evo-crm`
- **Então** a requisição deve atingir `http://evo-crm-anero` através do outbound proxy local
- **E** o contato deve ser autenticado utilizando o token da instância Anero (`anero-crm-api-token`).

### Cenário 5: Invariante e Não-Regressão das Instâncias e Agentes Legados
- **Dado** a frota existente de agentes (`customer-support-vehicles`, `duo-dermato-support`, `paralax-support`)
- **Quando** a nova instância e os pipelines atualizados entrarem em operação
- **Então** os endpoints `crm.paralax.ia.br`, suas rotas internas e suas respectivas esteiras de deploy não devem sofrer qualquer alteração de comportamento, indisponibilidade ou reconfiguração indesejada.

---

## 6. Plano de Rollout em Ondas Topológicas (Topological Waves)

O processo de implementação deve seguir rigorosamente a metodologia de ondas da engenharia Paralax:

```
┌────────────────────────────────────────────────────────────────────────┐
│ ONDA 1: Infraestrutura IaC, GitOps Base & Reusable Workflows           │
│ • terraform: Cloud SQL DB/user, GCS bucket, Secrets, Workload Identity │
│ • argocd: Manifests base/prod para anero-crm, Routes, Cert-Manager     │
│ • actions-workflows: Atualização do gitops-update.yml para multi-target│
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ ONDA 2: Orquestração e Pipelines de Microsserviços                     │
│ • evolution-crm: Parametrização da matriz em main.yml                  │
│ • evo-ai-crm-community / evo-ai-frontend-community: Dispatch multi-alvo│
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ ONDA 3: Agentes de IA & Roteamento de Canais                           │
│ • anero-cafe-support: Apontamento para CRM dedicado em patch-env.yaml   │
│ • evo-bot-runtime: Roteamento de canais/instâncias da Anero Café       │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ ONDA 4: Verificação de Conformidade & E2E                              │
│ • Validação de Ingress e TLS em anerocafe.paralax.ia.br                │
│ • Validação de PreSync DB migrations e healthchecks                    │
│ • Teste de transbordo e atendimento integrado com o agente             │
└────────────────────────────────────────────────────────────────────────┘
```

### 6.1. Checklist de Entrega

#### Onda 1 (Infraestrutura & Plataforma)
- [ ] `paralax-ia/terraform`:
  - Declarar banco `anero_crm_prod` e usuário `anero_crm_user`.
  - Declarar bucket `paralax-prod-anero-crm-storage`.
  - Declarar secrets no Secret Manager para chaves da nova instância.
  - Configurar bindings de Workload Identity para os novos ServiceAccounts do GKE.
- [ ] `paralax-ia/argocd`:
  - Criar overlays `prod/anero-crm/` para todos os 6 microsserviços.
  - Criar `apps/prod-anero-crm-*.yaml` para o ArgoCD sincronizar a nova stack.
  - Atualizar `argocd/base/gateway/routes.yaml` adicionando `anero-crm-route`.
  - Atualizar `argocd/base/cert-manager/certificates.yaml` adicionando o domínio `anerocafe.paralax.ia.br`.
  - Adicionar testes de kustomize build em `argocd/tests/`.
- [ ] `paralax-ia/actions-workflows`:
  - Atualizar `gitops-update.yml` para suportar matriz ou lista de destinos de kustomize.

#### Onda 2 (Orquestrador de Build do CRM)
- [ ] `paralax-ia/evolution-crm`:
  - Atualizar `.github/workflows/main.yml` para gerar a matriz incluindo a nova instância Anero Café.
  - Validar build e push de imagens com atualização síncrona de ambas as instâncias no ArgoCD.

#### Onda 3 (Agente & Mensageria)
- [ ] `paralax-ia/anero-cafe-support`:
  - Atualizar `CRM_URL` e `CRM_TOKEN` nos manifestos do agente.
  - Ajustar outbound proxy sidecar para rotear para `evo-crm-anero`.
  - Validar suíte de testes com `just verify`.
- [ ] `paralax-ia/evo-bot-runtime`:
  - Configurar instância do WhatsApp correspondente ao Anero Café para despachar eventos para `evo-crm-anero`.

#### Onda 4 (Validação & Handover)
- [ ] Verificar propagação de DNS e validação do certificado HTTPS `https://anerocafe.paralax.ia.br`.
- [ ] Validar acesso administrativo ao painel do CRM (`evo-frontend-anero`).
- [ ] Testar fluxo conversacional ponta a ponta: Mensagem WhatsApp $\rightarrow$ `evo-bot-runtime` $\rightarrow$ `evo-crm-anero` $\rightarrow$ `anero-cafe-support` $\rightarrow$ Resposta ao cliente.
