# SDD Technical Specification Refinement Request (In-Flight)

You are the Software Architect responsible for the ecosystem.
The human operator requested a refinement/change in the technical specification below during the Approval Gateway.

## Target Specification File:
`/mnt/home/eduardo/srv/paralax-ia/paralax-spec-hub/specs/SPEC-010-suporte-audio-como-feature.md`

## Current Specification Content:
```markdown
---
spec_id: SPEC-010
title: "Suporte audio como feature"
product:
  - paralax-platform
capability: customer-relationship-management
scope: platform
bounded_context: "CRM (Supporting Subdomain)"
origin_module: module-name
target_repositories:
  - repo: paralax-ia/module-name
    wave: 1
    role: service
prompts:
  - name: module-name/agent_instruction
    target_repo: paralax-ia/module-name
    file: module_name/prompts.py
    symbol: INSTRUCTION
    description: "Instrução de prompt do agente ou componente LLM"
status: DRAFT
---

# SPEC-010: Suporte audio como feature

> **Product:** `paralax-platform`  
> **Business Capability:** `customer-relationship-management`  
> **Scope:** Platform  
> **Bounded Context:** CRM (Supporting Subdomain)

## 1. Contexto e Motivação
Descreva o problema de negócio resolvido por este módulo.

## 2. Escopo e Repositórios Afetados
- [ ] [Onda 1] `paralax-ia/module-name`: Descrição da entrega neste módulo.

## 3. Contratos de Interface
Descreva classes, métodos ou endpoints OpenAPI 3.1 adicionados/alterados.

### 3.1. Viabilidade Técnica e Compatibilidade de SDKs / APIs Externas
- **Dependências Externas / SDKs:** Liste pacotes e versões mínimas exigidas (ex: `google-genai>=1.0.0`, `google-adk>=0.2.0`).
- **Protocolo e Modo de Execução:** REST síncrono, streaming assíncrono, WebSocket bidirecional (Live API), etc.
- **Limitações Conhecidas e Paridade de Recursos:**
  - [ ] A API/SDK suporta chamadas de ferramentas (Function Calling) no modo especificado?
  - [ ] Existem restrições de formato de dados, codecs de áudio ou payloads (ex: PCM 16kHz, limites de turnos)?
  - [ ] O ciclo de vida da sessão, reconexão e contexto conversacional são suportados nativamente?
- **Estratégia de Spike (Onda 0):** Se a tecnologia for experimental, emergente (ex: Gemini Live API) ou não comprovada no ecossistema, defina uma subtarefa com `wave: 0` e `role: spike` contendo teste executável antes da implementação definitiva.
- **Plano de Fallback Arquitetural:** Estratégia de contingência caso a API externa apresente incompatibilidades técnicas em produção (ex: fallback de Live streaming para requisições assíncronas turn-by-turn).

### 3.5. Governança de Prompts (SPEC-PROMPT-01)
- **Prompt:** `module-name/agent_instruction`
- **Repositório:** `paralax-ia/module-name`
- **Arquivo Local / Fallback:** `module_name/prompts.py` (constante `INSTRUCTION`)
- **Papel:** Instrução de sistema do agente
- **Idioma:** Estritamente em inglês

## 4. Critérios de Aceitação (Gherkin)
- **Cenário 1: Comportamento esperado**
  - **Dado** um estado inicial válido
  - **Quando** a operação for executada
  - **Então** o contrato deve responder conforme especificado.

## 5. Plano de Rollout e Compatibilidade
Estratégia de versionamento SemVer e publicação.
```

## Current Subtasks State in State Tracker:
### COMPLETED AND FROZEN SUBTASKS (DO NOT MODIFY ALREADY DELIVERED SCOPE):
  (No completed tasks so far)

### PENDING SUBTASKS / UPCOMING WAVES (OPEN FOR REFINEMENT):
  - [task-1] Wave 1 in `paralax-ia/paralax-common` (Status: PENDING)

## Operator Requested Change Instruction:
Todos os agentes de IA devem ter suporte a audio como uma feature flag a partir das especificações da spec-009

## Mandatory Refinement Rules:
1. PRESERVE COMPLETED WORK: It is strictly forbidden to regress, remove, or modify the scope, public interface contracts, or acceptance criteria of already completed tasks (none).
2. UPDATE THE FILE DIRECTLY ON DISK: Rewrite/edit the file `SPEC-010-suporte-audio-como-feature.md` incorporating the requested changes:
   - Add or update Interface Contracts and Acceptance Criteria (Gherkin) for pending tasks or new waves.
   - Update the Context and Motivation section reflecting recent decisions.
   - Adjust YAML Frontmatter (`target_repositories`) if new subtasks or modules are added for upcoming waves.
   - Ensure the specification strictly complies with canonical ecosystem SDD format.
3. MANDATORY PROMPT GOVERNANCE (SPEC-PROMPT-01): If any target repository is an AI agent (`role: ai-agent`) or if the spec touches instructions, system prompts, or files like `prompts.py`, you MUST declare all affected prompts in YAML Frontmatter under `prompts:` with `name`, `target_repo`, `file`, `symbol`, and `description`. Document the exact prompt text in English in Section 3.5.
4. MANDATORY TECHNICAL FEASIBILITY AND SDK COMPATIBILITY: It is strictly prohibited to design architecture or public interface contracts assuming unsupported features in third-party or emerging SDKs (such as Google ADK, Gemini Live API, or WebSocket streaming) without verifying feasibility. For any real-time, audio, streaming, or emerging SDK integration: (a) Explicitly document required SDK dependencies, versions, and contract signatures in Section 3.1; (b) Specify protocol constraints (e.g., tool calling limitations in streaming mode, socket lifecycle, audio codecs); (c) If capability is not proven in codebase, specify a preliminary Wave 0 Spike task (`role: spike`) before feature implementation; (d) Define an architectural fallback in Section 3.1.