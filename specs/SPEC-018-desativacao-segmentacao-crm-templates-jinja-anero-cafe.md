---
spec_id: SPEC-018
title: Desativação da Segmentação Artificial no CRM e Padronização de Templates Jinja
  para Mensagens WhatsApp no Anero Café
product:
- anero-cafe-support
- paralax-platform
capability: conversational-ai-agent
scope: single-repo
bounded_context: Conversational Agent / Canais & Formatação WhatsApp
origin_module: anero-cafe-support
target_repositories:
- repo: paralax-ia/anero-cafe-support
  wave: 1
  role: ai-agent
  prompts:
  - anero_cafe/instruction
  - anero_cafe/b2b_cadastrado
  - anero_cafe/lead_b2b_qualificacao
prompts:
- name: anero_cafe/instruction
  target_repo: paralax-ia/anero-cafe-support
  file: anero_cafe/prompts.py
  symbol: INSTRUCTION
  description: Instrução governada de prompt 'anero_cafe/instruction'
- name: anero_cafe/b2b_cadastrado
  target_repo: paralax-ia/anero-cafe-support
  file: anero_cafe/prompts.py
  symbol: INSTRUCTION
  description: Instrução governada de prompt 'anero_cafe/b2b_cadastrado'
- name: anero_cafe/lead_b2b_qualificacao
  target_repo: paralax-ia/anero-cafe-support
  file: anero_cafe/prompts.py
  symbol: INSTRUCTION
  description: Instrução governada de prompt 'anero_cafe/lead_b2b_qualificacao'
status: APPROVED
---

# SPEC-018: Desativação da Segmentação Artificial no CRM e Padronização de Templates Jinja para Mensagens WhatsApp no Anero Café

> **Product:** [`anero-cafe-support`](../products/anero-cafe-support.yaml) | [`paralax-platform`](../products/paralax-platform.yaml)  
> **Business Capability:** [`conversational-ai-agent`](../capabilities/conversational-ai-agent/capability.yaml)  
> **Scope:** Agente de IA (`anero-cafe-support`) e Integração com CRM/WhatsApp  
> **Bounded Context:** Conversational Agent / Canais de Mensageria & Formatação WhatsApp  
> **Status:** DRAFT  
> **Autor:** Antigravity & Eduardo F. Santos  
> **Data de Criação:** 2026-11-22  
> **Arquitetura 12-Factor & Padronização:** Formatação determinística de catálogo via templates Jinja com espelhamento estrito no prompt e desativação do fatiamento cego de mensagens no orquestrador de canais.  

---

## 1. Contexto e Motivação

Durante o atendimento conversacional do **Anero Café** no WhatsApp oficial, mensagens contendo o catálogo de produtos ou múltiplos cafés estavam sendo fragmentadas em 4 ou mais mensagens desconexas e cortadas no meio de palavras e sintaxes markdown (ex: `*Torra` em uma mensagem e `Média/Escura)*` na mensagem subsequente; e uma última mensagem contendo unicamente a palavra `deles?`).

### 1.1. Análise de Causa Raiz (RCA - Ishikawa & 5 Whys)

1. **Método e Configuração do Bot (`scripts/crm_register_bot.sh`):**
   - No script de registro do bot no CRM (`api/v1/agent_bots`), o payload registra:
     ```json
     {
       "text_segmentation_enabled": true,
       "text_segmentation_limit": 300,
       "text_segmentation_min_size": 50,
       "delay_per_character": 50.0
     }
     ```
   - O parâmetro `text_segmentation_limit: 300` ativa no middleware em Go (`evo-bot-runtime`) a função `segmentContent` (`pkg/dispatch/service/dispatch_engine.go`).

2. **Mecanismo Cego de Corte (`segmentContent` em Go):**
   - O `segmentContent` divide o texto recebido de forma gananciosa (`\S+|\s+`) ao atingir ~300 caracteres, **ignorando semântica, parágrafos e marcações de formatação do WhatsApp** (como negritos `*` e marcadores de lista `•`).
   - O resultado é um fatiamento destrutivo da mensagem, enviando fragmentos soltos para a API do WhatsApp a cada 300 caracteres.

3. **Incompatibilidade com os Limites Oficiais do WhatsApp:**
   - A **API Oficial do WhatsApp (Cloud API e On-Premises API)** possui limite de **4.096 caracteres** por mensagem de texto (`messages[type=text].body`).
   - Uma mensagem contendo a listagem completa de cafés do Anero Café possui entre 600 e 900 caracteres — cabendo com folga em **uma única mensagem atômica, legível e elegante no WhatsApp**.

4. **Ausência de Templates Estruturados (Divergência do Agente de Veículos):**
   - No agente de veículos (`customer-support-vehicles`), as saídas das ferramentas utilizam templates **Jinja2** (`vehicles/templates/vehicle_details.j2`) com a regra estrita de prompt `Exact Tool Output Mirroring`.
   - No `anero-cafe-support`, a ferramenta `anero_cafe/tools/coffee.py` concatenava strings manualmente em Markdown verboso (`###` títulos, múltiplos bullets aninhados, moagens repetidas para cada item), produzindo um texto longo e desestruturado que facilitava quebras e poluição visual.

---

## 2. Arquitetura da Solução

```
[ Usuário WhatsApp ]
        │
        │ Pergunta: "Me mostre todas as opções e preços"
        ▼
[ evo-bot-runtime / CRM ]
        │ (Sem segmentação artificial: text_segmentation_enabled: false)
        ▼
[ anero-cafe-support (/crm/run) ]
        │
        ├── 1. LLM invoca ferramenta: coffee_search / get_coffee_details
        │
        ├── 2. anero_cafe/tools/coffee.py renderiza catálogo via Jinja2
        │      • Template: anero_cafe/templates/coffee_catalog_item.j2 (listagem compacta)
        │      • Template: anero_cafe/templates/coffee_details.j2 (card detalhado PF/PJ)
        │
        ├── 3. LLM aplica regra estrita: "Exact Tool Output Mirroring"
        │      • Espelha exatamente a saída renderizada dos itens
        │
        └── 4. Retorno JSON-RPC com mensagem consolidada (<= 4000 caracteres)
        ▼
[ evo-bot-runtime / WhatsApp API ]
        │ Entrega mensagem única, coesa e com formatação perfeita no WhatsApp
        ▼
[ Usuário WhatsApp: Mensagem elegante sem quebras arbitrárias ]
```

---

## 3. Especificação Técnica e Regras de Negócio

### 3.1. Desativação da Segmentação Artificial no Registro do Bot

No arquivo `scripts/crm_register_bot.sh` do `anero-cafe-support`:
1. Desativar explicitamente a segmentação de texto do bot:
   - `'text_segmentation_enabled': False`
2. Ajustar o limite de corte de segurança para o limite oficial do WhatsApp (margem de segurança de 4000 caracteres em vez de 300):
   - `'text_segmentation_limit': 4000`
   - `'text_segmentation_min_size': 100`
3. Dessa forma, respostas normais de até 4.000 caracteres são despachadas como mensagens íntegras e completas para o WhatsApp.

### 3.2. Criação de Templates Jinja no Anero Café

Criar o diretório `anero_cafe/templates/` contendo os templates padronizados:

#### 1. `anero_cafe/templates/coffee_details.j2` (Card Detalhado)
Utilizado para detalhar um café específico consultado pelo cliente:
```jinja2
☕ *{{ name }}*{% if torra and torra != "—" %} (Torra {{ torra }}){% endif %}
{% if notas and notas != "—" %}• *Notas:* {{ notas }}
{% endif %}{% if origem and origem != "—" %}• *Origem:* {{ origem }}{% if variedade and variedade != "—" %} | {{ variedade }}{% endif %}
{% endif %}{% if include_price and prices %}• *Preços:* {% for size, price in prices.items() %}{{ size }}: {{ price }}{% if not loop.last %} | {% endif %}{% endfor %}
{% endif %}• *Moagens:* Grãos ou Moído (Filtro, Moka, Prensa)
```

#### 2. `anero_cafe/templates/coffee_catalog_item.j2` (Item Compacto de Listagem)
Utilizado na listagem de múltiplos produtos quando o cliente pede todas as opções do cardápio:
```jinja2
☕ *{{ name }}*{% if torra and torra != "—" %} (Torra {{ torra }}){% endif %} - Notas: {{ notas }}
{% if include_price and prices %}   • 250g: {{ prices.get('250g', prices.get('unit', 'Sob consulta')) }}{% if prices.get('500g') %} | 500g e 1kg a partir de {{ prices.get('500g') }}{% endif %}
{% endif %}
```

#### 3. `anero_cafe/templates/catalog_summary.j2` (Sumário Completo do Catálogo)
Template para consolidar as categorias (Especiais, Drip Coffee, Kits) com link oficial e fechamento objetivo:
```jinja2
Aqui estão as opções disponíveis no nosso catálogo:

{% for item in coffee_items %}
{{ item }}
{% endfor %}
{% if drip_items %}
*⚡ Linha Drip Coffee (Prático direto na xícara)*
{% for drip in drip_items %}
{{ drip }}
{% endfor %}
{% endif %}
Todos disponíveis pelo site: https://www.anerocafe.com.br/

Quer que eu monte o seu pedido por aqui ou prefere o link de algum deles?
```

### 3.3. Integração do Jinja2 em `anero_cafe/tools/coffee.py`

1. Instanciar o ambiente Jinja2 com `FileSystemLoader` apontando para `anero_cafe/templates/`:
   ```python
   from jinja2 import Environment, FileSystemLoader
   
   TEMPLATE_DIR = os.path.join(os.path.dirname(__file__), "..", "templates")
   jinja_env = Environment(
       loader=FileSystemLoader(TEMPLATE_DIR),
       keep_trailing_newline=False,
       trim_blocks=True,
       lstrip_blocks=True,
   )
   ```
2. Refatorar `format_coffee_card` e `resolve_coffee_from_content` para utilizarem os templates Jinja, respeitando rigorosamente a flag `include_price` (garantindo que o fluxo corporativo B2B continue sem exibir preços).
3. Adicionar uma função de listagem compacta de catálogo `get_catalog_overview(include_price: bool = True) -> str` que renderiza todos os itens de forma limpa e compacta.

### 3.4. Diretriz de Prompting: Exact Tool Output Mirroring

Atualizar as instruções dos agentes em `anero_cafe/prompts.py`:
1. Adicionar seção mandatória:
   ```markdown
   <exact_tool_output_mirroring>
   When coffee catalog tools (`get_coffee_details`, `get_catalog_overview`) return formatted coffee cards or list items:
   - You MUST copy and paste the EXACT output into your response for EACH coffee product.
   - Do NOT reformat, do NOT remove emojis, do NOT break lines into random bullet points, and do NOT alter WhatsApp asterisks (*).
   - When listing multiple coffees, separate each item's exact output with a single blank line.
   </exact_tool_output_mirroring>
   ```
2. Instruir o modelo a utilizar o formato de catálogo conciso quando o cliente solicitar "todas as opções", "cardápio", "tabela de preços" ou "o que vocês têm".

### 3.5. Governança de Prompts no Langfuse SSOT (§3.5 Mandatória)

Em conformidade com as regras globais do ecossistema Paralax IA:
1. **Prompts Gerenciados:**
   - `anero_cafe/instruction`: Prompt principal do atendimento de varejo / pessoa física.
   - `anero_cafe/b2b_cadastrado`: Prompt do atendimento corporativo com CNPJ previamente cadastrado.
   - `anero_cafe/lead_b2b_qualificacao`: Prompt do atendimento corporativo para novas empresas.
2. **Ciclo de Vida do Prompt:**
   - Durante a implementação na branch de trabalho, os prompts locais devem ser sincronizados como `draft` no Langfuse.
   - No merge formal e conclusão da spec, a esteira promove os prompts de forma atômica para `production`.

---

## 4. Plano de Implementação (Ondas Topológicas)

Como as alterações estão contidas na camada do agente e no seu respectivo script de registro no CRM, a execução é concentrada em **1 Onda**:

### Onda 1: `paralax-ia/anero-cafe-support`
1. Atualizar `scripts/crm_register_bot.sh` desativando `text_segmentation_enabled` e elevando `text_segmentation_limit` para 4000.
2. Criar diretório `anero_cafe/templates/` com os templates Jinja:
   - `coffee_details.j2`
   - `coffee_catalog_item.j2`
   - `catalog_summary.j2`
3. Atualizar `pyproject.toml` garantindo dependência explícita de `jinja2>=3.1.0`.
4. Atualizar `anero_cafe/tools/coffee.py` integrando a renderização Jinja2.
5. Atualizar `anero_cafe/prompts.py` com a regra `Exact Tool Output Mirroring`.
6. Criar suíte de testes unitários em `tests/unit/tools/test_coffee_templates.py`.

---

## 5. Plano de Testes e Critérios de Aceite (TDD)

### 5.1. Testes Unitários dos Templates (`test_coffee_templates.py`)
- **Regra de Negócio:** `test_coffee_details_renders_clean_whatsapp_card`: Verifica se o card detalhado contém nome em negrito, notas sensoriais, preços formatados e moagens sem markdown truncado.
- **Regra de Negócio:** `test_coffee_details_b2b_hides_prices`: Garante que quando `include_price=False`, nenhuma linha de preço ou símbolo `R$` é renderizada.
- **Regra de Negócio:** `test_catalog_summary_compact_under_whatsapp_limit`: Garante que uma listagem completa de todos os cafés do catálogo do Drive renderiza uma mensagem compacta com menos de 1.000 caracteres (bem abaixo do teto de 4.096 do WhatsApp).

### 5.2. Testes de Integração do Webhook (`test_crm.py`)
- **Regra de Negócio:** O endpoint `/crm/run` deve retornar mensagens completas de até 4.000 caracteres no artefato do JSON-RPC sem quebras artificiais nem fragmentação em fatias de 300 caracteres.

### 5.3. Testes do Script de Registro (`test_crm_register_bot.py`)
- **Regra de Negócio:** O payload do bot gerado para o CRM deve conter `text_segmentation_enabled: False` e `text_segmentation_limit: 4000`.