# Copilot instructions for this repository

## Stack

- Elixir
- Phoenix 1.8
- Phoenix LiveView
- HEEx templates
- Tailwind CSS v4
- Req for HTTP requests
- OTP process-based design where state ownership matters
- Gleam interop for Bitcoin transaction parsing via the external `btc_tx` library

Follow the project guidance in `/AGENTS.md`.

This repository is a Phoenix web application. When helping with this codebase:

## Core expectations

- Follow the Phoenix, LiveView, HEEx, Elixir, testing, JS, CSS, and UI rules in `AGENTS.md`
- Use `Req` for HTTP requests
- Prefer clear, maintainable solutions over clever abstractions
- Respect process ownership, supervision boundaries, and backpressure concerns
- Keep implementations aligned with Phoenix 1.8 conventions
- Use `mix precommit` when changes are complete and address any issues it reports

## Architecture guidance

When proposing or implementing changes:

- Explain where state should live
- Be explicit about whether a GenServer, Task, LiveView, or plain module/function is the right fit
- Call out failure modes and operational tradeoffs
- Prefer bounded resource usage over unbounded queues or uncontrolled concurrency
- When working with collections in LiveView, prefer streams where appropriate and follow the stream rules in `AGENTS.md`
- Prefer keeping Bitcoin transaction decoding and structural parsing inside `btc_tx` rather than duplicating parsing logic in Elixir

## UI and LiveView expectations

- Start LiveView templates with `<Layouts.app flash={@flash} ...>`
- Pass `current_scope` correctly when required
- Use the existing core components such as `<.input>` and `<.icon>`
- Do not introduce deprecated Phoenix or LiveView APIs
- Use Tailwind utility classes and custom CSS rules only
- Do not use inline `<script>` tags in templates

## Testing expectations

- Prefer focused tests with clear element-based assertions
- Use `Phoenix.LiveViewTest` helpers and stable DOM IDs
- Avoid `Process.sleep/1`
- Use `start_supervised!/1` for supervised processes in tests
- Test outcomes and behavior rather than implementation details

## Important project documents

- `/AGENTS.md`
- `/docs/btc_tx_api.md`
- `/docs/live_mempool_app_mvp_feasibility.md`
- `/docs/mempool-space-api.md`

When a task is closely related to one of these documents, consult it and keep the implementation aligned with it.