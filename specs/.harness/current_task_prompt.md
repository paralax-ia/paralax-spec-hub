# SDD Technical Specification Refinement Request (In-Flight)

You are the Software Architect responsible for the ecosystem.
The human operator requested a refinement/change in the technical specification below during the Approval Gateway.

## Target Specification File:
`/mnt/home/eduardo/srv/paralax-ia/paralax-spec-hub/specs/SPEC-010-suporte-audio-como-feature.md`

## Current Specification Content:
```markdown
---
spec_id: SPEC-010
title: "Suporte a Instruções de Áudio em Todos os Agentes de IA via Feature Flag e Modelo Gemini Live"
product:
  - paralax-platform
  - customer-support-vehicles
  - duo-dermato-support
  - anero-cafe-support
  - paralax-support
capability: conversational-ai-agent
scope: platform
bounded_context: "Orquestração Conversacional Multimodal & Agentes de IA (Core Subdomain)"
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
prompts:
  - name: vehicles/vehicle_search_agent_instruction
    target_repo: paralax-ia/customer-support-vehicles
    file: vehicles/prompts.py
    symbol: INSTRUCTION
    description: "System instructions for vehicle search agent Isa, supporting WhatsApp audio notes when audio feature flag is enabled."
  - name: anero_cafe/instruction
    target_repo: paralax-ia/anero-cafe-support
    file: anero_cafe/prompts.py
    symbol: INSTRUCTION
    description: "System instructions for Anero Cafe agent, supporting customer voice inquiries when audio feature flag is enabled."
  - name: duo_dermato/instruction
    target_repo: paralax-ia/duo-dermato-support
    file: duo_dermato/prompts.py
    symbol: INSTRUCTION
    description: "System instructions for Duo Dermato clinic agent, supporting patient audio messages when audio feature flag is enabled."
  - name: support/instruction
    target_repo: paralax-ia/paralax-support
    file: support/prompts.py
    symbol: INSTRUCTION
    description: "System instructions for Paralax IT support agent, supporting user audio requests when audio feature flag is enabled."
status: DRAFT
---

# SPEC-010: Suporte a Instruções de Áudio em Todos os Agentes de IA via Feature Flag e Modelo Gemini Live

> **Product:** [`paralax-platform`](../products/paralax-platform.yaml) | [`customer-support-vehicles`](../products/customer-support-vehicles.yaml) | [`duo-dermato-support`](../products/duo-dermato-support.yaml) | [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-support`](../products/paralax-support.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Platform (Transversal a todos os Agentes de Atendimento do Ecossistema)  
> **Bounded Context:** Orquestração Conversacional Multimodal & Agentes de IA (Core Subdomain)  
> **Status:** DRAFT  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-11-02  
> **Arquitetura 12-Factor:** Zero arquivos de configuração no Git; toda parametrização gerada exclusivamente via variáveis de ambiente  
> **Diretriz de Prompts (SPEC-PROMPT-01):** Prompts de sistema e instruções LLM estritamente redigidos em inglês  
> **Regra Mandatória de Áudio:** Mensagens com áudio utilizam obrigatoriamente a família de modelos Gemini Live (`gemini-3.8-live` e fallbacks) quando a feature flag estiver ativada  
> **Governança de Feature Flag:** Ativação granular de áudio por agente via `ENABLE_AUDIO_SUPPORT` (booleano, default `False`)  

---

## 1. Contexto e Motivação

A especificação pioneira **SPEC-009** introduziu o suporte de áudio no agente automotivo (`customer-support-vehicles`), estabelecendo as fundações de ingestão de mensagens de voz via WhatsApp através dos modelos da família **Gemini Live** (`gemini-3.8-live`, `gemini-3.8-live-extended-thinking` e `gemini-2.0-flash`) e a biblioteca base `paralax-evo-crm`.

Com a expansão da plataforma Paralax IA, todos os agentes conversacionais do ecossistema atendem canais com alto volume de comunicação por voz (WhatsApp, canais de mensageria omnicanal):
1. **Concessionária Brasília Automóveis (`customer-support-vehicles`):** Clientes enviando áudios sobre marcas, modelos, orçamentos, fotos e avaliação de usados.
2. **Cafeteria Gourmet Anero Café (`anero-cafe-support`):** Clientes solicitando cardápio, grãos especiais, métodos de extração, encomendas e reservas por áudio.
3. **Clínica Dermatológica Duo Dermato (`duo-dermato-support`):** Pacientes detalhando sintomas, tratamentos e agendamentos de consultas via mensagens de voz.
4. **Suporte Corporativo Paralax (`paralax-support`):** Colaboradores e clientes descrevendo incidentes, dúvidas e suporte técnico por voz.

### O Desafio de Governança: Feature Flag Transversal
Embora o processamento multimodal nativo do Gemini Live ofereça compreensão acústica superior sem requerer pipelines lentos e desconectados de STT (Speech-to-Text), a ativação do processamento de áudio envolve considerações de custo de inferência, capacidade de cota da API e requisitos contratuais por cliente/tenant:
- **Nem todos os canais ou clientes desejam ou autorizam o consumo de áudio:** É mandatório que o suporte a áudio possa ser ligado e desligado dinamicamente por ambiente e por agente via **Feature Flag 12-Factor (`ENABLE_AUDIO_SUPPORT`)**.
- **Comportamento quando a Feature Flag está Desativada (`ENABLE_AUDIO_SUPPORT=False`):**
  - O agente **não deve** tentar submeter o áudio para o LLM (evitando custos e potenciais falhas de cota).
  - O agente **não deve** gerar erro 500 ou descartar silenciosamente a mensagem do usuário.
  - O agente deve responder de forma cortês e imediata ao cliente no WhatsApp/CRM, notificando que o atendimento naquele canal é realizado por texto (ex: *"Desculpe, o atendimento por mensagens de voz está temporariamente indisponível neste canal. Por favor, envie sua mensagem por escrito para que eu possa te ajudar!"*).
- **Comportamento quando a Feature Flag está Ativada (`ENABLE_AUDIO_SUPPORT=True`):**
  - O webhook detecta partes de áudio (`part.is_audio()`).
  - O payload é convertido para GenAI `Content` multimodal via `Part.from_bytes(data=..., mime_type=...)`.
  - O roteamento dinâmico seleciona obrigatoriamente o modelo principal `gemini-3.8-live` com cascata de fallback (`gemini-3.8-live-extended-thinking` ➔ `gemini-2.0-flash`).
  - As mensagens puramente de texto continuam utilizando os modelos textuais padrão (`gemini-3.8-flash` / fallbacks).

---

## 2. Escopo e Repositórios Afetados

A implementação segue a separação estrita por ondas causais:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        ONDA 1 (SDK / BIBLIOTECAS)                      │
│                       paralax-ia/paralax-evo-crm                       │
│  • Validação e padronização dos modelos de áudio em `models.py`:       │
│    - `CrmMessagePart.is_audio()`, `to_genai_part()`                    │
│    - `CrmMessage.has_audio()`, `to_genai_content()`                    │
│  • Inclusão de mensagem padrão de fallback em `models.py`:             │
│    `DEFAULT_AUDIO_DISABLED_MESSAGE`                                    │
│  • Orquestrador `generate_crm_response()` em `generator.py`            │
│    suportando override dinâmico de modelo e fallbacks de áudio         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      ONDA 2 (AGENTES CONVERSACIONAIS)                  │
│                                                                        │
│ 1. paralax-ia/customer-support-vehicles                                │
│    • `vehicles/config.py`: `enable_audio_support: bool = False`,       │
│      `live_audio_model: str`, `live_audio_fallback_models: list[str]`  │
│    • `vehicles/routers/crm.py`: interceptação da flag no `/run`        │
│    • `vehicles/prompts.py`: diretrizes de áudio em inglês (`INSTRUCTION`)│
│                                                                        │
│ 2. paralax-ia/anero-cafe-support                                       │
│    • `anero_cafe/config.py`: `enable_audio_support: bool = False`,     │
│      `live_audio_model: str`, `live_audio_fallback_models: list[str]`  │
│    • `anero_cafe/routers/crm.py`: interceptação da flag no `/run`      │
│    • `anero_cafe/prompts.py`: diretrizes de áudio em inglês (`INSTRUCTION`)│
│                                                                        │
│ 3. paralax-ia/duo-dermato-support                                      │
│    • `duo_dermato/config.py`: `enable_audio_support: bool = False`,    │
│      `live_audio_model: str`, `live_audio_fallback_models: list[str]`  │
│    • `duo_dermato/routers/crm.py`: interceptação da flag no `/run`     │
│    • `duo_dermato/prompts.py`: diretrizes de áudio em inglês (`INSTRUCTION`)│
│                                                                        │
│ 4. paralax-ia/paralax-support                                          │
│    • `support/config.py`: `enable_audio_support: bool = False`,         │
│      `live_audio_model: str`, `live_audio_fallback_models: list[str]`  │
│    • `support/routers/crm.py`: interceptação da flag no `/run`         │
│    • `support/prompts.py`: diretrizes de áudio em inglês (`INSTRUCTION`)  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Contratos de Interface

### 3.1. Viabilidade Técnica e Compatibilidade de SDKs / APIs Externas

- **Dependências Externas / SDKs:**
  - `google-genai>=2.18.0` (suporte unificado ao SDK Google GenAI e chamadas multimodais com `Part.from_bytes`).
  - `google-adk[a2a]>=2.7.1` (orquestração do runner de agentes e persistência de sessões).
  - `pydantic-settings>=2.0.0` (configurações 12-Factor declarativas via variáveis de ambiente).
  - `httpx>=0.28.0` (download assíncrono seguro de áudios remotos quando recebidos via `media_url`).
- **Protocolo e Modo de Execução:**
  - REST/gRPC turn-by-turn assíncrono. O webhook `/run` recebe a mensagem do CRM (áudio já persistido ou codificado em base64/URL pública), converte em `Part.from_bytes(data=bytes, mime_type=mime_type)` e submete ao `runner.run_async()` com o modelo Gemini Live configurado.
  - Streaming bidirecional em tempo real (WebSocket) **não** é exigido para a recepção de notas de voz de mensageria assíncrona (WhatsApp/CRM), simplificando a infraestrutura e garantindo compatibilidade total com o modelo de execução em Cloud Run/Kubernetes.
- **Limitações Conhecidas e Paridade de Recursos:**
  - **Tool Calling (Function Calling):** Suportado nativamente pelo modelo `gemini-3.8-live` em modo multimodal turn-by-turn. As ferramentas de busca de veículos, cardápio de cafés, agendamentos médicos e triagem de suporte permanecem ativas e funcionais ao processar áudio.
  - **Codecs Suportados:** Ingestão nativa de `audio/ogg; codecs=opus` (padrão de mensagens de voz do WhatsApp), `audio/mp4`, `audio/wav`, `audio/mpeg`.
  - **Tamanho Máximo de Mídia:** Payloads de áudio limitados a 25 MB por requisição.
  - **Preservação de Contexto:** O histórico de conversa prévio (`session_service`) é mantido intacto, permitindo alternar de forma transparente entre turnos de texto e turnos de áudio.
- **Estratégia de Spike (Onda 0):**
  - Concluída com sucesso na validação da SPEC-009. Os testes unitários e de integração em `paralax-evo-crm` e `customer-support-vehicles` comprovaram a viabilidade técnica de ingestão multimodal com `gemini-3.8-live`.
- **Plano de Fallback Arquitetural:**
  1. Se `gemini-3.8-live` retornar erro transitório (429 rate limit ou 503 service unavailable), a chamada executa fallback automático para `gemini-3.8-live-extended-thinking`.
  2. Persistindo a falha, executa fallback para `gemini-2.0-flash`.
  3. Caso a feature flag `ENABLE_AUDIO_SUPPORT` esteja explicitamente `False`, o roteador do agente aborta a submissão ao LLM e despacha imediatamente a mensagem educativa configurada para o usuário final, com status HTTP 200 para o CRM.

---

### 3.2. Contrato de Feature Flag e Configuração 12-Factor (`AgentModel` / `Settings`)

Cada agente de IA implementa a seguinte estrutura padronizada de configuração em seu respectivo módulo de configuração (`config.py`):

```python
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class AgentModel(BaseModel):
    """Configurações de modelos do agente e feature flags multimodais."""

    name: str = Field(
        default="conversational_agent",
        description="Identificador canônico do agente."
    )
    model: str = Field(
        default="gemini-3.8-flash",
        description="Modelo principal para interações puramente textuais."
    )
    fallback_models: list[str] = Field(
        default=["gemini-3.7-flash", "gemini-3.6-flash"],
        description="Modelos secundários para interação textual."
    )
    enable_audio_support: bool = Field(
        default=False,
        validation_alias="ENABLE_AUDIO_SUPPORT",
        description="Feature flag que habilita ou desabilita o processamento de áudios."
    )
    live_audio_model: str = Field(
        default="gemini-3.8-live",
        validation_alias="LIVE_AUDIO_MODEL",
        description="Modelo Gemini Live oficial para processamento de áudio."
    )
    live_audio_fallback_models: list[str] = Field(
        default=["gemini-3.8-live-extended-thinking", "gemini-2.0-flash"],
        validation_alias="LIVE_AUDIO_FALLBACK_MODELS",
        description="Modelos Gemini Live de contingência e fallback de áudio."
    )
    audio_disabled_fallback_message: str = Field(
        default=(
            "Desculpe, o atendimento por mensagens de voz está temporariamente desativado "
            "neste canal. Por favor, envie sua mensagem por texto para que eu possa te ajudar!"
        ),
        validation_alias="AUDIO_DISABLED_FALLBACK_MESSAGE",
        description="Mensagem enviada ao cliente quando áudio for recebido com a feature flag desligada."
    )
    enable_heartbeat: bool = Field(default=True)
```

---

### 3.3. Contrato de Roteamento no Webhook `/run` dos Agentes

Todos os agentes de IA (`customer-support-vehicles`, `anero-cafe-support`, `duo-dermato-support`, `paralax-support`) devem adotar o seguinte fluxo determinístico no endpoint `/run`:

```python
@router.post("/run")
async def run_crm(request: CrmRequest):
    """Processa eventos de mensagens recebidas do CRM via webhook."""
    if request.method != "message/send":
        raise HTTPException(status_code=400, detail="Method not supported")

    message = request.params.message
    content, has_audio = message.to_genai_content()

    # 1. Verificação da Feature Flag de Áudio
    if has_audio:
        if not config.agent_settings.enable_audio_support:
            logger.warning(
                "Audio message received but audio support is disabled (ENABLE_AUDIO_SUPPORT=False). "
                "Sending friendly fallback notice to customer."
            )
            fallback_text = config.agent_settings.audio_disabled_fallback_message
            await crm_api.send_message(
                user_id=request.params.user_id,
                context_id=request.params.context_id,
                text=fallback_text,
            )
            return {"status": "success", "detail": "Audio received but disabled by feature flag"}

        # Áudio habilitado: roteamento obrigatório para família Gemini Live
        primary_model = config.agent_settings.live_audio_model
        fallback_models = config.agent_settings.live_audio_fallback_models
        logger.info(
            "Audio instruction detected and feature flag ENABLE_AUDIO_SUPPORT=True. "
            "Routing to Gemini Live model: '%s' (fallbacks: %s)",
            primary_model,
            fallback_models,
        )
    else:
        # Mensagem textual: modelos textuais padrão
        primary_model = config.agent_settings.model
        fallback_models = config.agent_settings.fallback_models

    # 2. Execução da Orquestração com Seleção Dinâmica de Modelo
    final_text, vertex_session_id = await generate_crm_response(
        runner=runner,
        session_service=session_service,
        user_id=request.params.user_id,
        vertex_session_id=request.params.vertex_session_id,
        content=content,
        context_id=request.params.context_id,
        use_redis_mapping=bool(config.USE_REDIS_MAPPING),
        redis_client=redis_client,
        timeout_seconds=int(config.AI_CALL_TIMEOUT_SECONDS),
        crm_client=crm_api,
        heartbeat_messages=HEARTBEAT_MESSAGES,
        enable_heartbeat=config.agent_settings.enable_heartbeat,
        primary_model_override=primary_model,
        fallback_models_override=fallback_models,
    )

    return {"status": "success", "vertex_session_id": vertex_session_id}
```

---

### 3.4. Matriz de Variáveis de Ambiente 12-Factor

| Variável de Ambiente | Tipo | Padrão | Descrição |
| :--- | :---: | :---: | :--- |
| `ENABLE_AUDIO_SUPPORT` | `bool` | `false` | Feature flag mestre de áudio. Aceita `true`, `1`, `yes`. |
| `LIVE_AUDIO_MODEL` | `str` | `gemini-3.8-live` | Modelo principal da família Gemini Live para processamento de áudio. |
| `LIVE_AUDIO_FALLBACK_MODELS` | `list[str]` | `["gemini-3.8-live-extended-thinking", "gemini-2.0-flash"]` | Modelos Live secundários em caso de 429/503. |
| `AUDIO_DISABLED_FALLBACK_MESSAGE` | `str` | *"Desculpe, o atendimento por mensagens de voz está temporariamente desativado..."* | Mensagem de cortesia retornada ao usuário final quando áudio for enviado com a flag desligada. |

---

### 3.5. Governança de Prompts (SPEC-PROMPT-01)

Em conformidade rigorosa com **SPEC-PROMPT-01**, todos os prompts de sistema devem ser redigidos **exclusivamente em inglês**, exportados como a constante `INSTRUCTION` no arquivo local `prompts.py` de cada repositório e sincronizados centralmente no Langfuse.

#### 1. Concessionária de Veículos (`customer-support-vehicles`)
- **Identificador Canônico (SSOT Langfuse):** `vehicles/vehicle_search_agent_instruction`
- **Repositório:** `paralax-ia/customer-support-vehicles`
- **Arquivo Local / Fallback:** `vehicles/prompts.py` (constante `INSTRUCTION`)
- **Papel:** Instrução de sistema da assistente virtual Isa (Brasília Automóveis)
- **Idioma:** Estritamente em inglês
- **Trecho de Diretriz Multimodal de Áudio Adicionado ao Prompt:**
```text
<audio_and_voice_guidelines>
When receiving voice notes or audio messages from the customer:
1. Listen attentively to all vehicle criteria stated by voice (brand, model, year, transmission, price range, trade-in details).
2. Answer promptly in clear, courteous Portuguese, keeping tone professional yet warm.
3. If the audio is partially unclear, confirm the understood details and politely ask for clarification on the ambiguous parts.
4. Execute available tools (search_vehicles, get_vehicle_details) using the voice-extracted parameters seamlessly.
</audio_and_voice_guidelines>
```

#### 2. Cafeteria Gourmet (`anero-cafe-support`)
- **Identificador Canônico (SSOT Langfuse):** `anero_cafe/instruction`
- **Repositório:** `paralax-ia/anero-cafe-support`
- **Arquivo Local / Fallback:** `anero_cafe/prompts.py` (constante `INSTRUCTION`)
- **Papel:** Instrução de sistema do barista virtual do Anero Café
- **Idioma:** Estritamente em inglês
- **Trecho de Diretriz Multimodal de Áudio Adicionado ao Prompt:**
```text
<audio_and_voice_guidelines>
When receiving audio inquiries from coffee lovers or store customers:
1. Identify the requested items, coffee varieties, brewing methods, grain grind preferences, or table reservations spoken in the audio.
2. Reply in engaging, natural Portuguese, expressing passion for specialty coffee.
3. Use tool functions (search_menu, check_table_availability) based on the spoken intent without requiring the customer to type.
</audio_and_voice_guidelines>
```

#### 3. Clínica Dermatológica (`duo-dermato-support`)
- **Identificador Canônico (SSOT Langfuse):** `duo_dermato/instruction`
- **Repositório:** `paralax-ia/duo-dermato-support`
- **Arquivo Local / Fallback:** `duo_dermato/prompts.py` (constante `INSTRUCTION`)
- **Papel:** Instrução de sistema da recepcionista virtual da Clínica Duo Dermato
- **Idioma:** Estritamente em inglês
- **Trecho de Diretriz Multimodal de Áudio Adicionado ao Prompt:**
```text
<audio_and_voice_guidelines>
When patients send voice notes regarding dermatological appointments, procedures, or questions:
1. Listen with maximum empathy, identifying the desired medical procedure, preferred dates, or concerns.
2. Formulate reassuring and professional responses in Brazilian Portuguese, respecting medical ethics and clinic privacy.
3. NEVER make direct medical diagnoses; guide the patient to schedule an in-person or telemedicine evaluation with doctors.
</audio_and_voice_guidelines>
```

#### 4. Suporte Corporativo (`paralax-support`)
- **Identificador Canônico (SSOT Langfuse):** `support/instruction`
- **Repositório:** `paralax-ia/paralax-support`
- **Arquivo Local / Fallback:** `support/prompts.py` (constante `INSTRUCTION`)
- **Papel:** Instrução de sistema do agente de suporte técnico e helpdesk da Paralax
- **Idioma:** Estritamente em inglês
- **Trecho de Diretriz Multimodal de Áudio Adicionado ao Prompt:**
```text
<audio_and_voice_guidelines>
When users report system incidents, bugs, or questions via audio messages:
1. Transcribe the technical issue mentally, extracting system name, error symptoms, urgency, and affected users.
2. Provide concise, step-by-step diagnostic guidance or register the support ticket via available tools.
3. Respond in structured, technical yet approachable Portuguese.
</audio_and_voice_guidelines>
```

---

## 4. Critérios de Aceitação (Gherkin)

### Cenário 1: Mensagem de voz recebida com Feature Flag de Áudio ATIVADA (`ENABLE_AUDIO_SUPPORT=True`)
- **Dado** que o agente está operando com a variável de ambiente `ENABLE_AUDIO_SUPPORT=true`
- **E** a configuração `live_audio_model` está definida como `"gemini-3.8-live"`
- **Quando** o webhook `/run` receber uma mensagem do CRM contendo parte do tipo `audio` (codec `audio/ogg; codecs=opus`)
- **Então** o sistema deve detectar `has_audio == True`
- **E** deve invocar `generate_crm_response` com `primary_model_override="gemini-3.8-live"`
- **E** deve processar a instrução de voz com sucesso, retornando resposta textual coerente para o cliente via CRM API
- **E** deve registrar log com nível INFO indicando roteamento para o modelo Gemini Live.

### Cenário 2: Mensagem de voz recebida com Feature Flag de Áudio DESATIVADA (`ENABLE_AUDIO_SUPPORT=False`)
- **Dado** que o agente está operando com a variável de ambiente `ENABLE_AUDIO_SUPPORT=false` (padrão)
- **Quando** o webhook `/run` receber uma mensagem do CRM contendo parte do tipo `audio`
- **Então** o sistema deve detectar `has_audio == True`
- **E** deve verificar que `enable_audio_support` é `False`
- **E** NÃO deve invocar o runner do LLM nem consumir cotas da API Gemini Live
- **E** deve despachar para o cliente via CRM API a mensagem amigável: *"Desculpe, o atendimento por mensagens de voz está temporariamente desativado neste canal. Por favor, envie sua mensagem por texto para que eu possa te ajudar!"*
- **E** deve retornar HTTP 200 para o CRM sem lançar exceção 500
- **E** deve registrar log de advertência (WARNING) indicando que o áudio foi interceptado e recusado pela feature flag.

### Cenário 3: Mensagem puramente textual recebida com Feature Flag de Áudio ATIVADA (`ENABLE_AUDIO_SUPPORT=True`)
- **Dado** que a feature flag `ENABLE_AUDIO_SUPPORT=true` está ativada
- **Quando** o webhook `/run` receber uma mensagem contendo apenas texto (`has_audio == False`)
- **Então** o sistema deve selecionar o modelo textual padrão do agente (`model="gemini-3.8-flash"`)
- **E** deve orquestrar a resposta normalmente sem acionar o modelo Gemini Live.

### Cenário 4: Mensagem combinada (áudio + texto) com Feature Flag ATIVADA
- **Dado** que `ENABLE_AUDIO_SUPPORT=true`
- **Quando** o webhook receber mensagem com uma parte de áudio e uma parte de texto explicativo
- **Então** o método `to_genai_content()` deve encapsular ambas as partes no mesmo objeto `Content(role="user")`
- **E** o modelo `gemini-3.8-live` deve ser acionado com o conteúdo multimodal completo.

### Cenário 5: Resiliência e Fallback de Modelos Live sob Erro Transitório
- **Dado** que `ENABLE_AUDIO_SUPPORT=true`
- **E** o modelo principal `gemini-3.8-live` retorna erro HTTP 429 (Rate Limit) ou 503 (Overloaded)
- **Quando** `generate_crm_response` executar a chamada
- **Então** o gerador deve alternar automaticamente para `gemini-3.8-live-extended-thinking`
- **E**, se persistir, para `gemini-2.0-flash`
- **E** o usuário deve receber a resposta normalmente sem quebra do fluxo conversacional.

### Cenário 6: Consistência Estrutural em Todos os 4 Agentes de IA
- **Dado** os repositórios `customer-support-vehicles`, `anero-cafe-support`, `duo-dermato-support` e `paralax-support`
- **Quando** a suíte de testes `just verify` for executada em cada um
- **Então** todos os 4 agentes devem validar a presença de `enable_audio_support` em `config.py`
- **E** todos os 4 agentes devem possuir testes unitários reproduzindo os cenários com flag ligada e desligada com docstrings iniciando por `Business Rule:`.

---

## 5. Plano de Rollout e Compatibilidade

### 5.1. Estratégia de Versionamento SemVer
- **`paralax-ia/paralax-evo-crm` (Onda 1):**
  - Incremento SemVer Minor (`v0.5.0` ou compatível) introduzindo constantes e contratos auxiliares de feature flag.
  - Publicação no Google Cloud Artifact Registry.
- **Repositórios de Agentes (Onda 2):**
  - Atualização do lockfile (`uv lock --upgrade-package paralax-evo-crm`).
  - Deploy em homologação com `ENABLE_AUDIO_SUPPORT=false`.
  - Execução de testes de regressão automatizados em `just verify`.

### 5.2. Plano de Ativação Gradual (Canary Rollout)
1. **Fase 1 (Silent Rollout):** Deploy de todos os agentes em produção com `ENABLE_AUDIO_SUPPORT=false`. Áudios recebidos recebem resposta imediata de fallback de texto amigável.
2. **Fase 2 (Canary Brasília Automóveis):** Ativação de `ENABLE_AUDIO_SUPPORT=true` apenas para `customer-support-vehicles` para validação de volume de voz de clientes de concessionária.
3. **Fase 3 (Expansão Ecossistema):** Ativação de `ENABLE_AUDIO_SUPPORT=true` para `anero-cafe-support`, `duo-dermato-support` e `paralax-support` sob monitoramento de métricas no Langfuse e dashboard de latência.
```

## Current Subtasks State in State Tracker:
### COMPLETED AND FROZEN SUBTASKS (DO NOT MODIFY ALREADY DELIVERED SCOPE):
  (No completed tasks so far)

### PENDING SUBTASKS / UPCOMING WAVES (OPEN FOR REFINEMENT):
  - [task-1] Wave 1 in `paralax-ia/paralax-evo-crm` (Status: PENDING)
  - [task-2] Wave 2 in `paralax-ia/customer-support-vehicles` (Status: PENDING)
  - [task-3] Wave 2 in `paralax-ia/anero-cafe-support` (Status: PENDING)
  - [task-4] Wave 2 in `paralax-ia/duo-dermato-support` (Status: PENDING)
  - [task-5] Wave 2 in `paralax-ia/paralax-support` (Status: PENDING)

## Operator Requested Change Instruction:
O modelo Gemini Live não funciona para o CRM

## Mandatory Refinement Rules:
1. PRESERVE COMPLETED WORK: It is strictly forbidden to regress, remove, or modify the scope, public interface contracts, or acceptance criteria of already completed tasks (none).
2. UPDATE THE FILE DIRECTLY ON DISK: Rewrite/edit the file `SPEC-010-suporte-audio-como-feature.md` incorporating the requested changes:
   - Add or update Interface Contracts and Acceptance Criteria (Gherkin) for pending tasks or new waves.
   - Update the Context and Motivation section reflecting recent decisions.
   - Adjust YAML Frontmatter (`target_repositories`) if new subtasks or modules are added for upcoming waves.
   - Ensure the specification strictly complies with canonical ecosystem SDD format.
3. MANDATORY PROMPT GOVERNANCE (SPEC-PROMPT-01): If any target repository is an AI agent (`role: ai-agent`) or if the spec touches instructions, system prompts, or files like `prompts.py`, you MUST declare all affected prompts in YAML Frontmatter under `prompts:` with `name`, `target_repo`, `file`, `symbol`, and `description`. Document the exact prompt text in English in Section 3.5.
4. MANDATORY TECHNICAL FEASIBILITY AND SDK COMPATIBILITY: It is strictly prohibited to design architecture or public interface contracts assuming unsupported features in third-party or emerging SDKs (such as Google ADK, Gemini Live API, or WebSocket streaming) without verifying feasibility. For any real-time, audio, streaming, or emerging SDK integration: (a) Explicitly document required SDK dependencies, versions, and contract signatures in Section 3.1; (b) Specify protocol constraints (e.g., tool calling limitations in streaming mode, socket lifecycle, audio codecs); (c) If capability is not proven in codebase, specify a preliminary Wave 0 Spike task (`role: spike`) before feature implementation; (d) Define an architectural fallback in Section 3.1.