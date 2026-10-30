---
spec_id: SPEC-008
title: "Fleet Remediation: compatibilização de todos os agentes com paralax-evo-crm 0.2.4"
product:
  - paralax-platform
capability: customer-relationship-management
scope: platform
bounded_context: "CRM (Supporting Subdomain)"
origin_module: paralax-evo-crm
target_repositories:
  - repo: paralax-ia/paralax-evo-crm
    wave: 1
    role: sdk
  - repo: paralax-ia/customer-support-vehicles
    wave: 2
    role: ai-agent
  - repo: paralax-ia/anero-cafe-support
    wave: 2
    role: ai-agent
  - repo: paralax-ia/duo-dermato-support
    wave: 2
    role: ai-agent
  - repo: paralax-ia/paralax-support
    wave: 2
    role: ai-agent
status: IN_PROGRESS
---

# SPEC-008: Fleet Remediation — compatibilização de todos os agentes com `paralax-evo-crm` 0.2.4

> **Product:** [`paralax-platform`](../products/paralax-platform.yaml)
> **Business Capability:** [`customer-relationship-management`](../capabilities/customer-relationship-management/capability.yaml)
> **Scope:** Platform
> **Bounded Context:** CRM (Supporting Subdomain)
> **Status:** IN_PROGRESS
> **Autor:** Eduardo F. Santos
> **Data de Criação:** 2026-10-30
> **Repositórios Impactados:**
> - `paralax-ia/paralax-evo-crm`
> - `paralax-ia/customer-support-vehicles`
> - `paralax-ia/anero-cafe-support`
> - `paralax-ia/duo-dermato-support`
> - `paralax-ia/paralax-support`
> **Rastreabilidade de Defeito:** Issue base do spoke `customer-support-vehicles` resolvida por `Fixes #55` (PR #56); correção de causa raiz no SDK em `paralax-evo-crm#21`.

---

## 1. Contexto e Motivação

O agente de veículos (`customer-support-vehicles`) entrou em looping infinito reenviando a mensagem de "aguardando" a cada ~90s por mais de 45 minutos (contextId `ac9e6c90-5481-408e-b03f-dd811cc8e667`, Cloud Logging 15:30:09 → 16:13:43 UTC) após falha irrecuperável `429 RESOURCE_EXHAUSTED` do Vertex AI. A causa raiz foi localizada no SDK consumido por **todos** os agentes: em `paralax.evo.crm.generator.run_agent_once`, o sinalizador `stop_event` do agendador de heartbeats (`send_heartbeats`) era acionado apenas no caminho feliz — sem garantia estrutural (`try/finally`) de execução em qualquer saída (exceção do provedor, timeout ou conclusão).

**Decisões recentes registradas neste refinamento:**

1. **Onda 1 concluída (frozen):** fix causal distribuído no SDK como `paralax-evo-crm 0.2.4` (PR `paralax-evo-crm#21`, wheel publicada no `prod-python-registry` com teste de regressão fail-first). O contrato público permanece formalmente inalterado: a mudança é exclusivamente semântica (bump de Patch no SemVer, mesma assinatura de `run_agent_once`).
2. **Onda 2 parcialmente concluída (frozen):** o spoke piloto `customer-support-vehicles` já foi compatibilizado (PR `customer-support-vehicles#56`): teste de reprodução `tests/unit/test_bug_repro.py::test_reproduce_reported_bug` (Red contra o wheel 0.0.16 de produção, Green com 0.2.4), bump para `>=0.2.4` em `pyproject.toml` + `uv.lock` com hash da wheel.
3. **Escopo expandido por solicitação do operador:** o defeito existia para toda a frota pelo compartilhamento do SDK, e a política de plataforma ("compatibilizar todos os agentes com a versão 0.2.4 do evo-crm") exige a sincronização dos demais três falantes do SDK na mesma versão, prevenindo reincidência caso algum spoke habilite `enable_heartbeat` no futuro.
4. **Nota do State Tracker:** o registro `[task-1] Wave 1 in paralax-ia/paralax-common` foi gerado como placeholder; a Onda 1 real desta spec é `paralax-ia/paralax-evo-crm` (já executada). O replane via `harness-state plan --manifest manifest.yaml --spec specs/SPEC-008-evo-crm-024.md` deve adotar a decomposição da Seção 2.

**Frota atual (survey no dia 2026-10-30):**

| Repositório | Consome `paralax-evo-crm` | Referência atual | `enable_heartbeat` | Exposição ao defeito |
|---|---|---|---|---|
| `customer-support-vehicles` | Sim (`vehicles/routers/crm.py`) | `>=0.2.4` (PR #56) | `True` | Red demonstrado (loop em prod) |
| `anero-cafe-support` | Sim (`anero_cafe/routers/crm.py`) | `>=0.0.14` (desatualizado) | `False` | Dormant (defeito no SDK, caminho de heartbeat inativo) |
| `duo-dermato-support` | Sim (`duo_dermato/routers/crm.py`) | `==0.0.14` (pin rígido, desatualizado) | `False` | Dormant |
| `paralax-support` | Sim (`support/routers/crm.py`) | `>=0.2.0` | `False` | Dormant |
| `google-calendar-agent` | **Não** (somente `paralax-agents-common`) | `>=0.0.11` | n/a | Fora do escopo |
| `evo-bot-runtime`, `evo-ai-crm-community` | Não (o SDK é consumido apenas do lado dos agentes) | n/a | n/a | Fora do escopo |

---

## 2. Escopo e Repositórios Afetados

### Onda 1 (Base/SDK) — CONCLUÍDA E FROZEN
- [x] `paralax-ia/paralax-evo-crm`: fix da causa raiz em `run_agent_once` (`try/finally` garantindo `stop_event.set()` + cancelamento da task do heartbeat em conclusão normal, timeout e falha irrecuperável do provedor de modelo, sem mascarar a exceção real), teste de regressão `tests/paralax/evo/crm/test_generator.py::test_run_agent_once_stops_heartbeat_after_unrecoverable_model_error`, bump para `0.2.4` e publicação da wheel no `prod-python-registry`. **Entrega:** [`paralax-evo-crm#21`](https://github.com/paralax-ia/paralax-evo-crm/pull/21).

### Onda 2 (Agentes/Consumidores)
- [x] **(FROZEN — não regredir)** `paralax-ia/customer-support-vehicles`: teste de repro fail-first `tests/unit/test_bug_repro.py::test_reproduce_reported_bug` + bump `paralax-evo-crm>=0.2.4` em `pyproject.toml`/`uv.lock`. **Entrega:** [`customer-support-vehicles#56`](https://github.com/paralax-ia/customer-support-vehicles/pull/56).
- [ ] `paralax-ia/anero-cafe-support`: atualizar `pyproject.toml` para `paralax-evo-crm>=0.2.4`, replicar teste de repro e validar `just verify`. **Contrato do Repro:** `tests/unit/test_bug_repro.py::test_reproduce_reported_bug` sobre `anero_cafe/routers/crm.py` (webhook `/crm/run` coordenando `paralax.evo.crm.generator.generate_crm_response` e `paralax.evo.crm.client.send_message`).
- [ ] `paralax-ia/duo-dermato-support`: **remover o pin rígido `==0.0.14`** e substituir por `paralax-evo-crm>=0.2.4`, replicar teste de repro e validar `just verify`. **Contrato do Repro:** `tests/unit/test_bug_repro.py::test_reproduce_reported_bug` sobre `duo_dermato/routers/crm.py` (webhook `/crm/run` coordenando `generate_crm_response`/`send_message`).
- [ ] `paralax-ia/paralax-support`: bump de `>=0.2.0` para `>=0.2.4`, replicar teste de repro e validar `just verify`. **Contrato do Repro:** `tests/unit/test_bug_repro.py::test_reproduce_reported_bug` sobre `support/routers/crm.py`.

### Fora de Escopo (justificativa)
- `paralax-ia/google-calendar-agent`: não depende do `paralax-evo-crm` (apenas `paralax-agents-common`); não invoca `generate_crm_response`.
- `evo-bot-runtime` e `evo-ai-crm-community`: o SDK é consumido exclusivamente do lado dos agentes; as camadas de orquestração em Go e o backend Rails não são atingidas.

---

## 3. Contratos de Interface

### 3.1. Contrato do SDK — Onda 1 (implementado em 0.2.4)
- **`paralax.evo.crm.generator.run_agent_once(...)` (assinatura inalterada, compatibilidade total):**
  - Garantia nova (semântica de escrita, Patch SemVer): ao finalizar o escopo do recurso — por qualquer caminho de saída (**conclusão normal**, **`asyncio.timeout`** → `TimeoutError`, **exceções de provedor** como `ResourceExhausted`/`ServiceUnavailable`/`ServerError`/`APIError`) — o agendador criado em `asyncio.create_task(send_heartbeats(...))` é terminado: `stop_event.set()` e `heartbeat_task.cancel()`.
  - A exceção real do provedor **continua propagada sem máscara** para `run_with_model_fallback` (final única mensagem de indisponibilidade: "Desculpe, nosso serviço de IA está temporariamente indisponível...").
- **`paralax.evo.crm.generator.generate_crm_response(...)` (inalterada):** timeout como garantia incondicional por conversa (contextId); mensagens de fallback únicas; `SessionNotFoundError`/RedisError mapeados a mensagens terminais.
- **`paralax.evo.crm.client.CRMAPIClient.send_message(...)` (inalterada):** sinks do heartbeat e do texto final; nenhuma nova chamada automática pós-estado terminal.

### 3.2. Contratos nos Spokes — Onda 2 (invariante de integração)
- Nenhum endpoint HTTP novo. Os routers (`anero_cafe/routers/crm.py`, `duo_dermato/routers/crm.py`, `support/routers/crm.py`) chamam `generate_crm_response` exatamente com a mesma assinatura atual; a entrega é de governança de versão (pyproject/uv.lock) + teste de repro, **sem refactors de rota**.
- `duo-dermato-support`: o pin ==0.0.14 é um anti-pattern de governança (bloqueia patches de segurança da frota) e deve passar a floor `>=0.2.4`.

---

## 4. Critérios de Aceitação (Gherkin)

### 4.1. Onda 1 — SDK `paralax-evo-crm 0.2.4` (frozen, implementado)
- **Cenário 1: Falha irrecuperável 429 interrompe o agendador de "aguardando"**
  - **Dado** uma conversa com `context_id` "ac9e6c90-5481-408e-b03f-dd811cc8e667" com `enable_heartbeat=True` e tool call iniciada pelo modelo (task de heartbeat canalizada)
  - **Quando** o runner leva a exceção `ResourceExhausted` (429) após a tool call, esgotando todos os modelos de `fallback_models`
  - **Então** nenhuma mensagem de espera adicional pode ser enviada (`crm_client.send_message` com zero reenvios pós-falha), a exceção 429 original é propagada sem máscara para a camada de fallback, e o resultado terminal retorna a mensagem única "Desculpe, nosso serviço de IA está temporariamente indisponível..."
- **Cenário 2: Timeout determinístico interrompe o agendador**
  - **Dado** a mesma conversa com heartbeat ativo e `timeout_seconds` esgotado durante a execução do runner
  - **Quando** `asyncio.timeout` dispara `TimeoutError`
  - **Então** o agendador de heartbeats é sinalizado e cancelado e a conversa é encerrada em estado terminal ("Estou verificando os detalhes..." único).
- **Cenário 3: Caminho feliz preserva os heartbeats já enviados**
  - **Dado** tool call com resposta do modelo dentro do timeout
  - **Quando** o `async for` termina normalmente
  - **Então** os heartbeats já enviados permanecem válidos e o loop para ao receber `stop_event` (regressão zero no fluxo feliz).

**Referência de implementação (aplicada e validada):** `test_run_agent_once_stops_heartbeat_after_unrecoverable_model_error`, suíte SDK 42/42 e `just verify` 100%.

### 4.2. Onda 2 — Repro por spoke (pendente: anero-cafe-support, duo-dermato-support, paralax-support)

Critérios idênticos e invariáveis para cada um dos três spokes pendentes, onde `<module>` ∈ {`anero_cafe`, `duo_dermato`, `support`}:

- **Cenário 4: Repro fail-first por spoke**
  - **Dado** o venv do spoke resolvendo uma versão do SDK anterior a 0.2.4 (estado atual: 0.0.14, 0.0.14 pinned, 0.2.0) com temporizadores do heartbeat acelerados para validação determinística
  - **Quando** `tests/unit/test_bug_repro.py::test_reproduce_reported_bug` (no repo do spoke) executa `generate_crm_response` com runner simulado que emite tool call e lança `ResourceExhausted` 429 esgotando o fallback
  - **Então** o teste FALHA (Red) comprovando a fuga de heartbeat do wheel instalado (`crm_client.send_message` reexecutado múltiplas vezes antes do bump).
- **Cenário 5: Green após compatibilização**
  - **Dado** `pyproject.toml` atualizado para `paralax-evo-crm>=0.2.4`, `uv.lock` regenerado com hash da wheel 0.2.4 (`uv lock` + `uv sync`), docstring do teste iniciada por `Business Rule:` e docstring estilo Google
  - **Quando** `just verify` (pyright, ruff, isort, `import-linter`, `complexipy` ≤ 15, `pytest`) executa no spoke
  - **Então** o teste de repro passa (zero reenvios após o estado terminal, mensagem única de indisponibilidade, propagação sem máscara) e os testes unitários pré-existentes não regressam (suíte completa em 100%, exceto falhas pré-existentes alheias ao escopo desta spec, evidenciadas na Seção 2 e no tracking do spoke).
- **Cenário 6: Governança de Pull Request (Método inegociável)**
  - **Dado** branch `fix/issue-55-heartbeat-timeout-loop` (ou branch contendo `issue-55`)
  - **Quando** o PR é aberto via `gh pr create`
  - **Então** o corpo contém: (a) linha `Fixes #55`; (b) seção "Ishikawa" com as 6 categorias (Método, Máquina/Ambiente, Mão de Obra/Agente, Material/Dependências, Medição/Testes, Meio Ambiente); (c) seção "5 Porquês" cujo último nível exige o fix estrutural (try/finally + garantia de cleanup), rejeitando captura/mascaramento de exceção; (d) sem commits/tags em `main`.
- **Cenário 7: Paridade preventiva de heartbeat (frota à prova de futuro)**
  - **Dado** qualquer spoke que no futuro habilite `enable_heartbeat=True`
  - **Quando** a falha irrecuperável 429 ou timeout ocorrer
  - **Então** o comportamento terminal é idêntico ao Cenário 1/2 — nada além do fix SDK é necessário no spoke (prova implícita por herança do contrato 0.2.4).

---

## 5. Plano de Rollout e Compatibilidade

### 5.1. Estratégia SemVer e Publicação
- **Onda 1:** Patch `0.2.3 → 0.2.4` (mudança exclusivamente semântica/limpeza de recursos; sem alteração de assinaturas, payloads ou settings). Wheel+sdist publicados no `us-central1-python.pkg.dev/paralax-infra/prod-python-registry` (hash determinístico `sha256:4005…a` para o wheel). **Sem tags automáticas:** a marcação `v0.2.4` formal é etapa do operador humano pós-merge do PR #21 (regra AGENTS.md: agentes não criam tags).
- **Onda 2:** por spoke, apenas atualização de dependência (`pyproject.toml` floor `>=0.2.4` + `uv.lock`), sem alteração de código da aplicação; release do spoke no fluxo SemVer normal da esteira (`agent-deploy.yml`/Cloud Build — tag permanece etapa humana).

### 5.2. Ordem Executiva (ondas topológicas)
1. **Onda 1 (done):** SDK fix e publish → pré-requisito de resolução de dependência.
2. **Onda 2 (parcial):** spoke piloto `customer-support-vehicles` já compatibilizado e congelado (PR #56).
3. **Onda 2 restante (pendente nesta spec):** `anero-cafe-support`, `duo-dermato-support` e `paralax-support` iniciam em paralelo (não interdependem entre si). Ao abrir a issue de fan-out, usar obrigatoriamente a label `agent-run` (modo cloud) ou `agent-local` (modo local), com link explícito desta spec.
4. **Fechamento transacional:** quando todos os spokes reportarem `READY`, Cross-Repo Gate LLM-as-a-Judge (Score ≥ 100/100), merge transacional em cascata e spec assumida como `MERGED` no `capability.yaml` da capability pai.

### 5.3. Compatibilidade e Rollback
- **Compatibilidade:** garantida pelos testes de regressão existentes do SDK (caminho feliz, timeout, RedisError, SessionNotFoundError, model fallback) que passam 100% na 0.2.4 — os consumidores do caminho feliz não percebem mudança.
- **Rollback:** cada spoke mantém seu floor anterior versionado no histórico do `uv.lock`; em caso de defeito regressivo na 0.2.4, o re-bump por spoke para a rodada anterior (`0.0.16`/`0.2.0`) é local e sem rollback de infraestrutura (SDK é Python puro, sem migração de dados). O rollback **não reativa o loop** nos spokes sem heartbeat (caminho inativo hoje), mas o spoke piloto (`customer-support-vehicles`, com `enable_heartbeat=True`) deve permanecer em 0.2.4, pois reverter reativaria o defeito crítico em produção.
- **Observabilidade pós-merge:** o workflow de telemetria pós-merge (`feat(ci): add bug post-merge telemetry and closure workflow`, presente desde 0.2.3 do SDK) fecha o ciclo da issue via esteira assim que os PRs forem mergeados; monitorar "CRM message sent" repetido por contextId sem resposta final como detector operacional de reincidência.

---

## 6. Checklist de Verificação (Onda 2, por spoke pendente)
- [ ] `tests/unit/test_bug_repro.py::test_reproduce_reported_bug` criado com `Business Rule:` e executando Red no wheel pré-bump existente
- [ ] `pyproject.toml`: floor `paralax-evo-crm>=0.2.4` (duo-dermato: remover `==0.0.14`)
- [ ] `uv.lock` regenerado com hash da wheel 0.2.4 (`uv lock` + `uv sync`)
- [ ] `just verify` 100% no spoke
- [ ] PR com branch contendo `issue-55`, corpo com `Fixes #55`, Ishikawa (6 categorias) e 5 Porquês
- [ ] Sem commits/tags em `main`; labels de dispatch corretas na issue de fan-out
