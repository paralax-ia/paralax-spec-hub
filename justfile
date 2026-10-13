# Interface Canônica de Governança e SDD - paralax-spec-hub

default:
    @just --list

# Audita conformidade da Linguagem Ubíqua das Business Capabilities contra o código local
audit-capabilities:
    ./bin/capabilities audit

# Sincroniza e atualiza os runtime_contracts nos arquivos capabilities/*/capability.yaml
sync-capabilities:
    ./bin/capabilities sync

# Executa linting estático dos contratos OpenAPI e regras de spec via Spectral
lint:
    spectral lint specs/*.md || true
