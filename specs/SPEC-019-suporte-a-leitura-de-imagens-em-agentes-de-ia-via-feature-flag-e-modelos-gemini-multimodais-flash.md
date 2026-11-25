---
spec_id: SPEC-019
title: "Suporte a Leitura de Imagens em Agentes de IA via Feature Flag e Modelos Gemini Multimodais (Flash)"
product:
  - paralax-platform
  - paralax-support
  - anero-cafe-support
capability: conversational-ai-agent
scope: platform
bounded_context: "Orquestração Conversacional Multimodal & Agentes de IA (Core Subdomain)"
origin_module: paralax-evo-crm
target_repositories:
  - repo: paralax-ia/paralax-evo-crm
    wave: 1
    role: sdk
  - repo: paralax-ia/paralax-support
    wave: 2
    role: ai-agent
  - repo: paralax-ia/anero-cafe-support
    wave: 2
    role: ai-agent
  - repo: paralax-ia/argocd
    wave: 3
    role: gitops
prompts:
  - name: paralax/support
    target_repo: paralax-ia/paralax-support
    file: support/prompts.py
    symbol: INSTRUCTION
    description: "System instructions for Paralax IT support agent, supporting user screenshots and image attachments when image feature flag is enabled."
  - name: anero_cafe/instruction
    target_repo: paralax-ia/anero-cafe-support
    file: anero_cafe/prompts.py
    symbol: INSTRUCTION
    description: "System instructions for Anero Cafe agent, supporting customer photos of coffee packaging, labels, menus and receipts when image feature flag is enabled."
status: APPROVED
---

# SPEC-019: Suporte a Leitura de Imagens em Agentes de IA via Feature Flag e Modelos Gemini Multimodais (Flash)

> **Product:** [`paralax-platform`](../products/paralax-platform.yaml) | [`paralax-support`](../products/paralax-support.yaml) | [`anero-cafe-support`](../products/anero-cafe-support.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Platform (Habilitável por agente via Feature Flag)  
> **Bounded Context:** Orquestração Conversacional Multimodal & Agentes de IA (Core Subdomain)  
> **Decisão Arquitetural Crítica 1 (Zero Customizações no CRM):** O CRM (`evo-ai-crm-community`) e o runtime Go (`evo-bot-runtime`) já possuem a esteira completa de ingestão, download, validação SSRF e despacho de mídia via partes de arquivo A2A JSON-RPC 2.0 (EVO-2179 e EVO-2180). Nenhuma alteração de código é necessária no CRM.  
> **Decisão Arquitetural Crítica 2 (Governança por Feature Flag 12-Factor):** A funcionalidade de leitura de imagens é estritamente opt-in por agente via variável de ambiente `ENABLE_IMAGE_SUPPORT`. Nos ambientes de produção do ArgoCD, apenas `paralax-support` e `anero-cafe-support` terão a flag ativada inicialmente.  
> **Decisão Arquitetural Crítica 3 (Modelo Multimodal Turn-by-Turn):** A inferência visual utiliza o modelo Gemini Multimodal de produção (`gemini-3.8-flash`) com fallbacks nativos (`gemini-3.7-flash`, `gemini-2.5-flash`), ingerindo partes binárias brutas via `Part.from_bytes(data=..., mime_type=...)`.  
> **Diretriz de Prompts (SPEC-PROMPT-01):** Prompts de sistema e instruções de visão estritamente em inglês.  

---

## 1. Contexto e Motivação

Nos canais de atendimento digital operados pela Paralax IA (WhatsApp via Evolution CRM), os usuários frequentemente enviam imagens para ilustrar suas necessidades:
1. **Suporte Corporativo Paralax (`paralax-support`):** Colaboradores e clientes enviam capturas de tela (*screenshots*) de erros de software, logs de terminal, diagramas de rede ou topologias, notas fiscais e relatórios técnicos.
2. **Cafeteria Gourmet Anero Café (`anero-cafe-support`):** Clientes enviam fotos de embalagens de café para saber torra ou granulometria, cardápios físicos, fotos de métodos de extração (V60, Prensa Francesa, Espresso), comprovantes de pagamento e cupons.

### 1.1. O Gargalo Identificado no Ecossistema
- **CRM e Runtime Prontos:** O CRM (`evo-ai-crm-community`) já armazena anexos no ActiveStorage e repassa os metadados no webhook para o `evo-bot-runtime`. O runtime em Go (`evo-bot-runtime`) já baixa o arquivo sob limite seguro de bytes, valida a URL na allowlist de mídia e codifica a imagem em Base64 no envelope JSON-RPC:
  ```json
  "parts": [
    {"type": "text", "text": "Veja este erro:"},
    {"type": "file", "file": {"name": "error.png", "mimeType": "image/png", "bytes": "<BASE64>"}}
  ]
  ```
- **Descarte Silencioso no SDK Python (`paralax-evo-crm`):** Em `models.py`, o método `CrmMessage.to_genai_content()` processa apenas partes de texto ou áudio. Partes com `type == "image"` ou `file.mimeType` do tipo `image/*` são ignoradas, chegando ao agente apenas como texto (ou vazias).
- **Falta de Feature Flag nos Agentes:** Os agentes precisam interceptar imagens antes do envio ao LLM caso a flag `ENABLE_IMAGE_SUPPORT` esteja desativada, devolvendo uma resposta amigável sem incorrer em custos de cota e tokens de visão.

---

## 2. Metas, Não-Metas e Anti-Metas

### Metas (Goals)
- Permitir que os agentes `paralax-support` e `anero-cafe-support` interpretem imagens enviadas pelos usuários via WhatsApp.
- Preservar integridade e retrocompatibilidade com requisições existentes de texto e áudio no SDK `paralax-evo-crm`.
- Permitir ativação/desativação granular por agente via `ENABLE_IMAGE_SUPPORT` (padrão `False` no código; `True` via GitOps nos 2 agentes piloto).
- Fornecer fallback amigável quando a feature flag de imagem estiver desativada no agente, sem gerar erros 500 para o CRM.
- Fornecer instruções especializadas em inglês nos prompts de sistema para análise de imagens técnicas (TI) e gastronômicas (Café).

### Não-Metas (Non-Goals)
- Habilitar imagens em `customer-support-vehicles` ou `duo-dermato-support` nesta fase (permanecem desativados por governança).
- Realizar geração ou edição de imagens pelo agente (o foco é estritamente **leitura e interpretação de imagens recebidas**).
- Criar rotas ou serviços adicionais de OCR externo (o Gemini 3.8 Flash realiza visão computacional nativa de ponta a ponta).

### Anti-Metas (Anti-Goals)
- **NÃO** alterar qualquer linha de código no CRM (`evo-ai-crm-community`).
- **NÃO** aplicar `pip install -e` ou symlinks entre repositórios (respeito estrito às Ondas Topológicas de CI/CD).
- **NÃO** utilizar blocos `try...except` aninhados ou funções aninhadas no código Python.

---

## 3. Escopo e Topologia de Ondas

```
┌────────────────────────────────────────────────────────────────────────┐
│                       ONDA 1: SDK COMPARTILHADO                        │
│                       paralax-ia/paralax-evo-crm                       │
│  • Extensão de `CrmMessagePart`:                                       │
│    - Método `is_image() -> bool` (type == "image" ou mime "image/*")   │
│    - Atualização de `to_genai_part()` para converter imagens para      │
│      `Part.from_bytes(data=raw_bytes, mime_type=clean_mime)`           │
│  • Extensão de `CrmMessage`:                                           │
│    - Método `has_image() -> bool`                                      │
│    - Atualização de `to_genai_content()` para incluir parts de imagem  │
│      no `Content(role="user")` preservando retorno retrocompatível     │
│  • Suíte completa de testes unitários com TDD e docstrings Business    │
│  • Publicação de nova versão no Artifact Registry                      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                       ONDA 2: AGENTES PILOTO                           │
│              paralax-support  &  anero-cafe-support                    │
│  • Atualização da dependência `paralax-evo-crm` no pyproject.toml      │
│  • Configuração 12-Factor em `config.py`:                              │
│    - `ENABLE_IMAGE_SUPPORT: bool = False`                              │
│    - `IMAGE_DISABLED_FALLBACK_MESSAGE: str = "..."`                    │
│    - `MAX_IMAGE_SIZE_BYTES: int = 15728640`                            │
│  • Webhook `/run` em `routers/crm.py`:                                 │
│    - Verificação de `has_image`: se desativada, despacha fallback      │
│      amigável via crm_api e finaliza sem chamar LLM                   │
│    - Se ativada, envia o `Content` multimodal ao Gemini 3.8 Flash      │
│  • Atualização de `prompts.py` (em inglês):                            │
│    - `<image_analysis_instructions>` customizado por domínio           │
│  • Suíte de testes unitários em `tests/unit/test_crm_image.py`         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                       ONDA 3: ENTREGA GITOPS                           │
│                         paralax-ia/argocd                              │
│  • Atualização declarativa nos overlays Kustomize (`prod/`):           │
│    - `apps/prod-paralax-support`: `ENABLE_IMAGE_SUPPORT="true"`        │
│    - `apps/prod-anero-cafe-support`: `ENABLE_IMAGE_SUPPORT="true"`     │
│    - Demais agentes permanecem explicitamente desativados / default    │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Contratos de Código e Interface

### 4.1. Onda 1: `paralax-evo-crm` (`paralax/evo/crm/models.py`)

```python
class CrmMessagePart(BaseModel):
    """Represents a single part of a message in the CRM payload."""

    type: str
    text: str | None = None
    media_url: str | None = None
    data: str | None = None
    mime_type: str | None = None
    file: dict[str, Any] | None = None
    model_config = ConfigDict(extra="allow")

    def is_audio(self) -> bool:
        """Determina se a parte corresponde a um conteúdo de áudio."""
        if self.type == "audio":
            return True
        if self.mime_type and self.mime_type.lower().startswith("audio/"):
            return True
        if self.file and isinstance(self.file, dict):
            file_mime = (
                self.file.get("mimeType")
                or self.file.get("mime_type")
                or self.file.get("contentType")
                or self.file.get("content_type")
            )
            if file_mime and str(file_mime).lower().startswith("audio/"):
                return True
        return False

    def is_image(self) -> bool:
        """Determina se a parte corresponde a um conteúdo de imagem.

        Returns:
            True se o tipo for 'image' ou se o mime_type iniciar com 'image/'.
        """
        if self.type == "image":
            return True
        if self.mime_type and self.mime_type.lower().startswith("image/"):
            return True
        if self.file and isinstance(self.file, dict):
            file_mime = (
                self.file.get("mimeType")
                or self.file.get("mime_type")
                or self.file.get("contentType")
                or self.file.get("content_type")
            )
            if file_mime and str(file_mime).lower().startswith("image/"):
                return True
        return False

    def to_genai_part(self, timeout_seconds: float = 10.0) -> Part:
        """Converte a parte do CRM em uma Part utilizável pelo Google GenAI / ADK."""
        if self.is_audio() or self.is_image():
            default_mime = "audio/ogg" if self.is_audio() else "image/jpeg"
            clean_mime = self.mime_type
            if not clean_mime and self.file and isinstance(self.file, dict):
                clean_mime = (
                    self.file.get("mimeType")
                    or self.file.get("mime_type")
                    or self.file.get("contentType")
                    or self.file.get("content_type")
                )
            clean_mime = clean_mime or default_mime

            b64_payload = self.data
            if not b64_payload and self.file and isinstance(self.file, dict):
                b64_payload = self.file.get("bytes") or self.file.get("data")

            if b64_payload:
                raw_bytes = base64.b64decode(b64_payload)
                return Part.from_bytes(data=raw_bytes, mime_type=clean_mime)
            if self.media_url:
                with httpx.Client(timeout=timeout_seconds) as client:
                    resp = client.get(self.media_url)
                    resp.raise_for_status()
                    return Part.from_bytes(data=resp.content, mime_type=clean_mime)
            media_kind = "áudio" if self.is_audio() else "imagem"
            raise ValueError(f"Parte de {media_kind} sem 'data'/'bytes' nem 'media_url'.")

        return Part.from_text(text=self.text or "")


class CrmMessage(BaseModel):
    """Represents a complete message sent from the CRM."""

    role: str
    parts: list[CrmMessagePart]
    messageId: str | None = None
    model_config = ConfigDict(extra="allow")

    def has_audio(self) -> bool:
        """Verifica se alguma parte da mensagem contém áudio."""
        return any(part.is_audio() for part in self.parts)

    def has_image(self) -> bool:
        """Verifica se alguma parte da mensagem contém imagem."""
        return any(part.is_image() for part in self.parts)

    def to_genai_content(self, timeout_seconds: float = 10.0) -> tuple[Content, bool]:
        """Converte a mensagem para GenAI Content e reporta presença de áudio.

        Retrocompatível: Preserva retorno de (Content, bool) para chamadores existentes,
        incluindo todas as partes (áudio, imagens e texto) no Content.
        """
        genai_parts: list[Part] = []
        has_audio = False
        for part in self.parts:
            if part.is_audio():
                has_audio = True
                genai_part = part.to_genai_part(timeout_seconds=timeout_seconds)
                genai_parts.append(genai_part)
            elif part.is_image():
                genai_part = part.to_genai_part(timeout_seconds=timeout_seconds)
                genai_parts.append(genai_part)
            elif part.type == "text" and part.text and part.text.strip():
                genai_parts.append(Part.from_text(text=part.text))

        if not genai_parts:
            genai_parts.append(Part.from_text(text=""))

        return Content(role="user", parts=genai_parts), has_audio
```

---

### 4.2. Onda 2: Agentes Piloto (`paralax-support` e `anero-cafe-support`)

#### 1. Configuração 12-Factor (`config.py`)
```python
ENABLE_IMAGE_SUPPORT: bool = Field(
    default=False,
    validation_alias=AliasChoices(
        "enable_image_support",
        "ENABLE_IMAGE_SUPPORT",
        "IMAGE_SUPPORT",
    ),
)
IMAGE_DISABLED_FALLBACK_MESSAGE: str = Field(
    default=(
        "Desculpe, o recebimento de imagens está temporariamente desativado neste canal. "
        "Por favor, envie sua mensagem ou descreva sua dúvida por texto para que eu possa te ajudar!"
    ),
    validation_alias=AliasChoices(
        "image_disabled_fallback_message",
        "IMAGE_DISABLED_FALLBACK_MESSAGE",
    ),
)
```

#### 2. Roteamento e Interceptação no Webhook (`routers/crm.py`)
```python
has_image = request.params.message.has_image()
if has_image and not config.agent_settings.enable_image_support:
    logger.warning(
        "Image message received but image support is disabled (ENABLE_IMAGE_SUPPORT=False). "
        "Sending friendly fallback notice to customer."
    )
    fallback_text = config.agent_settings.image_disabled_fallback_message
    try:
        await crm_api.send_message(
            context_id=context_id,
            text=fallback_text,
            sender_id=agent_bot_id,
            sender_type="AgentBot",
        )
    except Exception as send_err:
        logger.warning("Falha ao despachar fallback de imagem: %s", send_err)

    final_chunks = format_for_whatsapp(fallback_text, max_chunk_size=config.MAX_MESSAGE_SIZE)
    parts = [{"type": "text", "text": chunk} for chunk in final_chunks]
    return {
        "jsonrpc": "2.0",
        "id": request.id,
        "result": {"artifacts": [{"parts": parts}]},
        "status": "success",
        "detail": "Image received but disabled by feature flag",
    }
```

#### 3. Prompts de Instrução em Inglês (`prompts.py`)
- **`paralax-support`:**
  ```xml
  <image_analysis_instructions>
  When the user provides an image (such as screenshots of errors, terminal output, logs, architecture diagrams, or technical documents):
  1. Carefully read and analyze all visible text, error codes, tracebacks, and visual cues.
  2. Directly address the specific error, stack trace, or configuration issue depicted in the image.
  3. Offer precise, step-by-step diagnostic or remediation commands in concise WhatsApp-friendly formatting.
  4. If an image is unreadable, blurry, or cropped, politely ask the user to provide a clearer screenshot or paste the text directly.
  </image_analysis_instructions>
  ```
- **`anero-cafe-support`:**
  ```xml
  <image_analysis_instructions>
  When the customer sends a photo (such as coffee packages, roast labels, brewing equipment, menus, or payment vouchers):
  1. Inspect the label details: roast level, process (natural, washed, honey), variety, altitude, and tasting notes.
  2. Answer inquiries about the beans, flavor profile, grind size recommendations, or brewing recipe.
  3. If the photo shows a menu or order voucher, confirm the ordered items and guide the customer cordially.
  4. If the photo is unclear, politely ask for clarification or a clearer shot of the package label.
  </image_analysis_instructions>
  ```

---

## 5. Critérios de Aceite e Testes (TDD)

1. **`paralax-evo-crm`:**
   - [ ] `Business Rule: CrmMessagePart must detect image by type or mime_type.`
   - [ ] `Business Rule: CrmMessagePart must convert base64 image data to Part.from_bytes with correct mime_type.`
   - [ ] `Business Rule: CrmMessage.has_image must return True when any part contains an image.`
   - [ ] `Business Rule: CrmMessage.to_genai_content must retain image parts alongside text in Content object.`
2. **`paralax-support` e `anero-cafe-support`:**
   - [ ] `Business Rule: Incoming image with ENABLE_IMAGE_SUPPORT=False must immediately return fallback message without invoking LLM.`
   - [ ] `Business Rule: Incoming image with ENABLE_IMAGE_SUPPORT=True must execute multimodal runner passing image Part.`
   - [ ] `Business Rule: Mixed message (text + image) with ENABLE_IMAGE_SUPPORT=True must process both text and visual content.`
   - [ ] `Business Rule: Corrupted or unparseable image payload must return friendly error message without throwing HTTP 500.`
3. **`argocd`:**
   - [ ] Manifestos em `prod/` para `paralax-support` e `anero-cafe-support` contêm `ENABLE_IMAGE_SUPPORT="true"`.
   - [ ] Outros agentes mantêm a feature explicitamente desativada.
