---
spec_id: SPEC-020
title: Parametrização Declarativa 12-Factor de Registro de Bot e Segmentação de Texto nos Agentes de IA
product:
- customer-support-vehicles
- duo-dermato-support
- paralax-support
- anero-cafe-support
- paralax-platform
capability: conversational-ai-agent
scope: multi-repo
bounded_context: Conversational Agent / Canais & Infraestrutura GitOps
origin_module: paralax-spec-hub
target_repositories:
- repo: paralax-ia/anero-cafe-support
  wave: 1
  role: ai-agent
- repo: paralax-ia/customer-support-vehicles
  wave: 1
  role: ai-agent
- repo: paralax-ia/duo-dermato-support
  wave: 1
  role: ai-agent
- repo: paralax-ia/paralax-support
  wave: 1
  role: ai-agent
- repo: paralax-ia/argocd
  wave: 2
  role: gitops
status: DRAFT
---

# SPEC-020: Parametrização Declarativa 12-Factor de Registro de Bot e Segmentação de Texto nos Agentes de IA

> **Product:** [`customer-support-vehicles`](../products/customer-support-vehicles.yaml) | [`duo-dermato-support`](../products/duo-dermato-support.yaml) | [`paralax-support`](../products/paralax-support.yaml) | [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Agentes de IA (`anero-cafe-support`, `customer-support-vehicles`, `duo-dermato-support`, `paralax-support`) e GitOps K8s (`argocd`)  
> **Bounded Context:** Conversational Agent / Canais de Mensageria & Infraestrutura GitOps  
> **Status:** APPROVED  
> **Autor:** Antigravity & Eduardo F. Santos  
> **Data de Criação:** 2026-11-26  
> **Arquitetura 12-Factor & Padronização:** Parametrização 100% declarativa das variáveis de registro do bot e segmentação de texto consumidas pelo entrypoint dos contêineres e expostas via manifestos do ArgoCD.  

---

## 1. Contexto e Motivação

Durante a evolução dos agentes de suporte do ecossistema Paralax IA e a desativação da fragmentação cega de mensagens de 300 caracteres (iniciada na SPEC-018), os scripts de registro do bot no CRM (`scripts/crm_register_bot.sh`) foram atualizados para enviar:
- `text_segmentation_enabled: False`
- `text_segmentation_limit: 4000`
- `text_segmentation_min_size: 100`

Entretanto, esses valores foram inicialmente codificados de forma estática (hardcoded) no payload do script shell. Conforme os princípios fundamentais da arquitetura **12-Factor** e as diretrizes do ecossistema Paralax IA:
> *"O entrypoint foi concebido para consumir variáveis de ambiente. Esse valor deveria estar configurado nos agentes e externalizado declarativamente nos manifestos do Kubernetes."*

### 1.1. Análise de Causa Raiz (RCA - Ishikawa & 5 Whys)

1. **Método (Falta de Externalização Declarativa):**
   - O payload do `crm_register_bot.sh` não utilizava `os.environ.get(...)` para os parâmetros de segmentação e debounce, dependendo de valores literais em Python.
2. **Ambiente / Configuração (12-Factor Breakdown):**
   - Os modelos Pydantic `Config` dos agentes não declaravam os campos correspondentes, impedindo a injeção ou sobrescrita via `.env` ou variáveis de contêiner.
3. **GitOps (Ausência nos Manifestos K8s):**
   - Os manifestos K8s no repositório `argocd` (`base/` e overlays `prod/`) não declaravam formalmente as variáveis operacionais do bot (`TEXT_SEGMENTATION_ENABLED`, `TEXT_SEGMENTATION_LIMIT`, etc.), quebrando o Single Source of Truth (SSOT).

---

## 2. Arquitetura da Solução

```
┌────────────────────────────────────────────────────────┐
│                      ArgoCD GitOps                     │
│  (Manifestos K8s base/ e prod/patch-env.yaml)          │
│                                                        │
│  • TEXT_SEGMENTATION_ENABLED: "false"                  │
│  • TEXT_SEGMENTATION_LIMIT: "4000"                     │
│  • TEXT_SEGMENTATION_MIN_SIZE: "100"                   │
│  • DELAY_PER_CHARACTER: "50.0"                         │
│  • DEBOUNCE_TIME: "5"                                  │
└───────────────────────────┬────────────────────────────┘
                            │
                            │ Injeção via K8s Pod Env
                            ▼
┌────────────────────────────────────────────────────────┐
│             Container Pod (Agente de IA)               │
│                                                        │
│   1. entrypoint.sh ──► bash /app/crm_register_bot.sh   │
│         │                                              │
│         ▼                                              │
│      Lê Variáveis de Ambiente do Pod:                  │
│      - TEXT_SEGMENTATION_ENABLED (def: false)          │
│      - TEXT_SEGMENTATION_LIMIT (def: 4000)             │
│      - TEXT_SEGMENTATION_MIN_SIZE (def: 100)           │
│      - DELAY_PER_CHARACTER (def: 50.0)                 │
│      - DEBOUNCE_TIME (def: 5)                          │
│         │                                              │
│         ▼ POST / PATCH                                 │
│   2. CRM API (/api/v1/agent_bots)                      │
│         │                                              │
│   3. Inicia uvicorn main:app                           │
│      - Config.TEXT_SEGMENTATION_ENABLED                │
│      - Config.TEXT_SEGMENTATION_LIMIT                  │
│      - Config.TEXT_SEGMENTATION_MIN_SIZE               │
└────────────────────────────────────────────────────────┘
```

---

## 3. Especificação Técnica Detalhada

### 3.1. Atualização do Script de Registro (`scripts/crm_register_bot.sh`)
Em todos os 4 agentes (`anero-cafe-support`, `customer-support-vehicles`, `duo-dermato-support`, `paralax-support`), o script deve consumir variáveis de ambiente de forma segura, com fallbacks adequados:

```bash
PAYLOAD=$(python3 -c "
import json, os

enabled_raw = os.environ.get('TEXT_SEGMENTATION_ENABLED', 'false').strip().lower()
text_seg_enabled = enabled_raw in ('true', '1', 't', 'yes')
text_seg_limit = int(os.environ.get('TEXT_SEGMENTATION_LIMIT', '4000'))
text_seg_min_size = int(os.environ.get('TEXT_SEGMENTATION_MIN_SIZE', '100'))
delay_per_char = float(os.environ.get('DELAY_PER_CHARACTER', '50.0'))
debounce = int(os.environ.get('DEBOUNCE_TIME', '5'))

print(json.dumps({
  'name': os.environ.get('BOT_NAME', 'Agente Google Cloud'),
  'description': f\"Agente da Engine {os.environ.get('ENGINE_NAME', 'unknown')}\",
  'bot_provider': 'evo_ai',
  'outgoing_url': f\"http://localhost:5000/{os.environ.get('AGENT_NAME', 'unknown')}/crm/run\",
  'api_key': os.environ['AGENT_API_KEY'],
  'debounce_time': debounce,
  'text_segmentation_enabled': text_seg_enabled,
  'text_segmentation_limit': text_seg_limit,
  'text_segmentation_min_size': text_seg_min_size,
  'delay_per_character': delay_per_char
}))
")
```

### 3.2. Atualização dos Modelos de Configuração (`config.py`)
Em cada agente (`anero_cafe/config.py`, `vehicles/config.py`, `duo_dermato/config.py`, `support/config.py`), adicionar campos no Pydantic `Config`:
```python
TEXT_SEGMENTATION_ENABLED: bool = Field(
    default=False, validation_alias="TEXT_SEGMENTATION_ENABLED"
)
TEXT_SEGMENTATION_LIMIT: int = Field(
    default=4000, validation_alias="TEXT_SEGMENTATION_LIMIT"
)
TEXT_SEGMENTATION_MIN_SIZE: int = Field(
    default=100, validation_alias="TEXT_SEGMENTATION_MIN_SIZE"
)
DELAY_PER_CHARACTER: float = Field(
    default=50.0, validation_alias="DELAY_PER_CHARACTER"
)
DEBOUNCE_TIME: int = Field(
    default=5, validation_alias="DEBOUNCE_TIME"
)
```

### 3.3. Testes Unitários de Regra de Negócio (`tests/unit/test_crm_register_bot.py`)
Expandir os testes unitários para validar:
1. Comportamento default (sem variáveis de ambiente explícitas): `text_segmentation_enabled is False`, `text_segmentation_limit == 4000`, `text_segmentation_min_size == 100`.
2. Sobrescrita via variáveis de ambiente: quando `TEXT_SEGMENTATION_ENABLED="true"` e `TEXT_SEGMENTATION_LIMIT="2000"`, o payload reflete exatamente as variáveis injetadas.

### 3.4. Declaração no Repositório `argocd` (GitOps Onda 2)
Nos manifestos K8s (`base/` e overlays `prod/patch-env.yaml` de cada agente), adicionar explicitamente:
```yaml
- name: TEXT_SEGMENTATION_ENABLED
  value: "false"
- name: TEXT_SEGMENTATION_LIMIT
  value: "4000"
- name: TEXT_SEGMENTATION_MIN_SIZE
  value: "100"
```

---

## 4. Plano de Implementação (Ondas Topológicas)

### Onda 1: Agentes de IA (Paralelo)
- `paralax-ia/anero-cafe-support`
- `paralax-ia/customer-support-vehicles`
- `paralax-ia/duo-dermato-support`
- `paralax-ia/paralax-support`
  - Tarefas:
    1. Atualizar `scripts/crm_register_bot.sh`.
    2. Atualizar `config.py` com os campos 12-factor.
    3. Atualizar e expandir `tests/unit/test_crm_register_bot.py` e testes de configuração.
    4. Executar linters (`ruff`, `isort`, `pyright`) e suíte de testes.
    5. Abrir Pull Request com `gh pr create`.

### Onda 2: Infraestrutura GitOps
- `paralax-ia/argocd`
  - Tarefas:
    1. Atualizar `base/<agente>/deployment.yaml` e/ou `prod/<agente>/patch-env.yaml`.
    2. Executar testes de validação do ArgoCD / Kustomize.
    3. Abrir Pull Request com `gh pr create`.

---

## 5. Critérios de Aceite e Regras de Negócio (TDD)

1. **Business Rule:** O registro do bot no CRM consome prioritariamente as variáveis de ambiente `TEXT_SEGMENTATION_ENABLED`, `TEXT_SEGMENTATION_LIMIT`, `TEXT_SEGMENTATION_MIN_SIZE`, `DELAY_PER_CHARACTER` e `DEBOUNCE_TIME`.
2. **Business Rule:** Na ausência de variáveis de ambiente, os defaults seguros devem ser estritamente `text_segmentation_enabled: False`, `text_segmentation_limit: 4000`, `text_segmentation_min_size: 100`, `delay_per_character: 50.0`, `debounce_time: 5`.
3. **Business Rule:** O modelo de configuração dos agentes reflete declarativamente as variáveis operacionais em conformidade com o Twelve-Factor App.
4. **Business Rule:** Os manifestos K8s no repositório ArgoCD declaram formalmente as variáveis para todos os agentes em produção.
