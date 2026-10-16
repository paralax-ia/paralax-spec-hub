# SPEC-003: Orquestração de Respostas de IA, Fallback de Modelos e Heartbeat

> **Product:** [`customer-support-vehicles`](../products/customer-support-vehicles.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Platform  
> **Bounded Context:** IA Conversacional & Resiliência (Core Subdomain)  
> **Status:** MERGED  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-10-12  
> **Repositórios Impactados:**  
> - `paralax-ia/paralax-evo-crm`  
> - `paralax-ia/customer-support-vehicles`

---

## 1. Visão Geral e Intenção (The "Why")

Assegurar resiliência na geração de respostas de IA para o CRM sob alta latência, esgotamento transitório de cotas de LLM (ex: 429 ou 503) e chamadas longas a ferramentas externas (tool calls), mantendo o usuário informado via mensagens de status (heartbeat) com backoff exponencial.

---

## 2. Casos de Uso & Requisitos de Negócio

### Caso de Uso 1: Fallback em Cascata de Provedores e Modelos LLM
* **Ator:** Agente de Atendimento (`customer-support-vehicles`).
* **Pré-condição:** Lista ordenada de modelos reservas fornecida via parâmetro `fallback_models`.
* **Fluxo Principal:**
  1. O agente invoca `generate_crm_response()`.
  2. Caso o modelo principal lance erro transitório (`ServiceUnavailable`, `ResourceExhausted`, `ServerError` ou `google.genai.errors.APIError` 429), o gerador itera sequencialmente pelos modelos de fallback.
  3. A resposta é gerada com o primeiro modelo com sucesso e o modelo original do runner é restaurado após a chamada.
  4. Se todos os modelos falharem, uma mensagem amigável de indisponibilidade temporária é retornada sem interromper o serviço.
* **Critério de Aceitação:**
  - O agente não encerra abruptamente a requisição com exceção 500 para o CRM.

### Caso de Uso 2: Heartbeat com Exponential Backoff em Tool Calls
* **Ator:** Usuário aguardando resposta longa.
* **Pré-condição:** `enable_heartbeat = True` e detecção de `function_call` ou processamento prolongado (>30s).
* **Fluxo Principal:**
  1. Durante a execução da tool call, uma tarefa em background envia mensagens periódicas da lista `heartbeat_messages`.
  2. O intervalo inicial é de 10s e cresce com fator de 1.5 até o teto de 90s.
  3. Ao finalizar a execução do agente, o `stop_event` é acionado interrompendo imediatamente o loop de mensagens intermediárias.
* **Critério de Aceitação:**
  - Heartbeat permanece desabilitado por padrão (`enable_heartbeat = False`).
  - Nenhuma mensagem de heartbeat é enviada após a conclusão da resposta.

### Caso de Uso 3: Recuperação Automática de Sessão Expirada
* **Ator:** Gerador de resposta `generate_crm_response`.
* **Pré-condição:** Sessão expirada ou não encontrada (`SessionNotFoundError`).
* **Fluxo Principal:**
  1. O gerador detecta a ausência da sessão no Vertex / ADK.
  2. Cria uma nova sessão transparente e atualiza a chave de mapeamento no Redis.
  3. Repete a inferência com sucesso na nova sessão criada.
* **Critério de Aceitação:**
  - Falha de conexão com Redis durante a recuperação é capturada sem quebrar a execução global.

---

## 3. Modelo de Dados e Contratos de Interface

### Assinatura da Função de Orquestração (em `paralax-evo-crm`):
```python
async def generate_crm_response(
    runner: Any,
    session_service: Any,
    user_id: str,
    vertex_session_id: str,
    content: Any,
    context_id: str,
    use_redis_mapping: bool,
    timeout_seconds: int,
    crm_client: Any,
    heartbeat_messages: list[str],
    enable_heartbeat: bool = False,
    fallback_models: Optional[list[str]] = None,
    redis_client: Optional[Any] = None,
) -> tuple[str, str]: ...
```

---

## 4. Plano de Decomposição (Sub-Tarefas)

- [x] **Sub-tarefa 1 (`paralax-evo-crm`):**
  - Implementar orquestração `generate_crm_response()` em `paralax/evo/crm/generator.py`.
  - Implementar serviço `send_heartbeats()` em `paralax/evo/crm/heartbeat.py`.
  - Adicionar suíte completa de testes unitários em `tests/paralax/evo/crm/test_generator.py` e `test_heartbeat.py`.

- [x] **Sub-tarefa 2 (`customer-support-vehicles`):**
  - Configurar lista de fallback de modelos (`fallback_models`) e habilitar heartbeat no roteador `/crm/run` do agente de veículos.
