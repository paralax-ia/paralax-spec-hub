# Instruções para Agentes de IA - Paralax Spec Hub (AGENTS.md)

> Este arquivo é a fonte primária de instruções e regras operacionais para agentes de IA que operam no repositório `paralax-spec-hub` e orquestram desenvolvimento orientado a especificações (Spec-Driven Development - SDD) em todo o ecossistema Paralax IA.

---

## 1. Visão Geral e Princípios Fundamentais

O **`paralax-spec-hub`** é o repositório central de governança, arquitetura e especificações de funcionalidades que cruzam múltiplos serviços da Paralax IA.

1. **Intenção antes de Código:** Nenhuma funcionalidade ou alteração de contrato pode começar diretamente nos repositórios spoke (microsserviços/agentes). Toda funcionalidade nasce como uma especificação em `specs/SPEC-XXX-nome.md`.
2. **Grafo Causal e Ondas de Dependência (`manifest.yaml`):** O catálogo oficial define a topologia de dependências:
   - **Onda 1 (Base/SDKs/Libs):** Bibliotecas e SDKs compartilhados (ex: `paralax-agents-common`, `paralax-evo-crm`).
   - **Onda 2 (Aplicações/Agentes):** Consumidores que dependem dos SDKs e contratos da Onda 1 (ex: `customer-support-vehicles`, `duo-dermato-support`, `google-calendar-agent`).
3. **Fechamento Transacional:** O ciclo de vida de uma especificação só é considerado concluído quando todos os spokes implementam suas partes, os testes passam em `just verify`, o Cross-Repo Gate aprova a conformidade com Score 100/100, e os PRs são mergeados transacionalmente.

---

## 2. A Hierarquia DDD: Produtos, Business Capabilities e Specs

A plataforma organiza o ecossistema segundo os princípios de **Domain-Driven Design (DDD)** em três camadas estratégicas:

```
┌────────────────────────────────────────────────────────┐
│           1. Produtos (Core Domains de Clientes)       │
│  (ex: dealership-vehicles, duo-dermato, anero-cafe)    │
└───────────────────────────┬────────────────────────────┘
                            │ consome / orquestra
                            ▼
┌────────────────────────────────────────────────────────┐
│         2. Business Capabilities (Bounded Contexts)    │
│ (ex: customer-relationship-management, scheduling...) │
└───────────────────────────┬────────────────────────────┘
                            │ implementa em incrementos
                            ▼
┌────────────────────────────────────────────────────────┐
│            3. Especificações Formais (Specs)           │
│        (ex: SPEC-001, SPEC-002, SPEC-003)              │
└────────────────────────────────────────────────────────┘
```

1. **Catálogo de Produtos (`products/<product-id>.yaml`):**
   - Representa as soluções completas entregues aos clientes finais ou serviços internos.
   - Define o segmento de mercado (`client_segment`), repositórios que compõem a solução e a lista de capacidades consumidas.
2. **Business Capabilities (Bounded Contexts):** Residem em `capabilities/<capability-id>/capability.yaml`. Representam capacidades corporativas perenes (ex: `customer-relationship-management`, `conversational-ai-agent`, `appointment-scheduling`).
   - **Escopo (`scope`):** `platform` (transversal/compartilhada) ou `product-specific` (dedicada a um segmento).
   - **Produtos Suportados (`supported_products`):** Lista de produtos que utilizam esta capacidade.
   - **Linguagem Ubíqua (`ubiquitous_language`):** Vocabulário formal do domínio (ex: `Contact`, `WorkingHours`, `OutOfOffice`).
   - **Context Map (`context_map`):** Define upstream autoritativo, camada de SDK e consumidores.
   - **Contratos de Runtime (`runtime_contracts`):** Classes e métodos implementados no código real.
3. **Relação Produto ➔ Capability ➔ Spec:** Cada especificação (`specs/SPEC-XXX.md`) é um incremento dentro de um Produto e de uma Business Capability pai. Toda spec deve apontar em seu cabeçalho:
   ```markdown
   # SPEC-002: Mensageria e Gestão de Expediente do CRM
   > **Product:** [`customer-support-vehicles`](../products/customer-support-vehicles.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)
   > **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)
   > **Scope:** Platform
   > **Bounded Context:** CRM (Supporting Subdomain)
   ```
4. **Auditoria e Sincronização Contínua de Contratos (Ferramentas Centrais):**
   O spec hub não contém código executável. As operações de domínio são executadas através do motor central `agentic-flywheel` (ou CLI `harness-state`):
   - **Mapear Todo o Ecossistema:** `flywheel map-all --spec-hub-dir .` (inventaria Produtos ➔ Capacidades ➔ Contratos de Runtime).
   - **Auditar Cobertura de Domínio:** `flywheel audit --spec-hub-dir .` (cruza a Linguagem Ubíqua com o código real).
   - **Sincronizar Contratos de Código:** `flywheel sync --spec-hub-dir .` (atualiza os `runtime_contracts` no `capability.yaml`).
   - **Fechamento Transacional:** O Cross-Repo Gate (`gate.py`) no hub atualiza automaticamente o status da spec para `MERGED` na capability ao aprovar o gate com Score 100/100.

---

## 3. Anatomia de uma Especificação (`specs/SPEC-XXX-nome.md`)

Toda spec deve conter a seguinte estrutura padronizada:
- **Metadados:** ID (`SPEC-XXX`), Título, Status (`DRAFT`, `PLANNED`, `IN_PROGRESS`, `READY`, `MERGED`), Data, Autor e **Business Capability Pai**.
- **Contexto e Motivação:** Problema de negócio que a funcionalidade resolve.
- **Escopo e Repositórios Afetados:** Lista de spokes envolvidos classificados por Onda (`wave: 1`, `wave: 2`).
- **Contratos de Interface:** Esquemas OpenAPI 3.1, assinaturas de métodos de SDKs Python ou payloads de mensageria.
- **Critérios de Aceitação (Gherkin ou Checklist Verificável):** Cenários explícitos utilizados pelo LLM-as-a-Judge no Cross-Repo Gate.
- **Plano de Rollout e Compatibilidade:** Estratégia de migração e versionamento SemVer.

---

## 3. Os Dois Modos de Desenvolvimento: Cloud vs. Local

A plataforma federada suporta dois modos de operação para transformar uma spec em código funcional nos repositórios spoke:

```
                            ┌──────────────────────────────────────────────┐
                            │      paralax-spec-hub: specs/SPEC-XXX.md     │
                            └──────────────────────┬───────────────────────┘
                                                   │
                         ┌─────────────────────────┴─────────────────────────┐
                         ▼                                                   ▼
        ┌───────────────────────────────────┐               ┌───────────────────────────────────┐
        │   OPÇÃO 1: NUVEM (Off the Loop)   │               │   OPÇÃO 2: LOCAL (On the Loop)    │
        │      Totalmente Autônomo          │               │      Pair-Programming / Dev       │
        └─────────────────┬─────────────────┘               └─────────────────┬─────────────────┘
                          │                                                   │
                          ▼                                                   ▼
        ┌───────────────────────────────────┐               ┌───────────────────────────────────┐
        │ Issues com label `agent-run`      │               │ Issues SEM label `agent-run`      │
        │ Webhook -> Runner Hetzner (CT109) │               │ Conexão ao Redis Hetzner via SSH  │
        │ Aider + agentic-qwen gera código  │               │ Agente local (Antigravity) gera   │
        └─────────────────┬─────────────────┘               └─────────────────┬─────────────────┘
                          │                                                   │
                          └─────────────────────────┬─────────────────────────┘
                                                    ▼
                            ┌──────────────────────────────────────────────┐
                            │    Cross-Repo Gate (agentic-flywheel Hub)    │
                            │  • Validação LLM-as-a-Judge (Score 100/100)  │
                            │  • Merge transacional dos PRs em cascata     │
                            │  • Fechamento automático das issues          │
                            └──────────────────────────────────────────────┘
```

---

### 3.1. Opção 1: Desenvolvimento Cloud Autônomo (Desatendido / Off the Loop)

Utilize este modo quando a funcionalidade deve ser implementada de forma assíncrona pelos runners de IA dedicados na nuvem.

#### Como Executar:
1. **Despacho via Fan-Out com Label `agent-run`:**
   Ao decompor a spec, crie uma issue em cada repositório spoke de origem contendo:
   - Título descritivo da sub-tarefa.
   - Link explícito para a spec no spec-hub.
   - **Label obrigatória:** `agent-run`.
   - Exemplo via CLI `gh`:
     ```bash
     gh issue create --repo paralax-ia/paralax-evo-crm \
       --title "feat(contacts): implementar busca por telefone conforme SPEC-002" \
       --body "Implementar contrato conforme especificado em: https://github.com/paralax-ia/paralax-spec-hub/blob/main/specs/SPEC-002-crm-messaging-schedule.md" \
       --label "agent-run"
     ```
2. **Execução Automática no Runner Proxmox:**
   - O spoke CI detecta a label `agent-run` e despacha para o hub `agentic-flywheel`.
   - O runner Hetzner LXC (CT 109) adquire o lock `flock /var/lock/llm.lock`, clona o spoke, roda o Aider com `agentic-qwen:7b`, valida os sensores (`just verify`) e submete o PR.
3. **Ordenação por Ondas:** O State Tracker no Redis Hetzner bloqueia a Onda 2 até a conclusão da Onda 1.
4. **Fechamento:** O Cross-Repo Gate valida o diff consolidado contra a spec, mergeia os PRs e fecha as issues de origem automaticamente.

---

### 3.2. Opção 2: Desenvolvimento Local (Interativo / Pair-Programming / On the Loop)

Utilize este modo quando você (agente local como Antigravity ou desenvolvedor) estiver implementando o código diretamente no ambiente local.

#### Passo 1: Conectar ao State Tracker via Túnel SSH
O estado global das tarefas é coordenado no Redis Hetzner (`192.168.20.5`). No terminal local, abra o túnel seguro na porta do Proxmox:
```bash
ssh -p 8 -N -L 6379:192.168.20.5:6379 eduardo@pve2.for.mat.br
```

#### Passo 2: Planejar Ondas e Criar Issues de Rastreamento
Execute o planejador no repositório `paralax-spec-hub`:
```bash
harness-state plan --manifest manifest.yaml --spec specs/SPEC-XXX.md
```
- O planejador registra as tarefas no Redis ordenadas por onda causal.
- Cria issues de rastreamento nos repositórios spoke com o link da spec central.
- **REGRA CRÍTICA PARA O FLUXO LOCAL:** As issues devem ser criadas **SEM a label `agent-run`** (ou com a label `agent-local`). Isso garante que os runners da nuvem fiquem desativados e não concorram com o desenvolvimento local.

#### Passo 3: Implementar a Onda 1 (SDKs e Bibliotecas Compartilhadas)
1. Navegue até o repositório da biblioteca (ex: `/home/eduardo/srv/paralax-ia/paralax-evo-crm`).
2. Crie a branch de trabalho:
   ```bash
   git checkout -b feat/spec-xxx-funcionalidade
   ```
3. Desenvolva seguindo estritamente as regras de engenharia:
   - **TDD:** Crie primeiro os testes unitários que reproduzem os requisitos da spec.
   - **Docstrings:** Use Google Style docstrings com o prefixo `Business Rule:` nos testes.
   - **PEP 8:** Imports ordenados com `isort`, sem funções aninhadas, sem blocos `try...except` aninhados ou em imports.
4. Valide todos os sensores:
   ```bash
   just verify
   ```
5. Comite, faça push e abra o PR via GitHub CLI:
   ```bash
   git push -u origin feat/spec-xxx-funcionalidade
   gh pr create --title "feat(contacts): implementar busca por telefone conforme SPEC-XXX" --body "Implementa SPEC-XXX..."
   ```
6. Notifique o State Tracker da conclusão da Onda 1:
   ```bash
   harness-state update --spec SPEC-XXX --repo paralax-evo-crm --status READY --pr <URL_DO_PR>
   ```
7. Acione a publicação do novo pacote (ex: via workflow do Cloud Build ou release SemVer) para disponibilizar a versão atualizada no Google Cloud Artifact Registry.

#### Passo 4: Implementar a Onda 2 (Agentes e Aplicações Finais)
1. Navegue até o repositório consumidor (ex: `/home/eduardo/srv/paralax-ia/customer-support-vehicles`).
2. Crie a branch de trabalho:
   ```bash
   git checkout -b feat/spec-xxx-integracao
   ```
3. Atualize o lockfile do projeto para apontar para a versão recém-publicada da lib:
   ```bash
   uv lock --upgrade-package paralax-evo-crm
   uv sync
   ```
4. Implemente as alterações na aplicação e adicione testes de unidade e integração.
5. Valide todos os sensores:
   ```bash
   just verify
   ```
6. Comite, faça push e abra o PR:
   ```bash
   git push -u origin feat/spec-xxx-integracao
   gh pr create --title "feat(tools): integrar busca de contatos conforme SPEC-XXX" --body "Consome nova versão do SDK conforme SPEC-XXX..."
   ```
7. Notifique o State Tracker:
   ```bash
   harness-state update --spec SPEC-XXX --repo customer-support-vehicles --status READY --pr <URL_DO_PR>
   ```

#### Passo 5: Validação no Cross-Repo Gate e Fechamento
Com todos os spokes reportados como `READY`, o Cross-Repo Gate no hub (`agentic-flywheel`) avalia todos os PRs abertos:
- O LLM-as-a-Judge avalia a conformidade dos diffs consolidados contra os critérios de aceitação da spec.
- Com score 100/100, o Gate adiciona a label `harness-approved`, mergeia transacionalmente os PRs de todos os spokes, fecha as issues abertas no Passo 2 e mergeia a branch da spec no `paralax-spec-hub`.

---

## 4. Regras Absolutas de Engenharia para Agentes

1. **Proteção Total da Branch `main`:** É TERMINANTEMENTE PROIBIDO commitar, fazer merge, rebase ou push diretamente na branch `main` de qualquer repositório. Toda alteração deve tramitar por branches de trabalho (`git checkout -b <tipo>/<nome>`) e Pull Requests via `gh pr create`.
2. **Proibição de Criação de Tags:** É TERMINANTEMENTE PROIBIDO aos agentes criar ou fazer push de tags git (`git tag`, `git push --tags`). Tags disparam pipelines de build e deploy em produção e são reservadas a operadores humanos e esteiras autorizadas.
3. **Padrões de Código Python:**
   - **No Nested Functions:** Proibido definir funções dentro de funções.
   - **No Nested Try-Excepts:** Apenas um bloco `try` por escopo lógico, com cadeia plana de `except`.
   - **No Try-Except em Imports:** Imports estáticos no topo.
   - **No Leading Underscores:** Variáveis e funções de módulo não usam `_` no início.
   - **Google Docstrings & PEP 8:** Docstrings completas em classes, métodos e funções.
   - **uv:** Utilize exclusivamente `uv` (`uv run`, `uv sync`, `uv add`).
4. **Testes e Qualidade:**
   - Testes residem estritamente em `tests/unit/` ou `tests/integration/`. Proibido arquivos de teste soltos na raiz.
   - Docstrings de testes iniciam com `Business Rule:`.
5. **Verificação Obrigatória:** Antes de abrir qualquer PR, execute `just verify` para assegurar que linter, checagem de tipos estáticos (`pyright`), fronteiras de arquitetura (`import-linter`) e testes (`pytest`) passem com 100% de sucesso.
