---
spec_id: SPEC-009
title: "Suporte a Instruções de Áudio no Agente de Veículos via Modelo Gemini Live"
product:
  - customer-support-vehicles
  - paralax-platform
capability: conversational-ai-agent
scope: product-specific
bounded_context: "IA Conversacional Multimodal & Veículos (Core Subdomain)"
origin_module: customer-support-vehicles
target_repositories:
  - repo: paralax-ia/paralax-evo-crm
    wave: 1
    role: sdk
  - repo: paralax-ia/customer-support-vehicles
    wave: 2
    role: ai-agent
prompts:
  - "vehicles/vehicle_search_agent_instruction"
status: APPROVED
---

# SPEC-009: Suporte a Instruções de Áudio no Agente de Veículos via Modelo Gemini Live

> **Product:** [`customer-support-vehicles`](../products/customer-support-vehicles.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Product-Specific (Atendimento da Concessionária Brasília Automóveis)  
> **Bounded Context:** IA Conversacional Multimodal & Veículos (Core Subdomain)  
> **Status:** DRAFT  
> **Autor:** Eduardo F. Santos  
> **Data de Criação:** 2026-10-31  
> **Arquitetura 12-Factor:** Zero arquivos de configuração salvos no Git; toda configuração é gerada exclusivamente a partir de variáveis de ambiente  
> **Diretriz de Prompts:** Prompts de sistema e templates de instrução para LLM devem ser estritamente redigidos em inglês  
> **Regra Mandatória de Áudio:** Para mensagens contendo instruções em áudio, utilizar obrigatoriamente o modelo Gemini Live  
> **Repositórios Impactados:**  
> - `paralax-ia/paralax-evo-crm` (Onda 1 - SDK Compartilhado: Modelos Pydantic Multimodais, Parser de Áudio em Part.from_bytes e Suporte a Seleção Dinâmica de Modelo em generate_crm_response)  
> - `paralax-ia/customer-support-vehicles` (Onda 2 - Agente de Veículos: Rota /run com Detecção de Áudio, Roteamento para Gemini Live, Configurações 12-Factor e Instruções da Agente Isa)

---

## 1. Contexto e Motivação

No atendimento digital da concessionária e revenda de veículos **Brasília Automóveis** via WhatsApp, uma parcela significativa de clientes em potencial envia mensagens de voz (áudios) em vez de texto. Os clientes utilizam áudios para formular perguntas, expor preferências e dar comandos como:
- *"Oi, Isa! Estou procurando um Corolla ou Civic automático entre 2020 e 2022. Vocês têm algum no estoque e aceitam meu usado na troca?"*
- *"Qual o valor daquele Renegade que está anunciado no site? Tem garantia de motor e câmbio?"*
- *"Consegue simular um financiamento com 30 mil de entrada para um SUV compacto?"*

### O Desafio Arquitetural e Limitações Atuais
1. **Descarte de Mensagens de Voz no Webhook do CRM:**
   Atualmente, o roteador do webhook do CRM (`vehicles/routers/crm.py`) processa estritamente partes de texto (`if part.type == "text" and part.text:`), descartando ou ignorando partes do tipo `audio`. Isso impede a compreensão da solicitação do cliente que envia áudio, deixando o usuário sem resposta ou exigindo intervenção manual desnecessária.
2. **Regra de Negócio Mandatória: Uso Obrigatório do Modelo Gemini Live para Áudio:**
   A diretriz oficial da arquitetura exige que: **"Para áudio sempre usar o modelo live do gemini"**.
   - A família de modelos **Gemini Live** (liderada pelo modelo oficial de produção **`gemini-3.8-live`** e seu companheiro de raciocínio estendido **`gemini-3.8-live-extended-thinking`**, com fallback multimodal para `gemini-2.0-flash`) foi construída com capacidades nativas de compreensão multimodal de áudio/voz de baixíssima latência e alta precisão acústica.
   - O processamento de áudio com Gemini Live opera de ponta a ponta ingerindo o áudio bruto (`Part.from_bytes` com mime-types como `audio/ogg; codecs=opus`, `audio/mp4`, `audio/wav`, `audio/mpeg`), eliminando a necessidade de pipelines intermediários frágeis de transcrição Speech-to-Text (STT) desacoplados.
   - Sempre que uma mensagem recebida contiver instrução em áudio, o agente deve obrigatoriamente rotear a inferência para o modelo Gemini Live configurado (`gemini-3.8-live`).
   - Para mensagens puramente textuais, o agente preserva o uso dos modelos textuais padrão (`gemini-3.8-flash` / fallbacks).
3. **Resiliência e Fallback Transversal:**
   Em caso de instabilidade temporária (erros 429 ou 503) no modelo Live principal (`gemini-3.8-live`), o gerador de respostas deve efetuar fallback automático para modelos Live secundários e de contingência (`gemini-3.8-live-extended-thinking` ➔ `gemini-2.0-flash`), sem lançar exceção 500 para o CRM.

### Diretrizes de Engenharia e Arquitetura
- **Prompts Estritamente em Inglês (English-Only Prompts):** Todas as instruções de sistema da agente em `vehicles/prompts.py` e eventuais templates de prompt para o LLM devem ser redigidos exclusivamente em inglês, assegurando precisão, consistência e conformidade estrita aos padrões corporativos.
- **Princípio 12-Factor (Zero Config no Git):** Nomes de modelos (`LIVE_AUDIO_MODEL`, `LIVE_AUDIO_FALLBACK_MODELS`), timeouts e configurações de credenciais devem ser parametrizados exclusivamente via variáveis de ambiente (`os.environ` / Pydantic Settings), com bloqueio estrito em `.gitignore` para proibir arquivos `.env` ou `.yaml` versionados no Git.
- **Padrões de Código Python (PEP 8, Google Docstrings, Sem Funções Aninhadas):** O código deve seguir estritamente as diretrizes corporativas, sem funções internas/aninhadas, sem blocos `try...except` aninhados ou em imports, e com docstrings Google em todas as funções e classes.

---

## 2. Escopo e Repositórios Afetados

```
┌────────────────────────────────────────────────────────────────────────┐
│                       ONDA 1 (PENDENTE - TASK-1)                       │
│                       paralax-ia/paralax-evo-crm                       │
│  • Extensão de `CrmMessagePart` e `CrmMessage` em `models.py` para     │
│    suportar partes de áudio (`media_url`, `data` base64, `mime_type`)  │
│  • Funções auxiliares `is_audio()` e `has_audio()`                     │
│  • Utilitário `convert_crm_part_to_genai_part()` montando             │
│    `Part.from_bytes(data=..., mime_type=...)`                          │
│  • Atualização de `generate_crm_response()` em `generator.py` para     │
│    suportar modelo ativo dinâmico e lista de fallback customizada      │
│  • Suíte completa de testes unitários com docstrings `Business Rule:`  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                       ONDA 2 (PENDENTE - TASK-2)                       │
│                 paralax-ia/customer-support-vehicles                   │
│  • Atualização de `vehicles/config.py`:                                │
│    - Adição de modelos Live em `SUPPORTED_GLOBAL_MODELS`               │
│    - Configuração 12-Factor `LIVE_AUDIO_MODEL` e                       │
│      `LIVE_AUDIO_FALLBACK_MODELS`                                      │
│  • Atualização de `vehicles/routers/crm.py`:                           │
│    - Detecção de partes de áudio na rota `/run`                        │
│    - Construção de `Content` multimodal com áudio                      │
│    - Roteamento estrito para o modelo Gemini Live quando áudio existir │
│  • Atualização de `vehicles/prompts.py` em inglês para instruções de   │
│    voz e áudio                                                         │
│  • Suíte de testes unitários em `tests/unit/` com `Business Rule:`     │
└────────────────────────────────────────────────────────────────────────┘
```

- [ ] **[Onda 1] `paralax-ia/paralax-evo-crm` (`task-1`):**
  - Atualizar `paralax/evo/crm/models.py`:
    - Adicionar campos opcionais em `CrmMessagePart`: `media_url: str | None = None`, `data: str | None = None` (base64 string) e `mime_type: str | None = None`.
    - Implementar método `is_audio() -> bool` em `CrmMessagePart`, retornando True se `type == "audio"` ou se `mime_type` iniciar com `"audio/"`.
    - Implementar método `has_audio() -> bool` em `CrmMessage`, retornando True se qualquer part for de áudio.
    - Implementar função `convert_crm_part_to_genai_part(part: CrmMessagePart, timeout_seconds: float = 10.0) -> Part` que converte texto para `Part.from_text` e áudio (base64 ou download via `media_url`) para `Part.from_bytes(data=raw_bytes, mime_type=clean_mime)`.
    - Implementar função `build_genai_content_from_crm_message(message: CrmMessage) -> tuple[Content, bool]` retornando o objeto `Content` consolidado e um booleano `has_audio`.
  - Atualizar `paralax/evo/crm/generator.py`:
    - Atualizar a assinatura de `generate_crm_response()` para aceitar `primary_model_override: str | None = None` e `fallback_models_override: list[str] | None = None`.
    - Quando um override de modelo for informado (como o modelo Gemini Live para requisições de áudio), utilizá-lo como modelo prioritário e aplicar a lista correspondente de fallbacks.
  - Testes unitários em `tests/paralax/evo/crm/`:
    - Validar detecção de áudio, decodificação de base64, conversão para `Part.from_bytes` e passagem do modelo prioritário ao generator.

- [ ] **[Onda 2] `paralax-ia/customer-support-vehicles` (`task-2`):**
  - Atualizar a dependência `paralax-evo-crm` no projeto.
  - Atualizar `vehicles/config.py`:
    - Adicionar os identificadores do Gemini Live à lista `SUPPORTED_GLOBAL_MODELS` (ex: `"gemini-3.8-live"`, `"gemini-3.8-live-extended-thinking"`, `"gemini-2.0-flash"`).
    - Adicionar as configurações 12-Factor em `AgentModel` / `Config`:
      - `LIVE_AUDIO_MODEL: str = Field(default="gemini-3.8-live", validation_alias="LIVE_AUDIO_MODEL")`
      - `LIVE_AUDIO_FALLBACK_MODELS: list[str] = Field(default=["gemini-3.8-live-extended-thinking", "gemini-2.0-flash"], validation_alias="LIVE_AUDIO_FALLBACK_MODELS")`
  - Atualizar `vehicles/routers/crm.py`:
    - Na rota POST `/run`, processar `request.params.message` utilizando `build_genai_content_from_crm_message`.
    - Se `has_audio` for True:
      - Selecionar obrigatoriamente o modelo Gemini Live (`config.agent_settings.live_audio_model`) e seus fallbacks (`config.agent_settings.live_audio_fallback_models`).
      - Passar os overrides para `generate_crm_response()`, garantindo que toda instrução em áudio seja processada pelo modelo Live do Gemini.
    - Se `has_audio` for False:
      - Manter o fluxo padrão com o modelo de texto (`config.agent_settings.model`) e fallbacks de texto.
  - Atualizar `vehicles/prompts.py`:
    - Adicionar seção em inglês estrito `<audio_and_voice_instructions>` instruindo a agente Isa a processar perguntas e comandos recebidos via áudio mantendo respostas concisas, cordiais e formatadas para WhatsApp.
  - Criar testes unitários em `tests/unit/test_crm_audio.py`:
    - Testar requisição com áudio em base64 resultando na chamada do modelo Gemini Live.
    - Testar requisição mista (áudio + texto) resultando na chamada do modelo Gemini Live.
    - Testar requisição puramente textual preservando o modelo textual padrão.
    - Testar fallback do modelo Live em caso de erro 429/503.

---

## 3. Contratos de Interface

### 3.1. Modelos de Domínio Multimodal (`paralax-evo-crm` — `paralax/evo/crm/models.py`)

```python
import base64
from typing import Any
import httpx
from pydantic import BaseModel, ConfigDict, Field
from google.genai.types import Content, Part


class CrmMessagePart(BaseModel):
    """Representa uma parte individual da mensagem do CRM (texto, áudio, anexo)."""

    type: str = Field(description="Tipo da parte: 'text', 'audio', 'image', etc.")
    text: str | None = Field(default=None, description="Conteúdo textual se type == 'text'.")
    media_url: str | None = Field(default=None, description="URL pública ou acessível do arquivo de mídia.")
    data: str | None = Field(default=None, description="Payload binário codificado em base64 se aplicável.")
    mime_type: str | None = Field(default=None, description="MIME type da mídia (ex: 'audio/ogg', 'audio/mp4', 'audio/wav').")
    model_config = ConfigDict(extra="allow")

    def is_audio(self) -> bool:
        """Determina se a parte corresponde a um conteúdo de áudio."""
        if self.type == "audio":
            return True
        if self.mime_type and self.mime_type.lower().startswith("audio/"):
            return True
        return False

    def to_genai_part(self, timeout_seconds: float = 10.0) -> Part:
        """Converte a parte do CRM em uma Part utilizável pelo Google GenAI / ADK."""
        if self.is_audio():
            clean_mime = self.mime_type or "audio/ogg"
            if self.data:
                raw_bytes = base64.b64decode(self.data)
                return Part.from_bytes(data=raw_bytes, mime_type=clean_mime)
            if self.media_url:
                with httpx.Client(timeout=timeout_seconds) as client:
                    resp = client.get(self.media_url)
                    resp.raise_for_status()
                    return Part.from_bytes(data=resp.content, mime_type=clean_mime)
            raise ValueError("Parte de áudio sem 'data' (base64) nem 'media_url'.")
        
        return Part.from_text(text=self.text or "")


class CrmMessage(BaseModel):
    """Representa a mensagem completa enviada pelo CRM via webhook."""

    role: str
    parts: list[CrmMessagePart]
    messageId: str | None = None
    model_config = ConfigDict(extra="allow")

    def has_audio(self) -> bool:
        """Verifica se alguma parte da mensagem contém áudio."""
        return any(part.is_audio() for part in self.parts)

    def to_genai_content(self, timeout_seconds: float = 10.0) -> tuple[Content, bool]:
        """Converte a mensagem completa para Google GenAI Content e indica presença de áudio.

        Returns:
            Tupla contendo o objeto Content(role="user", parts=[...]) e o booleano has_audio.
        """
        genai_parts: list[Part] = []
        has_audio = False
        for part in self.parts:
            if part.is_audio():
                has_audio = True
                genai_parts.append(part.to_genai_part(timeout_seconds=timeout_seconds))
            elif part.type == "text" and part.text and part.text.strip():
                genai_parts.append(Part.from_text(text=part.text))

        if not genai_parts:
            genai_parts.append(Part.from_text(text=""))

        return Content(role="user", parts=genai_parts), has_audio
```

---

### 3.2. Contrato de Orquestração com Suporte a Modelo Dinâmico (`paralax-evo-crm` — `generator.py`)

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
    fallback_models: list[str] | None = None,
    redis_client: Any | None = None,
    primary_model_override: str | None = None,
    fallback_models_override: list[str] | None = None,
) -> tuple[str, str]:
    """Gera resposta do agente suportando seleção dinâmica de modelo e fallback para áudio.

    Args:
        primary_model_override: Quando informado (ex: modelo Gemini Live para áudio),
            sobrepõe o modelo padrão do agente durante a execução.
        fallback_models_override: Lista ordenada de modelos de fallback específicos
            para a execução em curso (ex: modelos Live secundários).
    """
    ...
```

---

### 3.3. Configuração 12-Factor de Modelos no Agente (`vehicles/config.py`)

Configurações geradas dinamicamente exclusivamente a partir de variáveis de ambiente:

```python
SUPPORTED_GLOBAL_MODELS: list[str] = [
    "gemini-3.8-live",
    "gemini-3.8-live-extended-thinking",
    "gemini-3.8-flash",
    "gemini-3.7-flash",
    "gemini-3.6-flash",
    "gemini-3.5-flash",
    "gemini-2.5-flash",
    "gemini-2.0-flash",
]


class AgentModel(BaseModel):
    """Configurações dos modelos do agente com validação estrita."""

    name: str = Field(default="vehicle_search_agent")
    model: str = Field(default="gemini-3.8-flash")
    fallback_models: list[str] = Field(
        default=["gemini-3.8-flash", "gemini-3.7-flash", "gemini-3.6-flash"]
    )
    live_audio_model: str = Field(
        default="gemini-3.8-live",
        description="Modelo Gemini Live oficial para processamento de áudio.",
    )
    live_audio_fallback_models: list[str] = Field(
        default=["gemini-3.8-live-extended-thinking", "gemini-2.0-flash"],
        description="Modelos Gemini Live de contingência e fallback de áudio.",
    )
    enable_heartbeat: bool = Field(default=True)
```

---

### 3.4. Roteamento de Áudio no Webhook CRM (`vehicles/routers/crm.py`)

Na rota `/run`:

```python
@router.post("/run")
async def run_crm(request: CrmRequest):
    if request.method != "message/send":
        raise HTTPException(status_code=400, detail="Method not supported")

    content, has_audio = request.params.message.to_genai_content()
    
    # Regra Mandatória: Para áudio sempre usar o modelo live do gemini
    if has_audio:
        primary_model = config.agent_settings.live_audio_model
        fallback_models = config.agent_settings.live_audio_fallback_models
        logger.info(
            "Audio instruction detected in CRM message. Routing to Gemini Live model: '%s'",
            primary_model,
        )
    else:
        primary_model = config.agent_settings.model
        fallback_models = config.agent_settings.fallback_models

    final_text, vertex_session_id = await generate_crm_response(
        runner=runner,
        session_service=session_service,
        user_id=user_id,
        vertex_session_id=vertex_session_id,
        content=content,
        context_id=context_id,
        use_redis_mapping=bool(use_redis_mapping),
        redis_client=redis_client,
        timeout_seconds=int(config.AI_CALL_TIMEOUT_SECONDS),
        crm_client=crm_api,
        heartbeat_messages=HEARTBEAT_MESSAGES,
        enable_heartbeat=config.agent_settings.enable_heartbeat,
        primary_model_override=primary_model,
        fallback_models_override=fallback_models,
    )
    ...
```

---

### 3.5. Instruções da Agente Isa em Inglês (`vehicles/prompts.py`)

Seção adicionada em `vehicles/prompts.py`, estritamente em inglês:

```markdown
<audio_and_voice_instructions>
The customer may communicate by sending voice messages and audio recordings via WhatsApp.
When processing an audio message:
1. Listen carefully to the transcribed audio query to identify the customer's intent (e.g., searching for a car, asking about trade-in, financing, or warranty).
2. Use the inventory search tools (`vehicle_search`, `get_vehicle_details`, `inspect_external_vehicle_ad`) as needed to verify vehicle availability.
3. Formulate your response in Portuguese (PT-BR) following the exact tone, constraints, and WhatsApp formatting rules defined in <response_style_and_formatting>.
4. Do not mention technical audio processing details to the user; address their voice inquiry with immediate, practical assistance.
</audio_and_voice_instructions>
```

---

## 4. Critérios de Aceitação (Gherkin)

### Cenário 1: Instrução de Busca em Áudio Processada Obrigatoriamente pelo Modelo Gemini Live
- **Dado** que um cliente envia uma mensagem de voz no WhatsApp contendo uma solicitação de busca (ex: *"Vocês têm Corolla 2021 no estoque?"*)
- **E** o payload do CRM webhook contém uma parte de áudio com `type="audio"` e `data` em base64 (MIME `audio/ogg; codecs=opus`)
- **Quando** o endpoint `/run` processar a requisição
- **Então** o áudio deve ser convertido em `Part.from_bytes` e a flag `has_audio` deve ser avaliada como `True`
- **E** a execução deve selecionar obrigatoriamente o modelo Gemini Live configurado (`LIVE_AUDIO_MODEL="gemini-3.8-live"`)
- **E** a resposta final deve conter as informações de estoque formatadas para WhatsApp sem erros 500.

### Cenário 2: Mensagem Mista de Áudio e Texto Roteada para o Modelo Gemini Live
- **Dado** que a mensagem do cliente contenha tanto uma gravação de áudio quanto uma legenda ou texto complementar
- **Quando** a mensagem for processada pelo roteador do CRM
- **Então** a presença da parte de áudio deve acionar obrigatoriamente o roteamento para o modelo Gemini Live
- **E** o `Content` submetido ao modelo deve conter tanto a parte de áudio (`Part.from_bytes`) quanto a parte de texto (`Part.from_text`).

### Cenário 3: Mensagem Exclusivamente Textual Preservando Modelo Textual Padrão
- **Dado** que o cliente envia apenas mensagem de texto (sem partes de áudio)
- **Quando** a mensagem for processada pela rota `/run`
- **Então** a flag `has_audio` deve ser avaliada como `False`
- **E** a execução deve utilizar o modelo textual padrão configurado (`model="gemini-3.8-flash"`), sem acionar o modelo Live.

### Cenário 4: Fallback Transparente em Caso de Indisponibilidade Transitória do Modelo Live
- **Dado** que uma requisição com áudio seja recebida e o modelo Gemini Live principal retorne erro de cota ou indisponibilidade (HTTP 429 ou 503)
- **Quando** o gerador de resposta `generate_crm_response` capturar o erro
- **Então** o sistema deve acionar automaticamente o modelo Live secundário definido em `LIVE_AUDIO_FALLBACK_MODELS` (ex: `gemini-3.8-live-extended-thinking` / `gemini-2.0-flash`)
- **E** responder ao cliente de forma transparente sem falha irrecuperável.

### Cenário 5: Resiliência contra Áudio Corrompido ou Falha de Download
- **Dado** que uma parte de áudio possua URL inacessível ou base64 inválido
- **Quando** o parser tentar converter a mídia
- **Então** o erro deve ser capturado de forma tolerante, logando advertência estruturada
- **E** o agente deve retornar uma resposta amigável orientando o cliente a reenviar a mensagem, sem derrubar o serviço com exceção HTTP 500.

### Cenário 6: Conformidade 12-Factor e Ausência de Configurações no Git
- **Dado** os repositórios `paralax-evo-crm` e `customer-support-vehicles`
- **Quando** as configurações forem inicializadas
- **Então** `LIVE_AUDIO_MODEL` e `LIVE_AUDIO_FALLBACK_MODELS` devem ser resolvidas exclusivamente a partir de variáveis de ambiente
- **E** nenhum arquivo de configuração (`.env`, `.yaml`, `.json`) deve estar versionado no Git.

### Cenário 7: Padronização Mandatória de Prompts de Sistema em Inglês
- **Dado** o arquivo de instruções `vehicles/prompts.py`
- **Quando** a seção `<audio_and_voice_instructions>` for analisada
- **Então** todas as instruções de sistema e diretrizes para o LLM devem estar redigidas estritamente em inglês.

---

## 5. Plano de Rollout e Compatibilidade

1. **Sequência de Implementação por Ondas:**
   - **Onda 1 (`paralax-ia/paralax-evo-crm`):**
     1. Extensão de `CrmMessagePart` e `CrmMessage` em `models.py` com métodos `is_audio()`, `has_audio()` e conversão para GenAI `Part.from_bytes`.
     2. Suporte a overrides de modelo em `generator.py`.
     3. Testes unitários com docstrings `Business Rule:` em `tests/paralax/evo/crm/test_models.py`.
     4. Validação com `just verify`, merge e publicação SemVer minor no Artifact Registry.
   - **Onda 2 (`paralax-ia/customer-support-vehicles`):**
     1. Atualização do lockfile para a versão atualizada de `paralax-evo-crm`.
     2. Configuração de `LIVE_AUDIO_MODEL` e `LIVE_AUDIO_FALLBACK_MODELS` em `vehicles/config.py`.
     3. Integração do roteamento de áudio em `vehicles/routers/crm.py`.
     4. Atualização das instruções da agente Isa em inglês em `vehicles/prompts.py`.
     5. Suíte de testes unitários em `tests/unit/test_crm_audio.py` e validação com `just verify`.
2. **Compatibilidade e Rollback:**
   - Mudança 100% retrocompatível: clientes que enviarem mensagens de texto continuarão com o fluxo e modelos idênticos aos atuais.
   - Caso seja necessário desabilitar temporariamente o processamento de áudio, basta que o agente trate partes de áudio como texto informativo ou ajuste as variáveis de ambiente sem interrupção de serviço.
