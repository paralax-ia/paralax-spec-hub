# paralax-spec-hub

Repositório Central de Governança de Especificações (Spec-Driven Development) do ecossistema **Paralax IA**.

---

## 🎯 Princípios do Spec-Driven Development (SDD)

1. **Intenção antes de Código:** Nenhuma funcionalidade começa diretamente no código dos microsserviços. Toda nova feature nasce como uma especificação neste repositório.
2. **Governança por PR:** Novas specs ou alterações de contratos tramitam via Pull Request neste repositório, disparando o planejamento e a distribuição de tarefas filhas.
3. **Catálogo de Capacidades:** O diretório `capabilities/` mapeia quem faz o quê no sistema, extraído a partir dos repositórios listados em `manifest.yaml`.

---

## 📂 Estrutura

* **`manifest.yaml`**: Lista oficial de repositórios, papéis arquiteturais e dependências do ecossistema.
* **`products/`**: Catálogo de Produtos e Domínios de Clientes (`products/*.yaml`). Agrupa as soluções oferecidas a diferentes segmentos de negócio (ex: varejo automotivo, clínicas médicas, cafeterias, plataforma core).
* **`capabilities/`**: Business Capabilities modeladas sob Domain-Driven Design (DDD) como Bounded Contexts perenes (`capability.yaml`), contendo Linguagem Ubíqua, Context Map, Escopo (Platform vs. Product-Specific) e contratos de runtime. Uma capability governa múltiplas specs (1:N) e pode atender múltiplos produtos.
* **`specs/`**: Especificações de funcionalidades incrementais (`SPEC-001-...`) vinculadas ao seu Produto e à sua Business Capability pai.
* **`.spectral.yaml`**: Regras e padrões de governança para contratos OpenAPI 3.1.
* **`AGENTS.md`**: Diretrizes operacionais para agentes de IA que atuam neste hub.

> **Hierarquia DDD:** `Product` ➔ `Business Capability` (Bounded Context) ➔ `Spec` (`SPEC-XXX`) ➔ `Runtime Contracts`.

> **Nota Arquitetural:** O spec hub é um repositório **estritamente declarativo** (dados, contratos e especificações). As ferramentas de auditoria, sincronização e planejamento de capacidades residem centralmente no motor [`agentic-flywheel`](https://github.com/eduardosan/agentic-flywheel) e na CLI [`harness-state`](https://github.com/eduardosan/harness-state).

---

## 🚀 Como Iniciar uma Nova Funcionalidade

1. Crie uma branch:
   ```bash
   git checkout -b spec/SPEC-001-nome-da-funcionalidade
   ```
2. Escreva o arquivo de especificação em `specs/SPEC-001-nome-da-funcionalidade.md`.
3. Abra o Pull Request neste repositório:
   - O CI validará os padrões e contratos via Spectral.
   - O **Planner** cruzará os requisitos com `capabilities/` e abrirá as sub-tarefas nos repositórios alvo.

---

## 🤖 Operação com Agentes de IA (Local vs. Cloud)

A plataforma suporta dois fluxos de implementação para transformar especificações em código nos repositórios spoke:

1. **Opção 1: Nuvem (Off the Loop - 100% Autônomo):** O planner cria as issues nos spokes com a label `agent-run`. Os runners dedicados na nuvem (Hetzner LXC CT 109) codificam via Aider + `agentic-qwen:7b` e abrem os PRs automaticamente.
2. **Opção 2: Local (On the Loop - Pair-Programming):** O desenvolvedor ou agente local conecta ao Redis via túnel SSH, planeja as ondas e cria issues nos spokes **sem** a label `agent-run`. O código é desenvolvido localmente por ondas (Onda 1: SDKs ➔ Onda 2: Agentes), validado com `just verify`, e submetido via PR.

Em ambos os modos, a aprovação final e merge transacional ocorrem através do **Cross-Repo Harness Gate**.

👉 **Para o guia operacional completo com comandos, topologia e regras de engenharia, consulte:** [**`AGENTS.md`**](./AGENTS.md).
