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
  - repo: paralax-ia/argocd
    wave: 3
    role: gitops
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
> **Decisão Arquitetural Crítica 1:** O modelo Gemini Live NÃO é compatível com webhooks de CRM; a inferência de áudio no CRM utiliza obrigatoriamente modelos Gemini Multimodais nativos turn-by-turn (`gemini-3.8-flash` e sua hierarquia de fallback)  
> **Decisão Arquitetural Crítica 2 (GitOps ArgoCD):** A ativação em produção é controlada explicitamente via manifests do ArgoCD. Nesta fase inicial, **apenas `customer-support-vehicles` e `paralax-support` terão a feature flag ativada (`ENABLE_AUDIO_SUPPORT="true"`)**, enquanto `anero-cafe-support` e `duo-dermato-support` permanecem explicitamente desativados (`ENABLE_AUDIO_SUPPORT="false"`)  
> **Arquitetura 12-Factor:** Zero arquivos de configuração no Git dos microsserviços; toda parametrização gerada exclusivamente via variáveis de ambiente declaradas nos manifests K8s/Kustomize do repositório GitOps  
> **Diretriz de Prompts (SPEC-PROMPT-01):** Prompts de sistema e instruções LLM estritamente redigidos em inglês  

---

## 1. Contexto e Motivação

Nos canais de atendimento digital operados pela Paralax IA (WhatsApp via Evolution CRM e mensageria omnicanal), uma parcela expressiva das interações dos usuários finais ocorre via notas de voz (áudios). Essa demanda manifesta-se nos diversos domínios de negócio da plataforma:
1. **Concessionária Brasília Automóveis (`customer-support-vehicles`):** Clientes enviando áudios sobre marcas, modelos, orçamentos, fotos e avaliação de seminovos.
2. **Suporte Corporativo Paralax (`paralax-support`):** Colaboradores e clientes descrevendo incidentes, dúvidas e suporte técnico por voz.
3. **Cafeteria Gourmet Anero Café (`anero-cafe-support`):** Clientes solicitando cardápio, grãos especiais, métodos de extração, encomendas e reservas por áudio.
4. **Clínica Dermatológica Duo Dermato (`duo-dermato-support`):** Pacientes detalhando sintomas, tratamentos e agendamentos de consultas via mensagens de voz.

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
   - Forçar uma conexão WebSocket Gemini Live dentro de um webhook HTTP turn-by-turn introduz complexidade excessiva, fragilidade no ciclo de vida de sockets, falhas em ambientes serverless/Kubernetes e custos desnecessários de streaming ativo para mensagens assíncronas estáticas.

2. **Incompatibilidade com o Runner do Google ADK e Chamadas a Ferramentas (Tool Calling):**
   - No runner oficial do Google ADK (`google-adk`), a orquestração conversacional de agentes utiliza o método padrão turn-by-turn `runner.run_async(session_id=..., content=...)` sobre a API Vertex AI `generateContent`.
   - Os modelos Gemini Live não operam como endpoints padrão `generateContent` na location `global` do Vertex AI para requisições com `Part.from_bytes`. Tentar invocar nomes de modelo Gemini Live via `generateContent` resulta em erros de modelo não suportado (`ValueError: Modelo inválido ou não suportado`) ou falhas de protocolo.

3. **A Solução Homologada: Modelos Gemini Multimodais Nativos (Gemini Flash):**
   - Os modelos **Gemini Multimodais** (`gemini-3.8-flash`, com fallbacks para `gemini-3.7-flash` e `gemini-2.5-flash`) são modelos nativamente multimodais que suportam ingestão direta de áudio bruto (`audio/ogg; codecs=opus`, `audio/mp4`, `audio/wav`, `audio/mpeg`) via `Part.from_bytes` na API REST/gRPC `generateContent`.
   - Eles oferecem suporte completo e robusto a **Tool Calling (Function Calling)** com parâmetros extraídos diretamente do áudio gravado, respeitam perfeitamente o ciclo de vida stateless do webhook `/run`, integram-se sem atritos ao runner do Google ADK e possuem validação completa na location `global` do Vertex AI.

---

### 1.2. O Desafio de Governança: Feature Flag Transversal (`ENABLE_AUDIO_SUPPORT`)

O suporte a áudio envolve custos computacionais e considerações contratuais por cliente e por canal. Nem todos os clientes ou canais de mensageria têm contrato ou perfil para processamento de voz.

Por isso, o suporte a áudio deve ser governado por uma **Feature Flag 12-Factor (`ENABLE_AUDIO_SUPPORT`)**, aplicável universalmente no código de todos os agentes:
- **Quando a Feature Flag está Desativada (`ENABLE_AUDIO_SUPPORT=False`, Padrão no Código):**
  - O agente **não deve** tentar submeter o áudio para o LLM (evitando custos e consumo desnecessário de cota).
  - O agente **não deve** retornar erro HTTP 500 nem descartar silenciosamente a mensagem do usuário.
  - O agente deve responder de forma cortês e imediata ao cliente no WhatsApp/CRM, notificando que o atendimento naquele canal é realizado por texto (ex: *"Desculpe, o atendimento por mensagens de voz está temporariamente desativado neste canal. Por favor, envie sua mensagem por texto para que eu possa te ajudar!"*).
- **Quando a Feature Flag está Ativada (`ENABLE_AUDIO_SUPPORT=True`):**
  - O webhook detecta partes de áudio (`part.is_audio()`).
  - O payload é convertido para GenAI `Content` multimodal via `Part.from_bytes(data=..., mime_type=...)`.
  - O roteamento dinâmico seleciona o modelo multimodal homologado de áudio (`gemini-3.8-flash`) com cascata de fallback (`gemini-3.7-flash` ➔ `gemini-2.5-flash`).
  - Mensagens puramente textuais continuam utilizando os modelos textuais padrão.

---

### 1.3. Governança GitOps e Estratégia de Ativação Gradual no ArgoCD

O código de todos os 4 agentes torna-se capaz de processar áudio através da feature flag, mas a **ativação operacional em produção é governada de forma estrita e centralizada pelo repositório GitOps (`paralax-ia/argocd`)**:

- **Fase Inicial (Canary Restrito):**
  - **`customer-support-v2-vehicles`:** `ENABLE_AUDIO_SUPPORT="true"` (habilitado para clientes de concessionária).
  - **`paralax-support`:** `ENABLE_AUDIO_SUPPORT="true"` (habilitado para chamados de suporte técnico da Paralax).
  - **`anero-cafe-support`:** `ENABLE_AUDIO_SUPPORT="false"` (explicitamente desativado nos manifests K8s).
  - **`duo-dermato-support`:** `ENABLE_AUDIO_SUPPORT="false"` (explicitamente desativado nos manifests K8s).
- **Racional de Negócio:**
  `customer-support-vehicles` e `paralax-support` possuem a maior volumetria e maturidade de testes operacionais no ecossistema. Mantendo `anero-cafe-support` e `duo-dermato-support` desligados nesta primeira fase, garante-se que os dois canais clínicos e comerciais operem sem riscos de cobranças ou alucinações de voz até a homologação completa dos modelos `gemini-3.8-flash`.

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
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        ONDA 3 (GITOPS / ARGO CD)                       │
│                           paralax-ia/argocd                            │
│  • `base/customer-support-v2-vehicles/deployment.yaml` e patch `prod`: │
│    - `ENABLE_AUDIO_SUPPORT: "true"`                                    │
│    - `AUDIO_MODEL: "gemini-3.8-flash"`                                 │
│    - `AUDIO_FALLBACK_MODELS: '["gemini-3.7-flash", "gemini-2.5-flash"]'│
│  • `base/paralax-support/deployment.yaml` e patch `prod`:              │
│    - `ENABLE_AUDIO_SUPPORT: "true"`                                    │
│    - `AUDIO_MODEL: "gemini-3.8-flash"`                                 │
│    - `AUDIO_FALLBACK_MODELS: '["gemini-3.7-flash", "gemini-2.5-flash"]'│
│  • `base/anero-cafe-support/deployment.yaml` e patch `prod`:           │
│    - `ENABLE_AUDIO_SUPPORT: "false"`                                   │
│    - `AUDIO_MODEL: "gemini-3.8-flash"`                                 │
│    - `AUDIO_FALLBACK_MODELS: '["gemini-3.7-flash", "gemini-2.5-flash"]'│
│  • `base/duo-dermato-support/deployment.yaml` e patch `prod`:          │
│    - `ENABLE_AUDIO_SUPPORT: "false"`                                   │
│    - `AUDIO_MODEL: "gemini-3.8-flash"`                                 │
│    - `AUDIO_FALLBACK_MODELS: '["gemini-3.7-flash", "gemini-2.5-flash"]'│
│  • Verificação de integridade via `just verify` (Kustomize + Pytest)   │
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

| Variável de Ambiente | Tipo | Padrão no Código | Valor no ArgoCD (Veículos & Support) | Valor no ArgoCD (Anero & Duo) | Descrição |
| :--- | :---: | :---: | :---: | :---: | :--- |
| `ENABLE_AUDIO_SUPPORT` | `bool` | `false` | `"true"` | `"false"` | Feature flag mestre de áudio. Controlada declarativamente no GitOps. |
| `AUDIO_MODEL` | `str` | `gemini-3.8-flash` | `gemini-3.8-flash` | `gemini-3.8-flash` | Modelo principal Gemini Multimodal para processamento turn-by-turn. Suporta alias `LIVE_AUDIO_MODEL`. |
| `AUDIO_FALLBACK_MODELS` | `list[str]` | `["gemini-3.7-flash", "gemini-2.5-flash"]` | `["gemini-3.7-flash", "gemini-2.5-flash"]` | `["gemini-3.7-flash", "gemini-2.5-flash"]` | Modelos secundários multimodais em caso de 429/503. Suporta alias `LIVE_AUDIO_FALLBACK_MODELS`. |
| `AUDIO_DISABLED_FALLBACK_MESSAGE` | `str` | *"Desculpe, o atendimento por mensagens de voz está temporariamente desativado..."* | (Padrão) | (Padrão) | Mensagem de cortesia retornada ao usuário final quando áudio for recebido com a flag desligada. |

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

### 3.6. Contratos GitOps e Declaração Explícita de Feature Flags no ArgoCD (`paralax-ia/argocd`)

No repositório central de GitOps (`paralax-ia/argocd`), as variáveis de ambiente devem ser declaradas explicitamente nos manifests base e patches de ambiente Kustomize, aplicando a regra estrita de ativação:

#### 1. Manifests de `customer-support-v2-vehicles` (Áudio Habilitado):
- **Arquivo Base:** `base/customer-support-v2-vehicles/deployment.yaml`
- **Patch Produção:** `prod/customer-support-v2-vehicles/patch-env.yaml`
```yaml
        - name: ENABLE_AUDIO_SUPPORT
          value: "true"
        - name: AUDIO_MODEL
          value: gemini-3.8-flash
        - name: AUDIO_FALLBACK_MODELS
          value: '["gemini-3.7-flash", "gemini-2.5-flash"]'
        - name: LIVE_AUDIO_MODEL
          value: gemini-3.8-flash
        - name: LIVE_AUDIO_FALLBACK_MODELS
          value: '["gemini-3.7-flash", "gemini-2.5-flash"]'
```

#### 2. Manifests de `paralax-support` (Áudio Habilitado):
- **Arquivo Base:** `base/paralax-support/deployment.yaml`
- **Patch Produção:** `prod/paralax-support/patch-env.yaml`
```yaml
        - name: ENABLE_AUDIO_SUPPORT
          value: "true"
        - name: AUDIO_MODEL
          value: gemini-3.8-flash
        - name: AUDIO_FALLBACK_MODELS
          value: '["gemini-3.7-flash", "gemini-2.5-flash"]'
        - name: LIVE_AUDIO_MODEL
          value: gemini-3.8-flash
        - name: LIVE_AUDIO_FALLBACK_MODELS
          value: '["gemini-3.7-flash", "gemini-2.5-flash"]'
```

#### 3. Manifests de `anero-cafe-support` (Áudio Desabilitado):
- **Arquivo Base:** `base/anero-cafe-support/deployment.yaml`
- **Patch Produção:** `prod/anero-cafe-support/patch-env.yaml`
```yaml
        - name: ENABLE_AUDIO_SUPPORT
          value: "false"
        - name: AUDIO_MODEL
          value: gemini-3.8-flash
        - name: AUDIO_FALLBACK_MODELS
          value: '["gemini-3.7-flash", "gemini-2.5-flash"]'
```

#### 4. Manifests de `duo-dermato-support` (Áudio Desabilitado):
- **Arquivo Base:** `base/duo-dermato-support/deployment.yaml`
- **Patch Produção:** `prod/duo-dermato-support/patch-env.yaml`
```yaml
        - name: ENABLE_AUDIO_SUPPORT
          value: "false"
        - name: AUDIO_MODEL
          value: gemini-3.8-flash
        - name: AUDIO_FALLBACK_MODELS
          value: '["gemini-3.7-flash", "gemini-2.5-flash"]'
```

---

## 4. Critérios de Aceitação (Gherkin)

### Cenário 1: Mensagem de voz recebida em agente com Feature Flag ATIVADA (`customer-support-vehicles` e `paralax-support`)
- **Dado** que o pod está rodando com as variáveis injetadas pelo ArgoCD:
  - `ENABLE_AUDIO_SUPPORT="true"`
  - `AUDIO_MODEL="gemini-3.8-flash"`
- **Quando** o webhook `/run` receber uma mensagem do CRM contendo parte do tipo `audio` (codec `audio/ogg; codecs=opus`)
- **Então** o sistema deve detectar `has_audio == True`
- **E** deve invocar `generate_crm_response` com `primary_model_override="gemini-3.8-flash"`
- **E** deve processar a instrução de voz turn-by-turn via `Part.from_bytes` com sucesso
- **E** deve retornar resposta textual coerente para o cliente via CRM API
- **E** deve registrar log com nível INFO indicando roteamento para o modelo multimodal `"gemini-3.8-flash"`.

### Cenário 2: Mensagem de voz recebida em agente com Feature Flag DESATIVADA (`anero-cafe-support` e `duo-dermato-support`)
- **Dado** que o pod está rodando com a variável injetada pelo ArgoCD:
  - `ENABLE_AUDIO_SUPPORT="false"`
- **Quando** o webhook `/run` receber uma mensagem do CRM contendo parte do tipo `audio`
- **Então** o sistema deve detectar `has_audio == True`
- **E** deve verificar que `enable_audio_support` é `False`
- **E** NÃO deve invocar o runner do LLM nem consumir cotas da API
- **E** deve despachar para o cliente via CRM API a mensagem amigável: *"Desculpe, o atendimento por mensagens de voz está temporariamente desativado neste canal. Por favor, envie sua mensagem por texto para que eu possa te ajudar!"*
- **E** deve retornar HTTP 200 para o CRM sem lançar exceção 500
- **E** deve registrar log de advertência (WARNING) indicando que o áudio foi interceptado e recusado pela feature flag.

### Cenário 3: Validação da Configuração Declarativa GitOps no ArgoCD (`paralax-ia/argocd`)
- **Dado** o repositório `paralax-ia/argocd`
- **Quando** a suíte `just verify` for executada
- **Então** a validação `kubectl kustomize base/customer-support-v2-vehicles` e `prod/customer-support-v2-vehicles` deve conter `ENABLE_AUDIO_SUPPORT` com valor `"true"`
- **E** a validação `kubectl kustomize base/paralax-support` e `prod/paralax-support` deve conter `ENABLE_AUDIO_SUPPORT` com valor `"true"`
- **E** a validação `kubectl kustomize base/anero-cafe-support` e `prod/anero-cafe-support` deve conter `ENABLE_AUDIO_SUPPORT` com valor `"false"`
- **E** a validação `kubectl kustomize base/duo-dermato-support` e `prod/duo-dermato-support` deve conter `ENABLE_AUDIO_SUPPORT` com valor `"false"`
- **E** todos os modelos de áudio devem apontar para `"gemini-3.8-flash"`, sem qualquer referência aos modelos Live.

### Cenário 4: Rejeição de Modelos Gemini Live no Contexto de CRM
- **Dado** que um operador tente configurar `AUDIO_MODEL="gemini-3.8-live"` ou qualquer modelo fora de `SUPPORTED_GLOBAL_MODELS`
- **Quando** o módulo de configuração carregar a classe `AgentModel`
- **Então** o `field_validator` deve lançar um `ValueError` explicativo informando que o modelo não é suportado na location global do Vertex AI para o CRM
- **E** deve impedir a inicialização com configuração de modelo incompatível.

### Cenário 5: Mensagem puramente textual recebida com Feature Flag de Áudio ATIVADA
- **Dado** que a feature flag `ENABLE_AUDIO_SUPPORT=true` está ativada no pod
- **Quando** o webhook `/run` receber uma mensagem contendo apenas texto (`has_audio == False`)
- **Então** o sistema deve selecionar o modelo textual padrão do agente (`model="gemini-3.8-flash"`)
- **E** deve orquestrar a resposta normalmente.

### Cenário 6: Mensagem combinada (áudio + texto) com Feature Flag ATIVADA
- **Dado** que `ENABLE_AUDIO_SUPPORT=true`
- **Quando** o webhook receber mensagem com uma parte de áudio e uma parte de texto explicativo
- **Então** o método `to_genai_content()` deve encapsular ambas as partes no mesmo objeto `Content(role="user")`
- **E** o modelo multimodal turn-by-turn `gemini-3.8-flash` deve ser acionado com o conteúdo multimodal completo.

### Cenário 7: Resiliência e Fallback sob Erro Transitório
- **Dado** que `ENABLE_AUDIO_SUPPORT=true`
- **E** o modelo principal `gemini-3.8-flash` retorna erro HTTP 429 (Rate Limit) ou 503 (Overloaded)
- **Quando** `generate_crm_response` executar a chamada
- **Então** o gerador deve alternar automaticamente para `gemini-3.7-flash`
- **E**, se persistir, para `gemini-2.5-flash`
- **E** o usuário deve receber a resposta normalmente sem quebra do fluxo conversacional.

### Cenário 8: Consistência Estrutural em Todos os Repositórios Afetados
- **Dado** os repositórios `paralax-evo-crm`, `customer-support-vehicles`, `anero-cafe-support`, `duo-dermato-support`, `paralax-support` e `argocd`
- **Quando** o comando `just verify` for executado na raiz de cada um dos spokes
- **Então** 100% dos testes, checagens de tipos e validações declarativas devem passar sem falhas
- **E** os testes unitários de regras de negócio devem possuir docstrings iniciando por `Business Rule:`.

---

## 5. Plano de Rollout e Compatibilidade

### 5.1. Estratégia de Versionamento SemVer e Ondas

- **Onda 1: `paralax-ia/paralax-evo-crm` (SDK):**
  - Incremento SemVer Minor (`v0.5.0` ou compatível) introduzindo constantes e contratos auxiliares de feature flag e mensagem de fallback.
  - Publicação no Google Cloud Artifact Registry.
- **Onda 2: Repositórios de Agentes de IA:**
  - Atualização do lockfile (`uv lock --upgrade-package paralax-evo-crm`).
  - Implementação do suporte a feature flag e roteamento para `gemini-3.8-flash` com testes unitários em `just verify`.
  - Construção e publicação das novas imagens Docker no Artifact Registry (`us-central1-docker.pkg.dev/paralax-infra/prod-docker-registry/...`).
- **Onda 3: Repositório GitOps (`paralax-ia/argocd`):**
  - Atualização dos manifests Kustomize com as tags de imagem atualizadas e as variáveis declaradas explicitamente:
    - `ENABLE_AUDIO_SUPPORT="true"` em `customer-support-v2-vehicles` e `paralax-support`.
    - `ENABLE_AUDIO_SUPPORT="false"` em `anero-cafe-support` e `duo-dermato-support`.
  - Validação estática com `just verify` no repositório `argocd`.
  - Sincronização automática via ArgoCD Root App nos clusters de produção (`namespace: crm`).

### 5.2. Plano de Ativação Gradual (Canary Phased Rollout)
1. **Fase 1 (Produção Piloto):** Sincronização do ArgoCD com áudio ativado **exclusivamente** para `customer-support-vehicles` e `paralax-support`. Monitoramento de telemetria no Langfuse (latência de inferência de áudio, consumo de tokens multimodais e erros 429/503).
2. **Fase 2 (Homologação Anero Café):** Alteração declarativa no ArgoCD de `ENABLE_AUDIO_SUPPORT="true"` para `anero-cafe-support` em staging/canary.
3. **Fase 3 (Homologação Duo Dermato):** Ativação de `ENABLE_AUDIO_SUPPORT="true"` para `duo-dermato-support` após validação da conformidade médica e ética de voz.
