# SFWork — Agent Guide

This guide describes the `sfwork` workspace for AI coding agents. The workspace is a mono-repo-like directory that bundles the four main repositories of the SecretFlow privacy-preserving computing ecosystem. Read this first before touching any code.

> **Documentation language note**: The projects maintain both English and Chinese documentation. The most detailed operation guides (e.g. `无docker运行说明.md`, `运行说明.md`) are in Chinese, while architecture summaries such as `PROJECT_SUMMARY.md` are in English. Code comments are often bilingual.
>
> **Centralized docs**: All project documentation is organized and copied to `docs/doc-center/`. Start with `docs/doc-center/README.md` to find the right document by category.  
> **Agent skills**: Project-level Kimi skills live in `.agents/skills/`. Use them for doc lookup, frontend/backend/Kuscia workflows, and workspace orientation.

---

## 1. Project Overview

`sfwork` is the local development workspace for the SecretFlow stack. It contains four independent but integrated projects:

| Project | Language | Role | Directory |
|---|---|---|---|
| **Kuscia** | Go | Kubernetes-based orchestration engine for federated learning jobs | `kuscia/` |
| **SecretFlow** | Python | Privacy-preserving computation framework (MPC, HEU, SPU, TEE, FL) | `secretflow/` |
| **Privahub** | Go | Web management console backend | `privahub/` |
| **Privahub Frontend** | TypeScript / React | Web management console UI | `privahub/web/` |

There is also a legacy copy of the frontend at `privahub/frontend-src/` and `secretpad-frontend/`, but it has been deprecated and removed; active development happens in `privahub/web/`.

### 1.1 Local Privacy SDKs / Agent

In addition to the four main projects, `sfwork` is accompanied by three standalone local-privacy repositories. They provide masking, K-anonymity, differential privacy, and query obfuscation without requiring a full SecretFlow job:

| Project | Language | Role | Repository |
|---|---|---|---|
| **privacy-java-sdk** | Java 17 | Local SDK for Java/Privahub backends | [github.com/fengzhizi319/privacy-java-sdk](https://github.com/fengzhizi319/privacy-java-sdk) |
| **privacy-go-sdk** | Go 1.21 | Local SDK for Go microservices | [github.com/fengzhizi319/privacy-go-sdk](https://github.com/fengzhizi319/privacy-go-sdk) |
| **privacy-local-agent** | Python 3.10+ | REST + gRPC Sidecar for multi-language access | [github.com/fengzhizi319/privacy-local-agent](https://github.com/fengzhizi319/privacy-local-agent) |

Clone them next to the `sfwork` root directory when needed; they are ignored by the `sfwork` root repository. Use the Java/Go SDKs when the consuming service is written in the same language and can embed a library. Use the Agent when you need a language-agnostic Sidecar or cannot embed an SDK. See `docs/dp/README.md` for a selection guide.

### How the pieces fit together

```text
Privahub Frontend (React/Vite, port 8000 dev)
        │  REST /api/v1alpha1/*
        ▼
Privahub Backend (Go, ports 8080/9001)
        │  gRPC
        ▼
Kuscia Master/Lite (Go, gRPC port 8083, Envoy ports 80/1080)
        │  schedules pods / DomainData / DomainRoute
        ▼
SecretFlow (Python)  ← executes privacy-preserving algorithms inside containers
```

Data access is mediated by **DataMesh** (part of Kuscia) using gRPC and Apache Arrow Flight.

### 1.2 c-life Privacy Computing Platform

The platform is positioned as a full-stack privacy computing system with three capability layers:

```
Data Ingest → Classification (L1~L5) → Local Privacy Processing → FL / MPC → Audit & Budget
```

- **Classification**: Rule Engine → Small-NER → local VLM/LLM for multimodal medical data.
- **Local Privacy**: Masking, K-anonymity, Differential Privacy, Query Obfuscation.
- **FL / MPC**: Cross-domain collaborative computing with data available but invisible.

The detailed whitepaper and presentation are in `docs/doc-center/00-项目总览/`.

### 1.3 Documentation Center & Agent Skills

| Resource | Path | Purpose |
|---|---|---|
| Centralized docs | `docs/doc-center/README.md` | Categorized archive of all sfwork / frontend / backend / Kuscia docs |
| Project whitepaper | `docs/doc-center/00-项目总览/数据分类分级与本地隐私原语-团队汇报与落地白皮书.md` | Full-stack privacy computing overview |
| Presentation | `docs/doc-center/00-项目总览/数据分类分级与本地隐私原语-汇报PPT.html` | HTML slide deck |
| Workspace skill | `.agents/skills/sfwork-workspace/SKILL.md` | Workspace orientation and cross-project commands |
| Doc reader skill | `.agents/skills/doc-center-reader/SKILL.md` | How to navigate docs/doc-center |
| Frontend skill | `.agents/skills/secretpad-frontend-dev/SKILL.md` | Frontend development workflow |
| Backend skill | `.agents/skills/secretpad-backend-dev/SKILL.md` | Backend development workflow |
| Kuscia skill | `.agents/skills/kuscia-dev/SKILL.md` | Kuscia development workflow |

---

## 2. Repository Layout

```text
/home/charles/code/sfwork/
├── AGENTS.md                     # this file
├── PROJECT_SUMMARY.md            # high-level English architecture summary
├── 项目总结.md                    # high-level Chinese architecture summary
├── 无docker运行说明.md            # Chinese non-Docker runbook
├── scripts/run-all-no-docker.sh  # one-script launcher for local dev
├── .local-kuscia/                # Kuscia runtime home (created at runtime)
├── logs/                         # aggregated logs from run-all-no-docker.sh
├── kuscia/                       # Go orchestration engine
├── secretflow/                   # Python privacy-preserving ML framework
├── privahub/                     # Go backend + React/Vite frontend (privahub/web/)
├── privacy-java-sdk/             # Java local privacy SDK
├── privacy-go-sdk/               # Go local privacy SDK
└── privacy-local-agent/          # Python REST/gRPC privacy agent
```

---

## 3. Technology Stack

### Kuscia (`kuscia/`)
- **Go 1.24.7**
- Kubernetes CRDs (`k8s.io/* v0.33.5`)
- gRPC / Protocol Buffers
- Gin (internal HTTP), Envoy (gateway), CoreDNS (service discovery)
- containerd / runc / K3s (embedded control plane)
- Apache Arrow Flight (DataMesh I/O)
- Zap / custom `nlog` logger, Viper for config

### SecretFlow (`secretflow/`)
- **Python 3.10 / 3.11**
- JAX, NumPy, pandas, scikit-learn
- SPU, HEU, sf-sml, secretflow-spec, secretflow-dataproxy (ecosystem packages)
- PyArrow, DuckDB, gRPC
- Build: `pdm-backend`, PEP 517 wheel

### Privahub (`privahub/`)
- **Go 1.25**
- **Gin** HTTP framework
- **GORM** with SQLite (default) and MySQL drivers
- **gRPC** via Kuscia Go client (`privahub/pkg/kuscia`)
- **Viper** for configuration; profile-based configs in `config/privahub*.yaml`
- **Zap** structured logging
- **JWT** authentication
- **Prometheus** metrics

### Privahub Frontend (`privahub/web/`)
- **Node.js >= 18.0.0**, **pnpm >= 8.8.0** (managed by `packageManager` field, currently `pnpm@11.7.0`)
- **React 18**, **Vite 5**, **Tailwind CSS**
- **TypeScript 5.x**
- **Zustand** for state management
- pnpm workspace monorepo
- Vitest + React Testing Library

---

## 4. Build & Test Commands

### 4.1 Kuscia

```bash
cd /home/charles/code/sfwork/kuscia

# Build the kuscia binary
make build
# or
bash hack/build.sh -t kuscia

# Build the standalone transport binary
bash hack/build.sh -t transport

# Unit tests
make test

# Lint
make lint-golang
make check

# Generate code (CRDs, clientset, proto)
make generate

# Docker image
make image
```

### 4.2 SecretFlow

```bash
cd /home/charles/code/sfwork/secretflow

# Editable install
pip install -e .

# Install dev extras
pdm install -G dev

# Build wheel
python -m build --wheel
# or
pdm build

# Compile extended protobufs (protoc 3.19.6)
~/protoc-3.19.6/bin/protoc \
  --proto_path secretflow/protos/ \
  --python_out . \
  secretflow/protos/secretflow/spec/extend/*.proto

# Run tests
python -m pytest tests/ -v                    # simulation mode
python -m pytest tests/ --env=prod -v         # MPC/prod mode
```

### 4.3 Privahub Backend

```bash
cd /home/charles/code/sfwork/privahub

# Run tests (CGO required for SQLite driver)
CGO_ENABLED=1 go test ./...

# Build backend binary (CGO required for SQLite driver)
CGO_ENABLED=1 go build -o bin/privahub ./cmd/server

# Run locally with the dev profile (Docker-mapped Kuscia ports)
PRIVAHUB_PROFILE=dev ./bin/privahub -config ./config/privahub.yaml

# Docker image
make image
```

### 4.4 Privahub Frontend

```bash
cd /home/charles/code/sfwork/privahub/web

# Enable corepack so the project-specified pnpm version is used
corepack enable

# Install dependencies
corepack pnpm install

# Dev server (http://localhost:8000)
corepack pnpm --filter @privahub/app dev

# Build all packages and the main app
corepack pnpm run build

# Typecheck
corepack pnpm run typecheck

# Test
corepack pnpm test

# Lint / format
corepack pnpm run lint
```

---

## 5. Code Organization

### Kuscia
| Directory | Purpose |
|---|---|
| `cmd/kuscia/` | CLI entry point and module initializers |
| `pkg/agent/` | Kubelet-like agent, pod lifecycle, CRI |
| `pkg/controllers/` | CRD controllers (job, task, domain, route, domaindata, GC, ...) |
| `pkg/kusciaapi/` | External HTTP/gRPC API server |
| `pkg/datamesh/` | DataMesh HTTP/gRPC + Arrow Flight |
| `pkg/gateway/` | Envoy xDS control plane, domain route, handshake |
| `pkg/confmanager/` | Certificate & config management |
| `pkg/transport/` | Standalone transport service |
| `pkg/scheduler/` | Scheduler plugins |
| `pkg/web/` | Internal Gin + gRPC web framework |
| `pkg/utils/` | Shared utilities, `nlog`, TLS helpers |
| `pkg/crd/` | Generated Go types, clientset, informers, listers |
| `crds/v1alpha1/` | CRD YAML manifests |
| `proto/api/v1alpha1/` | Protobuf definitions |
| `scripts/deploy/` | Docker deployment scripts |
| `scripts/run_local_kuscia.sh` | Non-Docker local master runner |

### SecretFlow
| Directory | Purpose |
|---|---|
| `secretflow/device/` | `PYU`, `SPU`, `HEU`, `TEEU` devices |
| `secretflow/data/` | Horizontal/vertical/mixed FedDataFrames, FedNdarray |
| `secretflow/ml/` | FL/SL algorithms |
| `secretflow/component/` | Pipeline/component system |
| `secretflow/preprocessing/` | Binning, encoding, scaling |
| `secretflow/stats/` | Statistics and evaluation |
| `secretflow/privacy/` | Differential privacy, k-anonymity |
| `secretflow/security/` | Secure aggregation/comparison |
| `secretflow/kuscia/` | Kuscia task entry point and DataMesh client |
| `secretflow/protos/` | Source `.proto` files |
| `secretflow/spec/extend/` | Generated Python protobuf bindings |
| `tests/` | pytest suite, custom MPC test runner |

### Privahub Backend
Go project under `github.com/fengzhizi319/privahub`:

| Directory | Purpose |
|---|---|
| `cmd/server/` | CLI entry point for the main server binary |
| `cmd/migrator/` | Database migration utility |
| `cmd/edge-agent/` | Edge/lite mode agent binary |
| `internal/controller/http/` | HTTP handlers / routers (`/api/v1alpha1/*`) |
| `internal/service/` | Business logic |
| `internal/dao/` | Database access layer (GORM models, migrations, repositories) |
| `internal/wire/` | Dependency injection wiring |
| `pkg/kuscia/` | KusciaAPI gRPC client and helpers |
| `pkg/config/` | Viper-based configuration loading |
| `pkg/logger/` | Zap logger setup |
| `config/` | YAML configuration files |
| `deployments/` | Docker / K8s deployment manifests |

Config files live under `config/`.

### Privahub Frontend (`privahub/web/`)
pnpm workspace monorepo:

| Directory | Purpose |
|---|---|
| `apps/privahub/` | Main Privahub web app (Vite 5 + React 18) |
| `packages/design-system/` | `@privahub/design-system` component library |
| `packages/api-client/` | `@privahub/api-client` API schemas and mock client |
| `packages/dag-next/` | `@privahub/dag-next` DAG canvas engine |
| `packages/utils/` | `@privahub/utils` shared utilities |
| `tooling/tsconfig/` | Shared TypeScript configs |

---

## 6. Code Style Guidelines

### Kuscia (Go)
- Run `make fmt` (`go fmt ./...`) before committing.
- Imports grouped with `local-prefixes: github.com/secretflow/kuscia` (golangci-lint).
- Every file must have an Apache-2.0 license header.
- Use `pkg/errors` style wrapping; web layer uses `pkg/web/errorcode.Errs` for validation.
- Prefer constructors + interfaces for dependency injection.
- Table-driven tests with `testify` and `gomock`/`go.uber.org/mock`.
- Pre-commit hooks: gitleaks, golangci-lint, shellcheck, trailing-whitespace.

### SecretFlow (Python)
- Format with **Black** (line length 88, target py310).
- Sort imports with **isort** (`profile = "black"`).
- Use type hints widely; mypy is configured but not strict.
- Docstrings are often Numpy-style and bilingual.
- Every file starts with an Apache-2.0 Ant Group copyright header.

### Privahub Backend (Go)
- Run `make fmt` (`go fmt ./...`) before committing.
- Imports grouped with `local-prefixes: github.com/fengzhizi319/privahub` (golangci-lint).
- Every file must have an Apache-2.0 license header.
- Use `pkg/errors` style wrapping; HTTP handlers return standard JSON errors.
- Prefer constructors + interfaces for dependency injection.
- Table-driven tests with `testify` and `gomock`/`go.uber.org/mock`.
- Pre-commit hooks: gitleaks, golangci-lint, shellcheck, trailing-whitespace.

### Privahub Frontend (TypeScript/React)
- **Prettier**: printWidth 88, singleQuote, trailingComma all.
- **ESLint**: project root `eslint.config.js` + workspace overrides.
- Conventional Commits enforced by Husky/commitlint.
- lint-staged runs prettier, eslint on commit.
- State management uses **Zustand**.

---

## 7. Testing Instructions

### Kuscia
```bash
make test                                      # unit tests
make integration_test TEST_SUITE=center.base   # integration suite
make integration_test TEST_SUITE=all
```
Unit tests use `testify`, `gomock`, `gomonkey`, `go-sqlmock`, Kubernetes fake clients.

### SecretFlow
```bash
python -m pytest tests/ -v                     # sim mode
python -m pytest tests/ --env=prod -v          # MPC mode
python -m pytest tests/ -n auto --env=prod     # parallel
```
MPC tests marked `@pytest.mark.mpc(parties=[...])` are executed in spawned child processes. Configuration fixtures are in `tests/conftest.py`, `tests/sf_fixtures.py`, `tests/sf_config.py`.

### Privahub Backend
```bash
CGO_ENABLED=1 go test ./...
# or by package
CGO_ENABLED=1 go test ./internal/service/...
```
Tests use `testify`, `gomock`/`go.uber.org/mock`, and `sqlmock`/`gorm` where applicable.

### Privahub Frontend
```bash
corepack pnpm test
corepack pnpm --filter @privahub/app test
```
Vitest config uses `jsdom`, `msw`, and `identity-obj-proxy` for CSS/SVG.

---

## 8. Runtime Architecture & Ports

### Non-Docker local development (`run-all-no-docker.sh`)
The script at `/home/charles/code/sfwork/scripts/run-all-no-docker.sh` boots everything in this order:

1. Activate conda env `sf310` and build/install local SecretFlow (`pip install -e ./secretflow`)
2. Build Kuscia binary (`kuscia/hack/build.sh -t kuscia`)
3. Start Kuscia Master via `kuscia/scripts/run_local_kuscia.sh` master (requires sudo for ports 53/80)
4. Build Privahub backend (`CGO_ENABLED=1 go build -o bin/privahub ./cmd/server`)
5. Start Privahub backend with `./config/privahub.yaml`
6. Start Privahub frontend

Default local ports:

| Service | Port | Notes |
|---|---|---|
| Privahub frontend dev server | 8000 | Vite dev, proxies `/api` to backend |
| Privahub backend HTTP | 8080 | Go HTTP server |
| Privahub inner API | 9001 | cluster-internal port (no auth) |
| Kuscia API gRPC | 8083 | internal, non-Docker mode |
| Kuscia Envoy internal | 80 | non-Docker mode |
| CoreDNS | 53 | requires root |

Dev login: `admin` / `12345678`.

### Local development with Docker Kuscia

When Kuscia master + alice + bob are running via local Docker with host port mappings (as in the current setup), use these connection parameters for Privahub backend:

| Config / Env Var | Value | Notes |
|---|---|---|
| `kuscia.api_address` / `PRIVAHUB_KUSCIA_API_ADDRESS` | `127.0.0.1` | Kuscia API gRPC host |
| `kuscia.api_port` / `PRIVAHUB_KUSCIA_API_PORT` | `18083` | Mapped from container port 8083 |
| `kuscia.gateway` / `PRIVAHUB_KUSCIA_GATEWAY` | `127.0.0.1:18080` | 容器 Envoy 跨域网关端口 1080 映射到宿主机 18080（非 Docker 模式下使用 80） |
| `kuscia.protocol` / `PRIVAHUB_KUSCIA_PROTOCOL` | `notls` | Dev profile, no mTLS |
| `PRIVAHUB_DATA_DIR` | `${INSTALL_DIR:-$HOME/kuscia}/master/data` | 上传 CSV 的落盘根目录；dev-start.sh 自动设置为 Kuscia lite 节点数据目录的宿主机侧（`<kuscia_root>/master/data/<domain>/`），任务容器经 DataProxy 可直接读取 |

Use the dev profile to apply these defaults automatically:

```bash
export PRIVAHUB_PROFILE=dev
./bin/privahub -config ./config/privahub.yaml
```

The startup helper `scripts/dev-start.sh` sets this automatically.

### Key Kuscia ports (Docker deployment)
| Service | Default Port |
|---|---|
| KusciaAPI HTTP external | 8082 |
| KusciaAPI gRPC | 8083 |
| KusciaAPI HTTP internal | 8092 |
| DataMesh HTTP | 8070 |
| DataMesh gRPC | 8071 |
| ConfManager HTTP | 8060 |
| ConfManager gRPC | 8061 |
| Reporter HTTP | 8050 |
| Transport gRPC | 9090 |
| Gateway public (Envoy 跨域网关) | 1080 |
| Gateway internal | 80 |

---

## 9. Deployment Processes

### Docker (production)
- **Kuscia**: `scripts/deploy/start_standalone.sh center|p2p|cxc|cxp`, or `scripts/deploy/deploy.sh master|lite|autonomy ...`.
- **SecretFlow**: release/dev/GPU Docker images under `docker/release/` and `docker/dev/`.
- **Privahub**: `make image` (builds `bin/privahub` + frontend + container image).
- **All-in-one offline package**: legacy `privahub/scripts/pack/pack_allinone.sh` is no longer maintained for the new Go backend; use the per-project Docker images instead.

### Non-Docker (development)
Use `run-all-no-docker.sh`, or manually:

```bash
# 1. Install local SecretFlow (conda env sf310)
cd /home/charles/code/sfwork/secretflow
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate sf310
pip install -i https://mirrors.aliyun.com/pypi/simple/ kuscia
pip install -e .

# 2. Build Kuscia
cd /home/charles/code/sfwork/kuscia
bash hack/build.sh -t kuscia

# 3. Start Kuscia Master
export KUSCIA_HOME="/home/charles/code/sfwork/.local-kuscia"
sudo bash scripts/run_local_kuscia.sh master

# 4. Build Privahub backend
cd /home/charles/code/sfwork/privahub
CGO_ENABLED=1 go build -o bin/privahub ./cmd/server

# 5. Start Privahub backend (adjust profile for Docker vs non-Docker Kuscia)
export PRIVAHUB_PROFILE=dev   # dev profile uses Docker-mapped Kuscia ports
./bin/privahub -config ./config/privahub.yaml

# 7. Start Privahub frontend
cd /home/charles/code/sfwork/privahub/web
corepack enable
corepack pnpm install
corepack pnpm --filter @privahub/app dev
```

Stop everything with `bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh --stop`.

---

## 10. Security Considerations

- **mTLS**: Kuscia uses mTLS for cross-domain communication and KusciaAPI in production. The `dev` profile uses `kuscia.protocol=notls`.
- **Certificates**: Privahub development mode uses `notls` and does not require Java/JKS certificates. Production deployments should configure TLS certificates and keep them out of version control.
- **Authentication**: Privahub uses JWT tokens + user/token database (not Spring Security).
- **Authorization**: Kuscia uses Casbin; DataMesh enforces domaindata grants.
- **Secrets**: gitleaks runs in Kuscia pre-commit hooks. Do not hard-code passwords, tokens, or cert keys.
- **sudo**: Local Kuscia needs root for CoreDNS port 53. The helper script uses `sudo` internally.
- **Sensitive files**: Frontend `.env` proxy config is gitignored. Kuscia certificates under `.local-kuscia/var/certs/` are local-only.

---

## 11. Cross-Project Integration

When modifying code, understand which layer owns the contract:

- **Frontend ↔ Backend**: REST JSON under `/api/v1alpha1/*`. DTOs/VOs live in `privahub/internal/controller/http` and `privahub/internal/service`.
- **Backend ↔ Kuscia**: gRPC via the Kuscia client in `privahub/pkg/kuscia`. Config (`config/privahub*.yaml`) or `PRIVAHUB_*` env vars control the connection.
- **Kuscia ↔ SecretFlow**: Kuscia schedules containerized SecretFlow tasks; SecretFlow reads `DomainData` via DataMesh.
- **DataMesh ↔ SecretFlow**: gRPC + Apache Arrow Flight; `secretflow/kuscia/datamesh.py` is the client.
- **Protobuf contracts**: Shared `.proto` files are in `kuscia/proto/` and `secretflow/protos/`. Changing a proto requires regenerating stubs in all consuming languages.

---

## 12. Common Development Workflow

1. **Start from the root**: `/home/charles/code/sfwork`.
2. **Choose a launcher**:
   - Non-Docker all-in-one: `bash scripts/run-all-no-docker.sh`
   - Docker Kuscia + local backend/frontend: `bash scripts/dev-start.sh`
3. **Make backend changes**: `cd privahub && CGO_ENABLED=1 go build -o bin/privahub ./cmd/server`, restart backend.
4. **Make frontend changes**: `cd privahub/web && corepack enable && corepack pnpm --filter @privahub/app dev` supports hot reload.
5. **Make Kuscia changes**: `cd kuscia && bash hack/build.sh -t kuscia`, then restart Kuscia Master.
6. **Run tests** in the relevant subproject before committing.
7. **Check logs**: `logs/kuscia-master.log`, `logs/backend.log`, `logs/frontend.log`, plus per-project log directories.

---

## 13. Quick Reference

| Goal | Command |
|---|---|
| Build Kuscia | `cd kuscia && make build` |
| Test Kuscia | `cd kuscia && make test` |
| Build SecretFlow wheel | `cd secretflow && python -m build --wheel` |
| Test SecretFlow | `cd secretflow && python -m pytest tests/ --env=prod -v` |
| Build Privahub backend | `cd privahub && CGO_ENABLED=1 go build -o bin/privahub ./cmd/server` |
| Test Privahub backend | `cd privahub && CGO_ENABLED=1 go test ./...` |
| Build Privahub image | `cd privahub && make image` |
| Install frontend deps | `cd privahub/web && corepack enable && corepack pnpm install` |
| Dev frontend | `cd privahub/web && corepack pnpm --filter @privahub/app dev` |
| Test frontend | `cd privahub/web && corepack pnpm test` |
| Run all locally (non-Docker) | `bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh` |
| Stop all locally (non-Docker) | `bash /home/charles/code/sfwork/scripts/run-all-no-docker.sh --stop` |
| Start with Docker Kuscia | `bash /home/charles/code/sfwork/scripts/dev-start.sh` |
| Stop Docker Kuscia setup | `bash /home/charles/code/sfwork/scripts/dev-stop.sh` |
| Test privacy-java-sdk | `cd privacy-java-sdk && mvn test` |
| Test privacy-go-sdk | `cd privacy-go-sdk && go test ./...` |
| Test privacy-local-agent | `cd privacy-local-agent && PYTHONPATH=. pytest tests -q` |
