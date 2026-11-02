# SDD Technical Specification Refinement Request (In-Flight)

You are the Software Architect responsible for the ecosystem.
The human operator requested a refinement/change in the technical specification below during the Approval Gateway.

## Target Specification File:
`/mnt/home/eduardo/srv/paralax-ia/paralax-spec-hub/specs/SPEC-010-suporte-audio-como-feature.md`

## Current Specification Content:
```markdown
---
spec_id: SPEC-010
title: "Suporte a Instruções de Áudio em Todos os Agentes de IA via Feature Flag e Modelos Gemini Multimodais (Flash)"
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

# SPEC-010: Suporte a Instruções de Áudio em Todos os Agentes de IA via Feature Flag e Modelos Gemini Multimodais (Flash)

> **Product:** [`paralax-platform`](../products/paralax-platform.yaml) | [`customer-support-vehicles`](../products/customer-support-vehicles.yaml) | [`duo-dermato-support`](../products/duo-dermato-support.yaml) | [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-support`](../products/paralax-support.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Platform (Transversal a todos os Agentes de Atendimento do Ecossistema)  
> **Bounded Context:** Orquestração Conversacional Multimodal & Agentes de IA (Core Subdomain)  
> **Status:** DRAFT  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-11-02  
> **Decisão Arquitetural Crítica:** O modelo Gemini Live NÃO é compatível com webhooks de CRM; a inferência de áudio no CRM utiliza obrigatoriamente modelos Gemini Multimodais nativos turn-by-turn (`gemini-3.8-flash` e sua hierarquia de fallback)  
> **Arquitetura 12-Factor:** Zero arquivos de configuração no Git; toda parametrização gerada exclusivamente via variáveis de ambiente  
> **Diretriz de Prompts (SPEC-PROMPT-01):** Prompts de sistema e instruções LLM estritamente redigidos em inglês  
> **Governança de Feature Flag:** Ativação granular de áudio por agente via `ENABLE_AUDIO_SUPPORT` (booleano, default `False`)  

---

## 1. Contexto e Motivação

Nos canais de atendimento digital operados pela Paralax IA (WhatsApp via Evolution CRM e mensageria omnicanal), uma parcela expressiva das interações dos usuários finais ocorre via notas de voz (áudios). Essa demanda manifesta-se nos diversos domínios de negócio da plataforma:
1. **Concessionária Brasília Automóveis (`customer-support-vehicles`):** Clientes enviando áudios sobre marcas, modelos, orçamentos, fotos e avaliação de seminovos.
2. **Cafeteria Gourmet Anero Café (`anero-cafe-support`):** Clientes solicitando cardápio, grãos especiais, métodos de extração, encomendas e reservas por áudio.
3. **Clínica Dermatológica Duo Dermato (`duo-dermato-support`):** Pacientes detalhando sintomas, tratamentos e agendamentos de consultas via mensagens de voz.
4. **Suporte Corporativo Paralax (`paralax-support`):** Colaboradores e clientes descrevendo incidentes, dúvidas e suporte técnico por voz.

---

### 1.1. Por Que o Modelo Gemini Live Não Funciona para o CRM

Durante os testes de integração e validação operacional no Gateway de Aprovação, identificou-se uma incompatibilidade estrutural profunda entre a API **Gemini Live** e a arquitetura de mensageria assíncrona do CRM:

1. **Descompasso de Paradigmas (Full-Duplex Streaming vs. Webhook HTTP Turn-by-Turn):**
   - A **Gemini Live API** foi desenvolvida para sessões interativas em tempo real baseadas em **WebSockets bidirecionais contínuos** (`BidiStreamSession`), com streaming full-duplex de áudio (áudio contínuo de entrada e saída, interrupções por detecção de fala de baixíssima latência), simulando chamadas telefônicas ao vivo.
   - O ecossistema de CRM (Evo CRM / WhatsApp) opera no paradigma **desacoplado, sem estado (stateless) e baseado em turnos (turn-by-turn)**:
     - O cliente grava e envia uma nota de voz no WhatsApp.
     - O CRM armazena a mídia e despacha uma requisição HTTP `POST /run` para o webhook do agente com o arquivo de áudio (em bytes base64 ou link de mídia).
     - O agente processa a requisição completa, executa chamadas a ferramentas de negócio (bancos de dados, estoques, calendários) e responde através de uma chamada REST à API do CRM (`crm_api.send_message`).
     - A conexão HTTP fecha imediatamente após a resposta.
   - Forçar uma conexão WebSocket Gemini Live dentro de um webhook HTTP turn-by-turn introduz complexidade excessiva, fragilidade no ciclo de vida de sockets, falhas em ambientes serverless (Cloud Run) e custos desnecessários de streaming ativo para mensagens assíncronas estáticas.

2. **Incompatibilidade com o Runner do Google ADK e Chamadas a Ferramentas (Tool Calling):**
   - No runner oficial do Google ADK (`google-adk`), a orquestração conversacional de agentes utiliza o método padrão turn-by-turn `runner.run_async(session_id=..., content=...)` sobre a API Vertex AI `generateContent`.
   - Os modelos Gemini Live não operam como endpoints padrão `generateContent` na location `global` do Vertex AI para requisições com `Part.from_bytes`. Tentar invocar nomes de modelo Gemini Live via `generateContent` resulta em erros de modelo não suportado (`ValueError: Modelo inválido ou não suportado`) ou falhas de protocolo.

3. **A Solução Homologada: Modelos Gemini Multimodais Nativos (Gemini Flash):**
   - Os modelos **Gemini Multimodais** (`gemini-3.8-flash`, com fallbacks para `gemini-3.7-flash` e `gemini-2.5-flash`) são modelos nativamente multimodais que suportam ingestão direta de áudio bruto (`audio/ogg; codecs=opus`, `audio/mp4`, `audio/wav`, `audio/mpeg`) via `Part.from_bytes` na API REST/gRPC `generateContent`.
   - Eles oferecem suporte completo e robusto a **Tool Calling (Function Calling)** com parâmetros extraídos diretamente do áudio gravado, respeitam perfeitamente o ciclo de vida stateless do webhook `/run`, integram-se sem atritos ao runner do Google ADK e possuem validação completa na location `global` do Vertex AI.

---

### 1.2. O Desafio de Governança: Feature Flag Transversal (`ENABLE_AUDIO_SUPPORT`)

O suporte a áudio envolve custos computacionais e considerações contratuais por cliente e por canal. Nem todos os clientes ou canais de mensageria têm contrato ou perfil para processamento de voz.

Por isso, o suporte a áudio deve ser governado por uma **Feature Flag 12-Factor (`ENABLE_AUDIO_SUPPORT`)**, aplicável universalmente a todos os agentes:
- **Quando a Feature Flag está Desativada (`ENABLE_AUDIO_SUPPORT=False`, Padrão):**
  - O agente **não deve** tentar submeter o áudio para o LLM (evitando custos e consumo desnecessário de cota).
  - O agente **não deve** retornar erro HTTP 500 nem descartar silenciosamente a mensagem do usuário.
  - O agente deve responder de forma cortês e imediata ao cliente no WhatsApp/CRM, notificando que o atendimento naquele canal é realizado por texto (ex: *"Desculpe, o atendimento por mensagens de voz está temporariamente desativado neste canal. Por favor, envie sua mensagem por texto para que eu possa te ajudar!"*).
- **Quando a Feature Flag está Ativada (`ENABLE_AUDIO_SUPPORT=True`):**
  - O webhook detecta partes de áudio (`part.is_audio()`).
  - O payload é convertido para GenAI `Content` multimodal via `Part.from_bytes(data=..., mime_type=...)`.
  - O roteamento dinâmico seleciona o modelo multimodal homologado de áudio (`gemini-3.8-flash`) com cascata de fallback (`gemini-3.7-flash` ➔ `gemini-2.5-flash`).
  - Mensagens puramente textuais continuam utilizando os modelos textuais padrão.

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
│  • Constante padrão de fallback: `DEFAULT_AUDIO_DISABLED_MESSAGE`      │
│  • Orquestrador `generate_crm_response()` em `generator.py`            │
│    suportando override dinâmico de modelo multimodal turn-by-turn      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      ONDA 2 (AGENTES CONVERSACIONAIS)                  │
│                                                                        │
│ 1. paralax-ia/customer-support-vehicles                                │
│    • `vehicles/config.py`: `enable_audio_support: bool = False`,       │
│      `audio_model: str = "gemini-3.8-flash"`,                          │
│      `audio_fallback_models: list[str] = ["gemini-3.7-flash", ...]`,   │
│      validação estrita contra `SUPPORTED_GLOBAL_MODELS`                │
│    • `vehicles/routers/crm.py`: interceptação da flag no `/run`        │
│    • `vehicles/prompts.py`: diretrizes de áudio em inglês (`INSTRUCTION`)│
│                                                                        │
│ 2. paralax-ia/anero-cafe-support                                       │
│    • `anero_cafe/config.py`: `enable_audio_support: bool = False`,     │
│      `audio_model`, `audio_fallback_models`, `SUPPORTED_GLOBAL_MODELS` │
│    • `anero_cafe/routers/crm.py`: interceptação da flag no `/run`      │
│    • `anero_cafe/prompts.py`: diretrizes de áudio em inglês (`INSTRUCTION`)│
│                                                                        │
│ 3. paralax-ia/duo-dermato-support                                      │
│    • `duo_dermato/config.py`: `enable_audio_support: bool = False`,    │
│      `audio_model`, `audio_fallback_models`, `SUPPORTED_GLOBAL_MODELS` │
│    • `duo_dermato/routers/crm.py`: interceptação da flag no `/run`     │
│    • `duo_dermato/prompts.py`: diretrizes de áudio em inglês (`INSTRUCTION`)│
│                                                                        │
│ 4. paralax-ia/paralax-support                                          │
│    • `support/config.py`: `enable_audio_support: bool = False`,         │
│      `audio_model`, `audio_fallback_models`, `SUPPORTED_GLOBAL_MODELS` │
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
  - **REST/gRPC turn-by-turn assíncrono exclusivamente.**
  - O webhook `/run` recebe a mensagem do CRM (áudio persistido pelo CRM em base64 ou URL pública), decodifica os bytes e mime-type (`Part.from_bytes(data=bytes, mime_type=mime_type)`), e submete ao `runner.run_async()` com o modelo multimodal homologado (`gemini-3.8-flash`).
  - O uso de sessões WebSocket bidirecionais (Gemini Live) é expressamente proibido para os webhooks do CRM devido à incompatibilidade de protocolo e timeout em arquitetura de microsserviços.
- **Limitações Conhecidas e Paridade de Recursos:**
  - **Tool Calling (Function Calling):** Suportado nativamente e com paridade de 100% pelos modelos Gemini Multimodais (`gemini-3.8-flash`, `gemini-3.7-flash`, `gemini-2.5-flash`) em modo turn-by-turn com áudio.
  - **Codecs de Áudio Suportados:** `audio/ogg; codecs=opus` (padrão oficial de mensagens de voz do WhatsApp), `audio/mp4`, `audio/wav`, `audio/mpeg`.
  - **Tamanho Máximo de Mídia:** Payloads de áudio limitados a 25 MB por requisição.
  - **Preservação de Contexto Conversacional:** O histórico de conversa prévio (`session_service`) é mantido intacto, permitindo alternar de forma transparente entre turnos de texto e turnos de áudio.
- **Estratégia de Spike (Onda 0):**
  - Desnecessária nova spike: a viabilidade da ingestão turn-by-turn via `Part.from_bytes` com `gemini-3.8-flash` já foi comprovada no pipeline de testes do ecossistema.
- **Plano de Fallback Arquitetural:**
  1. Se `gemini-3.8-flash` retornar erro transitório (429 rate limit ou 503 service unavailable), a chamada executa fallback automático para `gemini-3.7-flash`.
  2. Persistindo a falha, executa fallback para `gemini-2.5-flash`.
  3. Caso a feature flag `ENABLE_AUDIO_SUPPORT` esteja `False`, o roteador do agente aborta a submissão ao LLM e despacha imediatamente a mensagem educativa configurada para o usuário final, com status HTTP 200 para o CRM.

---

### 3.2. Contrato de Feature Flag e Configuração 12-Factor (`AgentModel` / `Settings`)

Cada agente de IA implementa a seguinte estrutura padronizada de configuração em seu respectivo módulo de configuração (`config.py`):

```python
from typing import ClassVar
from pydantic import AliasChoices, BaseModel, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

SUPPORTED_GLOBAL_MODELS: list[str] = [
    "gemini-3.8-flash",
    "gemini-3.7-flash",
    "gemini-3.6-flash",
    "gemini-3.5-flash",
    "gemini-2.5-flash",
]


class AgentModel(BaseModel):
    """Configurações de modelos do agente e feature flags multimodais."""

    SUPPORTED_MODELS: ClassVar[list[str]] = SUPPORTED_GLOBAL_MODELS

    name: str = Field(
        default="conversational_agent",
        description="Identificador canônico do agente."
    )
    model: str = Field(
        default="gemini-3.8-flash",
        description="Modelo principal para interações puramente textuais."
    )
    fallback_models: list[str] = Field(
        default=["gemini-3.7-flash", "gemini-3.6-flash", "gemini-2.5-flash"],
        description="Modelos secundários para interação textual."
    )
    enable_audio_support: bool = Field(
        default=False,
        validation_alias=AliasChoices(
            "enable_audio_support",
            "ENABLE_AUDIO_SUPPORT",
        ),
        description="Feature flag que habilita ou desabilita o processamento de áudios."
    )
    audio_model: str = Field(
        default="gemini-3.8-flash",
        validation_alias=AliasChoices(
            "audio_model",
            "AUDIO_MODEL",
            "live_audio_model",
            "LIVE_AUDIO_MODEL",
        ),
        description="Modelo Gemini Multimodal oficial para processamento de áudio turn-by-turn.",
    )
    audio_fallback_models: list[str] = Field(
        default=["gemini-3.7-flash", "gemini-2.5-flash"],
        validation_alias=AliasChoices(
            "audio_fallback_models",
            "AUDIO_FALLBACK_MODELS",
            "live_audio_fallback_models",
            "LIVE_AUDIO_FALLBACK_MODELS",
        ),
        description="Modelos Gemini Multimodais de contingência e fallback de áudio.",
    )
    audio_disabled_fallback_message: str = Field(
        default=(
            "Desculpe, o atendimento por mensagens de voz está temporariamente desativado "
            "neste canal. Por favor, envie sua mensagem por texto para que eu possa te ajudar!"
        ),
        validation_alias=AliasChoices(
            "audio_disabled_fallback_message",
            "AUDIO_DISABLED_FALLBACK_MESSAGE",
        ),
        description="Mensagem enviada ao cliente quando áudio for recebido com a feature flag desligada."
    )
    enable_heartbeat: bool = Field(default=True)

    @field_validator("model", "audio_model")
    @classmethod
    def validate_model(cls, value: str) -> str:
        """Valida se o identificador do modelo pertence aos modelos globais suportados."""
        if not isinstance(value, str):
            raise TypeError(f"O modelo deve ser uma string, recebido: {type(value).__name__}")
        cleaned_value = value.strip()
        if not cleaned_value:
            raise ValueError("O modelo não pode ser vazio.")
        if cleaned_value not in SUPPORTED_GLOBAL_MODELS:
            raise ValueError(
                f"Modelo inválido ou não suportado para CRM: '{value}'. "
                f"Modelos suportados na location global: {SUPPORTED_GLOBAL_MODELS}"
            )
        return cleaned_value

    @field_validator("fallback_models", "audio_fallback_models")
    @classmethod
    def validate_fallback_models(cls, value: list[str]) -> list[str]:
        """Valida a lista de modelos de fallback contra os modelos globais suportados."""
        if not isinstance(value, list):
            raise TypeError("Modelos de fallback devem ser fornecidos como lista.")
        validated: list[str] = []
        for model_name in value:
            cls.validate_model(model_name)
            validated.append(model_name.strip())
        return validated
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

        # Áudio habilitado: roteamento para modelo Gemini Multimodal homologado
        primary_model = config.agent_settings.audio_model
        fallback_models = config.agent_settings.audio_fallback_models
        logger.info(
            "Audio instruction detected and feature flag ENABLE_AUDIO_SUPPORT=True. "
            "Routing to multimodal audio model: '%s' (fallbacks: %s)",
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
| `AUDIO_MODEL` | `str` | `gemini-3.8-flash` | Modelo principal Gemini Multimodal para processamento turn-by-turn de áudio. Suporta alias legado `LIVE_AUDIO_MODEL`. |
| `AUDIO_FALLBACK_MODELS` | `list[str]` | `["gemini-3.7-flash", "gemini-2.5-flash"]` | Modelos secundários multimodais em caso de 429/503. Suporta alias legado `LIVE_AUDIO_FALLBACK_MODELS`. |
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
- **E** a configuração `audio_model` está definida como `"gemini-3.8-flash"`
- **Quando** o webhook `/run` receber uma mensagem do CRM contendo parte do tipo `audio` (codec `audio/ogg; codecs=opus`)
- **Então** o sistema deve detectar `has_audio == True`
- **E** deve invocar `generate_crm_response` com `primary_model_override="gemini-3.8-flash"`
- **E** deve processar a instrução de voz turn-by-turn via `Part.from_bytes` com sucesso
- **E** deve retornar resposta textual coerente para o cliente via CRM API
- **E** deve registrar log com nível INFO indicando roteamento para o modelo multimodal `"gemini-3.8-flash"`.

### Cenário 2: Rejeição de Modelos Gemini Live no Contexto de CRM
- **Dado** que um operador tente configurar `AUDIO_MODEL="gemini-3.8-live"` ou qualquer modelo fora de `SUPPORTED_GLOBAL_MODELS`
- **Quando** o módulo de configuração carregar a classe `AgentModel`
- **Então** o `field_validator` deve lançar um `ValueError` explicativo informando que o modelo não é suportado na location global do Vertex AI para o CRM
- **E** deve impedir a inicialização com configuração de modelo incompatível.

### Cenário 3: Mensagem de voz recebida com Feature Flag de Áudio DESATIVADA (`ENABLE_AUDIO_SUPPORT=False`)
- **Dado** que o agente está operando com a variável de ambiente `ENABLE_AUDIO_SUPPORT=false` (padrão)
- **Quando** o webhook `/run` receber uma mensagem do CRM contendo parte do tipo `audio`
- **Então** o sistema deve detectar `has_audio == True`
- **E** deve verificar que `enable_audio_support` é `False`
- **E** NÃO deve invocar o runner do LLM nem consumir cotas da API
- **E** deve despachar para o cliente via CRM API a mensagem amigável: *"Desculpe, o atendimento por mensagens de voz está temporariamente desativado neste canal. Por favor, envie sua mensagem por texto para que eu possa te ajudar!"*
- **E** deve retornar HTTP 200 para o CRM sem lançar exceção 500
- **E** deve registrar log de advertência (WARNING) indicando que o áudio foi interceptado e recusado pela feature flag.

### Cenário 4: Mensagem puramente textual recebida com Feature Flag de Áudio ATIVADA (`ENABLE_AUDIO_SUPPORT=True`)
- **Dado** que a feature flag `ENABLE_AUDIO_SUPPORT=true` está ativada
- **Quando** o webhook `/run` receber uma mensagem contendo apenas texto (`has_audio == False`)
- **Então** o sistema deve selecionar o modelo textual padrão do agente (`model="gemini-3.8-flash"`)
- **E** deve orquestrar a resposta normalmente.

### Cenário 5: Mensagem combinada (áudio + texto) com Feature Flag ATIVADA
- **Dado** que `ENABLE_AUDIO_SUPPORT=true`
- **Quando** o webhook receber mensagem com uma parte de áudio e uma parte de texto explicativo
- **Então** o método `to_genai_content()` deve encapsular ambas as partes no mesmo objeto `Content(role="user")`
- **E** o modelo multimodal turn-by-turn `gemini-3.8-flash` deve ser acionado com o conteúdo multimodal completo.

### Cenário 6: Resiliência e Fallback sob Erro Transitório
- **Dado** que `ENABLE_AUDIO_SUPPORT=true`
- **E** o modelo principal `gemini-3.8-flash` retorna erro HTTP 429 (Rate Limit) ou 503 (Overloaded)
- **Quando** `generate_crm_response` executar a chamada
- **Então** o gerador deve alternar automaticamente para `gemini-3.7-flash`
- **E**, se persistir, para `gemini-2.5-flash`
- **E** o usuário deve receber a resposta normalmente sem quebra do fluxo conversacional.

### Cenário 7: Consistência Estrutural em Todos os 4 Agentes de IA
- **Dado** os repositórios `customer-support-vehicles`, `anero-cafe-support`, `duo-dermato-support` e `paralax-support`
- **Quando** a suíte de testes `just verify` for executada em cada um
- **Então** todos os 4 agentes devem validar a presença de `enable_audio_support`, `audio_model` e `audio_fallback_models` em `config.py`
- **E** todos os 4 agentes devem possuir testes unitários reproduzindo os cenários com flag ligada e desligada com docstrings iniciando por `Business Rule:`.

---

## 5. Plano de Rollout e Compatibilidade

### 5.1. Estratégia de Versionamento SemVer
- **`paralax-ia/paralax-evo-crm` (Onda 1):**
  - Incremento SemVer Minor (`v0.5.0` ou compatível) introduzindo constantes e contratos auxiliares de feature flag e mensagem de fallback.
  - Publicação no Google Cloud Artifact Registry.
- **Repositórios de Agentes (Onda 2):**
  - Atualização do lockfile (`uv lock --upgrade-package paralax-evo-crm`).
  - Deploy em homologação com `ENABLE_AUDIO_SUPPORT=false`.
  - Execução de testes de regressão automatizados em `just verify`.

### 5.2. Plano de Ativação Gradual (Canary Rollout)
1. **Fase 1 (Silent Rollout):** Deploy de todos os agentes em produção com `ENABLE_AUDIO_SUPPORT=false`. Áudios recebidos recebem resposta imediata de fallback de texto amigável.
2. **Fase 2 (Canary Brasília Automóveis):** Ativação de `ENABLE_AUDIO_SUPPORT=true` apenas para `customer-support-vehicles` para validação de volume de voz de clientes de concessionária com `gemini-3.8-flash`.
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
Faltou a feature flag explícita no ArgoCD. Só paralax-support e suporte veículos devem ter o audio habilitado por enquanto

## Mandatory Refinement Rules:
1. PRESERVE COMPLETED WORK: It is strictly forbidden to regress, remove, or modify the scope, public interface contracts, or acceptance criteria of already completed tasks (none).
2. UPDATE THE FILE DIRECTLY ON DISK: Rewrite/edit the file `SPEC-010-suporte-audio-como-feature.md` incorporating the requested changes:
   - Add or update Interface Contracts and Acceptance Criteria (Gherkin) for pending tasks or new waves.
   - Update the Context and Motivation section reflecting recent decisions.
   - Adjust YAML Frontmatter (`target_repositories`) if new subtasks or modules are added for upcoming waves.
   - Ensure the specification strictly complies with canonical ecosystem SDD format.
3. MANDATORY PROMPT GOVERNANCE (SPEC-PROMPT-01): If any target repository is an AI agent (`role: ai-agent`) or if the spec touches instructions, system prompts, or files like `prompts.py`, you MUST declare all affected prompts in YAML Frontmatter under `prompts:` with `name`, `target_repo`, `file`, `symbol`, and `description`. Document the exact prompt text in English in Section 3.5.
4. MANDATORY TECHNICAL FEASIBILITY AND SDK COMPATIBILITY: It is strictly prohibited to design architecture or public interface contracts assuming unsupported features in third-party or emerging SDKs (such as Google ADK, Gemini Live API, or WebSocket streaming) without verifying feasibility. For any real-time, audio, streaming, or emerging SDK integration: (a) Explicitly document required SDK dependencies, versions, and contract signatures in Section 3.1; (b) Specify protocol constraints (e.g., tool calling limitations in streaming mode, socket lifecycle, audio codecs); (c) If capability is not proven in codebase, specify a preliminary Wave 0 Spike task (`role: spike`) before feature implementation; (d) Define an architectural fallback in Section 3.1.