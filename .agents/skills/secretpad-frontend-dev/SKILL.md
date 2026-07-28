---
name: secretpad-frontend-dev
description: Develop the Privahub frontend. Use when the user asks about frontend code changes, UI components, pages, DAG canvas, theming, build, lint, tests, or frontend-backend integration. The active frontend lives in privahub/web/; privahub/frontend-src and secretpad-frontend are legacy copies that have been removed/deprecated.
---

# Privahub Frontend Development

The active frontend is in `privahub/web/`. Legacy frontend directories (`privahub/frontend-src/`, `secretpad-frontend/`) have been removed/deprecated as part of the migration.

## Stack

- Node.js >= 18.0.0, pnpm >= 8.8.0 (managed by `packageManager`, currently pnpm@11.7.0)
- React 18, Vite 5, Tailwind CSS
- TypeScript 5.x
- TanStack Router + TanStack Query v5
- Zustand for state management
- pnpm workspace monorepo
- Vitest + React Testing Library

## Project Structure

```
privahub/web/
├── apps/
│   └── privahub/              # Main Privahub web app (Vite 5 + React 18)
├── packages/
│   ├── design-system/          # @privahub/design-system component library
│   ├── api-client/             # @privahub/api-client OpenAPI-generated client + schemas
│   ├── dag-next/               # @privahub/dag-next DAG canvas engine
│   └── utils/                  # @privahub/utils shared utilities
├── tooling/
│   └── tsconfig/               # Shared TypeScript configs
└── docs/                       # Frontend migration / consistency docs
```

## Key Commands

```bash
cd privahub/web

# Install dependencies
corepack pnpm install

# Dev server (http://localhost:8000)
corepack pnpm --filter @privahub/app dev

# Build all packages and the main app
corepack pnpm run build

# Typecheck
corepack pnpm typecheck

# Test
corepack pnpm test

# Lint / format
corepack pnpm run lint
```

## Conventions

- Prettier: printWidth 88, singleQuote, trailingComma all
- State management: Zustand (auth/theme), TanStack Query (server state)
- REST API: `openapi-typescript` + `openapi-fetch` via `@privahub/api-client`
- Path alias: use relative imports or workspace package names (`@privahub/*`)
- Runtime schema validation: Zod `unwrapValidated`/`validated`
- All user-visible text through `shared/lib/i18n` dictionaries (zh-CN / en-US)

## Common Workflows

1. **Add a page**: Create `apps/privahub/src/pages/<page>/index.tsx`, register in `apps/privahub/src/router.tsx`, add sidebar entry and i18n keys.
2. **Add a DAG template**: Create `apps/privahub/src/features/dag-templates/templates/<name>.ts`, register in `apps/privahub/src/features/dag-templates/registry.ts`, add i18n keys.
3. **Theme change**: Tailwind classes + dark variants; no Ant Design theme config.
4. **DAG changes**: `packages/dag-next/src/`.
5. **Backend API change**: Update `openapi/secretpad.openapi.json`, regenerate types/client if needed; keep `packages/api-client/src/schemas/index.ts` in sync.

## Important Paths

- Main app: `apps/privahub/src/`
- Routes: `apps/privahub/src/router.tsx`
- Pages: `apps/privahub/src/pages/`
- Features: `apps/privahub/src/features/`
- Shared: `apps/privahub/src/shared/`
- API client: `packages/api-client/src/`
- DAG engine: `packages/dag-next/src/`
- i18n dictionaries: `apps/privahub/src/shared/lib/i18n/dictionaries.ts`
- Migration docs: `privahub/web/docs/frontend-migration-consistency.md`
