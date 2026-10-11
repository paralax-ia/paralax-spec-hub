# paralax-spec-hub

Repositório Central de Governança de Especificações (Spec-Driven Development) do ecossistema **Paralax IA**.

---

## 🎯 Princípios do Spec-Driven Development (SDD)

1. **Intenção antes de Código:** Nenhuma funcionalidade começa diretamente no código dos microsserviços. Toda nova feature nasce como uma especificação neste repositório.
2. **Governança por PR:** Novas specs ou alterações de contratos tramitam via Pull Request neste repositório, disparando o planejamento e a distribuição de tarefas filhas.
3. **Catálogo de Capacidades:** O diretório `capabilities/` mapeia quem faz o quê no sistema, extraído a partir dos repositórios listados em `manifest.yaml`.

---

## 📂 Estrutura

* **`manifest.yaml`**: Lista oficial de repositórios, papéis arquiteturais e Dockerfiles do ecossistema.
* **`capabilities/`**: Esquemas de capacidades declaradas por serviço (endpoints, eventos e regras de negócio).
* **`specs/`**: Especificações de funcionalidades ativas e em evolução (`SPEC-001-...`).
* **`.spectral.yaml`**: Regras e padrões de governança para contratos OpenAPI 3.1.

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
