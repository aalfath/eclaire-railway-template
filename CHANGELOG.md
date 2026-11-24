# Changelog

Each entry is one version of this Railway template. Breaking changes are listed first.
Railway shows deployers an "update available" notice when `main` changes; read the entry before you apply it.

## 0.6.3-railway.1 (2026-11-24)

- First release: Eclaire v0.6.3 (`ghcr.io/eclaire-labs/eclaire:0.6.3@sha256:28cf083aa4fa9dae6c449dedcdcdb3214d607091194dc596df8058d1ebd823d1`) with Railway Postgres.
- The admin account is created on first boot from `ADMIN_EMAIL` / `ADMIN_PASSWORD`; public sign-up is closed.
- One OpenAI-compatible AI provider configured from `LLM_API_KEY`, `LLM_BASE_URL` and `LLM_MODEL`.
- Docling is optional (set `DOCLING_SERVER_URL` to use it); without it documents use the built-in extractors.
- Sized from the service's memory limit: Node heap, one worker below 1.5 GB, viewport-only bookmark screenshots below 2 GB, and Chromium/LibreOffice are killed before the app when memory runs out.
- README: Deploy on Railway button and resource notes (two volumes, so Trial plan or higher; 1 GB or more recommended for heavy bookmarks).
